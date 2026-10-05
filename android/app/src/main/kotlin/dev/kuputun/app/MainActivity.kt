package dev.kuputun.app

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.TrafficStats
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import dev.kuputun.core.bridge.Bridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPrepare: MethodChannel.Result? = null
    private var events: EventChannel.EventSink? = null

    private var pendingAction: String? = null

    companion object {
        private const val REQ_VPN = 0x4b54
        const val EXTRA_ACTION = "dev.kuputun.app.ACTION"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        takeAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeAction(intent)
    }

    /** Tile "connect best": delivered live if Flutter listens, else kept for takePendingAction. */
    private fun takeAction(i: Intent?) {
        val a = i?.getStringExtra(EXTRA_ACTION) ?: return
        i.removeExtra(EXTRA_ACTION)
        if (!VpnController.action(a)) pendingAction = a
    }

    /** Runs blocking Go calls off the UI thread. */
    private fun bg(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val v = block()
                main.post { result.success(if (v == Unit) null else v) }
            } catch (t: Throwable) {
                // Throwable, not Exception: loading the gomobile library throws
                // UnsatisfiedLinkError (an Error). Swallowing it left the Dart
                // future pending forever and the UI stuck on "Connecting…".
                main.post { result.error("core", t.message ?: t.toString(), null) }
            }
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        // Lets VpnController refresh the home-screen widget on state changes.
        VpnController.attach(this)
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "kuputun/core").setMethodCallHandler { call, r ->
            when (call.method) {
                "setAssetDir" -> bg(r) { Bridge.setAssetDir(call.argument<String>("dir")!!) }
                "startInstance" -> bg(r) {
                    Bridge.startInstance(call.argument<String>("id")!!, call.argument<String>("core")!!, call.argument<String>("config")!!)
                }
                "stopInstance" -> bg(r) { Bridge.stopInstance(call.argument<String>("id")!!) }
                "stopAll" -> bg(r) { Bridge.stopAll() }
                // The three below are cheap mutex/exporter reads, but they still
                // cross into native code, so keep them off the platform thread too.
                "isRunning" -> bg(r) { Bridge.isRunning(call.argument<String>("id")!!) }
                "freePorts" -> bg(r) { Bridge.freePorts((call.argument<Int>("n") ?: 1).toLong()) }
                "traffic" -> bg(r) { Bridge.trafficStats(call.argument<String>("id")!!) }
                "version" -> bg(r) { Bridge.version() }
                else -> r.notImplemented()
            }
        }

        MethodChannel(messenger, "kuputun/vpn").setMethodCallHandler { call, r ->
            when (call.method) {
                "prepare" -> {
                    val i = VpnService.prepare(this)
                    if (i == null) r.success(true) else {
                        pendingPrepare = r
                        @Suppress("DEPRECATION") startActivityForResult(i, REQ_VPN)
                    }
                }
                "start" -> {
                    VpnController.startService(this, JSONObject(call.arguments as Map<*, *>))
                    r.success(null)
                }
                "stop" -> {
                    VpnController.stop(this)
                    r.success(null)
                }
                "saveLastConfig" -> bg(r) { LastConfigStore.save(this, JSONObject(call.arguments as Map<*, *>)) }
                "openVpnSettings" -> {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                    r.success(null)
                }
                "installedApps" -> bg(r) {
                    // Launchable apps only: visible through <queries> without the
                    // QUERY_ALL_PACKAGES permission that Google Play restricts.
                    val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    @Suppress("DEPRECATION")
                    packageManager.queryIntentActivities(launcher, 0)
                        .map { it.activityInfo.applicationInfo }
                        .distinctBy { it.packageName }
                        .filter { it.packageName != packageName }
                        .map {
                            mapOf(
                                "package" to it.packageName,
                                "label" to packageManager.getApplicationLabel(it).toString(),
                                "system" to ((it.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                            )
                        }
                }
                "status" -> r.success(
                    mapOf(
                        "running" to VpnController.running,
                        "serverId" to VpnController.serverId,
                        "since" to VpnController.since,
                    )
                )
                "setNativePrefs" -> {
                    KupuPrefs.setTileAction(this, call.argument<String>("tileAction") ?: KupuPrefs.TILE_TOGGLE)
                    KupuPrefs.setNotifSpeed(this, call.argument<Boolean>("notifSpeed") ?: true)
                    QsTileService.requestUpdate()
                    r.success(null)
                }
                "takePendingAction" -> {
                    r.success(pendingAction)
                    pendingAction = null
                }
                "traffic" -> {
                    val uid = Process.myUid()
                    r.success(mapOf("up" to TrafficStats.getUidTxBytes(uid), "down" to TrafficStats.getUidRxBytes(uid)))
                }
                else -> r.notImplemented()
            }
        }

        EventChannel(messenger, "kuputun/vpn_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                events = sink
                VpnController.listener = { m -> main.post { events?.success(m) } }
            }
            override fun onCancel(args: Any?) {
                events = null
                VpnController.listener = null
            }
        })
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            pendingPrepare?.success(resultCode == RESULT_OK)
            pendingPrepare = null
        }
    }

    override fun onDestroy() {
        VpnController.listener = null
        events = null
        // The VPN consent dialog never returns once the activity is gone; complete
        // the pending call so the Dart future does not leak forever.
        pendingPrepare?.let { runCatching { it.success(false) } }
        pendingPrepare = null
        io.shutdown()
        super.onDestroy()
    }

    @Suppress("unused")
    private fun jsonList(a: JSONArray?) = (0 until (a?.length() ?: 0)).map { a!!.get(it) }
}
