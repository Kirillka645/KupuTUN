package dev.kuputun.app

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import dev.kuputun.core.bridge.Bridge
import org.json.JSONObject

/**
 * Starts/stops the proxy core and the VpnService from anywhere
 * (Flutter, tile, widget, boot, always-on).
 */
object VpnController {
    @Volatile var running = false
        internal set
    /** Current session (valid while [running]). */
    @Volatile var serverId: String? = null
    @Volatile var serverName: String? = null
    @Volatile var since: Long = 0L
    var listener: ((Map<String, Any?>) -> Unit)? = null

    /** Application context of whichever component started first; lets [notify]
     *  refresh the home-screen widget without holding on to an Activity. */
    @Volatile private var appContext: Context? = null

    fun attach(ctx: Context) {
        appContext = ctx.applicationContext
    }

    fun notify(state: String, message: String? = null) {
        running = state == "connected"
        if (!running) since = 0L
        listener?.invoke(
            mapOf("state" to state, "message" to message, "serverId" to serverId, "since" to since)
        )
        QsTileService.requestUpdate()
        // The widget reads the state only when it is repainted, so a toggle from
        // the app used to leave it showing a stale ON/OFF.
        appContext?.let { c -> KupuWidget.refresh(c) }
    }

    /** Asks the Flutter side to do something (if the UI is alive). */
    fun action(name: String): Boolean {
        val l = listener ?: return false
        l(mapOf("state" to "action", "message" to name))
        return true
    }

    /** Starts the core from the last saved config, then the VPN. */
    fun startFromLast(ctx: Context): Boolean {
        attach(ctx)
        if (VpnService.prepare(ctx) != null) return false // needs UI consent
        val last = LastConfigStore.load(ctx) ?: return false
        return try {
            Bridge.setAssetDir(java.io.File(ctx.filesDir, "assets").absolutePath) // == Dart getApplicationSupportDirectory()/assets
            Bridge.startInstance("main", last.getString("core"), last.getString("config"))
            startService(ctx, last)
            true
        } catch (e: Throwable) {
            notify("error", e.message)
            false
        }
    }

    fun startService(ctx: Context, args: JSONObject) {
        attach(ctx)
        val i = Intent(ctx, KupuVpnService::class.java).setAction(KupuVpnService.ACTION_START)
            .putExtra(KupuVpnService.EXTRA_ARGS, args.toString())
        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
    }

    fun stop(ctx: Context) {
        attach(ctx)
        val i = Intent(ctx, KupuVpnService::class.java).setAction(KupuVpnService.ACTION_STOP)
        // Android 8+ refuses to start a service from the background; if the command
        // cannot be delivered, stop the service directly instead of throwing.
        runCatching { ctx.startService(i) }.onFailure {
            runCatching { ctx.stopService(Intent(ctx, KupuVpnService::class.java)) }
            notify("disconnected")
        }
    }

    fun toggle(ctx: Context) {
        if (running) stop(ctx) else startFromLast(ctx)
    }
}
