package dev.kuputun.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.TrafficStats
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import dev.kuputun.core.bridge.Bridge
import org.json.JSONObject

/**
 * TUN owner. The core (Xray/sing-box) runs in-process and exposes SOCKS on
 * socksPort; tun2socks reads packets from the VpnService fd and forwards them.
 *
 * Decisions:
 *  - our own package is always excluded from the tunnel, so the core's
 *    outbound sockets never loop (no need for protect() per socket);
 *  - IPv6 is routed into the tunnel (::/0) and rejected by the core, which
 *    prevents IPv6 leaks on dual-stack networks;
 *  - DNS points at an in-tunnel address and is hijacked by the core.
 *  - if the core dies, the TUN stays up with nowhere to go = kill switch.
 */
class KupuVpnService : VpnService() {
    companion object {
        const val ACTION_START = "dev.kuputun.app.START"
        const val ACTION_STOP = "dev.kuputun.app.STOP"
        const val EXTRA_ARGS = "args"
        private const val CHANNEL = "vpn"
        private const val NOTIF_ID = 1
    }

    private var tun: ParcelFileDescriptor? = null
    private val ui = Handler(Looper.getMainLooper())
    /** The Android main thread is also Flutter's platform thread: never block it. */
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var session = "KupuTUN"
    private var lastUp = -1L
    private var lastDown = -1L
    private var lastTick = 0L
    private val ticker = object : Runnable {
        override fun run() {
            if (tun == null) return
            runCatching { getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification()) }
            ui.postDelayed(this, 2000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // Lets VpnController refresh the home-screen widget on state changes.
        VpnController.attach(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }
        // Everything below this line was reached through startForegroundService
        // (Android 8+), which enforces a ~5 s deadline. Promote to foreground
        // *before* loading the config and building the core — that work can take
        // longer than the deadline on a cold start, and missing it kills the app
        // with ForegroundServiceDidNotStartInTimeException.
        startForegroundCompat()

        if (intent?.action == ACTION_START) {
            startVpn(JSONObject(intent.getStringExtra(EXTRA_ARGS) ?: "{}"))
            return START_STICKY
        }

        // Always-on VPN / system restart: the intent action is android.net.VpnService or null.
        val last = LastConfigStore.load(this)
        if (last == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val core = last.optString("core")
        val config = last.optString("config")
        io.execute {
            try {
                if (!Bridge.isRunning("main")) Bridge.startInstance("main", core, config)
                ui.post { startVpn(last) }
            } catch (e: Throwable) {
                ui.post {
                    VpnController.notify("error", e.message)
                    stopVpn()
                }
            }
        }
        return START_STICKY
    }

    private fun startVpn(a: JSONObject) {
        session = a.optString("session", "KupuTUN").ifBlank { "KupuTUN" }
        VpnController.serverId = a.optString("serverId", "").ifBlank { null }
        VpnController.serverName = session
        KupuPrefs.setLastServerName(this, session)
        lastUp = -1L; lastDown = -1L
        startForegroundCompat()
        try {
            tun?.close()
            val mtu = a.optInt("mtu", 1500)
            val b = Builder()
                .setSession(a.optString("session", "KupuTUN"))
                .setMtu(mtu)
                .addAddress("172.19.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer(a.optString("dns", "172.19.0.2"))
                .setBlocking(false)
            if (a.optBoolean("ipv6", true)) {
                b.addAddress("fdfe:dcba:9876::1", 126)
                b.addRoute("::", 0)
            }
            if (Build.VERSION.SDK_INT >= 29) b.setMetered(false)
            val pkgs = a.optJSONArray("packages")
            val list = (0 until (pkgs?.length() ?: 0)).map { pkgs!!.getString(it) }.filter { it != packageName }
            when (a.optString("splitMode", "off")) {
                "onlySelected" -> list.forEach { runCatching { b.addAllowedApplication(it) } }
                "exceptSelected" -> {
                    b.addDisallowedApplication(packageName)
                    list.forEach { runCatching { b.addDisallowedApplication(it) } }
                }
                else -> b.addDisallowedApplication(packageName)
            }
            val pfd = b.establish() ?: throw IllegalStateException("VPN permission revoked")
            tun = pfd
            // tun2socks closes its device fd on stop. Give it its own dup'ed fd so
            // the ParcelFileDescriptor is never closed twice (double close /
            // fdsan abort / closing a reused fd number = crash on "Отключить").
            val nativeFd = pfd.dup().detachFd()
            try {
                Bridge.startTun2Socks("fd://$nativeFd", a.optInt("socksPort", 10808).toLong(), mtu.toLong(), "warn")
            } catch (e: Exception) {
                runCatching { ParcelFileDescriptor.adoptFd(nativeFd).close() }
                throw e
            }
            if (VpnController.since == 0L || !VpnController.running) VpnController.since = System.currentTimeMillis()
            VpnController.notify("connected")
            ui.removeCallbacks(ticker)
            if (KupuPrefs.notifSpeed(this)) ui.post(ticker)
            else runCatching { getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification()) }
        } catch (e: Exception) {
            VpnController.notify("error", e.message)
            stopVpn()
        }
    }

    private fun stopVpn() {
        ui.removeCallbacks(ticker)
        val t = tun
        tun = null
        // Report and tear down the foreground notification immediately...
        VpnController.notify("disconnected")
        runCatching {
            if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        }
        // ...but run the blocking native teardown off the main thread: engine.Stop()
        // joins goroutines and Xray's Close() closes every connection, which used
        // to freeze the UI (and trip the ANR watchdog) on every disconnect.
        io.execute {
            runCatching { Bridge.stopTun2Socks() } // closes its own dup'ed fd
            runCatching { Bridge.stopInstance("main") }
            runCatching { t?.close() }
        }
        stopSelf()
    }

    override fun onRevoke() = stopVpn() // another VPN took over / user revoked

    override fun onDestroy() {
        ui.removeCallbacks(ticker)
        val t = tun
        tun = null
        // The service can be destroyed without stopVpn() (system kill, stopService).
        // Always release the core and the global flag: otherwise the tile, the
        // widget and Dart keep reporting a tunnel that is gone, and the next start
        // hits "Not allowed to start service Intent" because the service is dead.
        io.execute {
            runCatching { Bridge.stopTun2Socks() }
            runCatching { Bridge.stopInstance("main") }
            runCatching { t?.close() }
        }
        io.shutdown() // lets the teardown above finish
        if (VpnController.running) VpnController.notify("disconnected")
        super.onDestroy()
    }

    /** Bytes (up, down) through the proxy core; falls back to our UID counters. */
    private fun counters(): Pair<Long, Long> {
        runCatching {
            val j = JSONObject(Bridge.trafficStats("main"))
            val up = j.optLong("up", 0L)
            val down = j.optLong("down", 0L)
            if (up > 0L || down > 0L) return up to down
        }
        val uid = Process.myUid()
        return TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L) to TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
    }

    private fun speed(bps: Long): String = when {
        bps >= 1_000_000 -> String.format(java.util.Locale.US, "%.1f МБ/с", bps / 1_000_000.0)
        bps >= 1_000 -> String.format(java.util.Locale.US, "%.0f КБ/с", bps / 1_000.0)
        else -> "$bps Б/с"
    }

    private fun total(b: Long): String = when {
        b >= 1_000_000_000 -> String.format(java.util.Locale.US, "%.2f ГБ", b / 1_000_000_000.0)
        b >= 1_000_000 -> String.format(java.util.Locale.US, "%.1f МБ", b / 1_000_000.0)
        else -> String.format(java.util.Locale.US, "%.0f КБ", b / 1_000.0)
    }

    private fun buildNotification(): Notification {
        val connected = tun != null
        val now = System.currentTimeMillis()
        var text = if (connected) "Защищено" else "Подключение…"
        val showSpeed = KupuPrefs.notifSpeed(this)
        if (connected && showSpeed) {
            val (up, down) = counters()
            val dt = (now - lastTick).coerceAtLeast(1L)
            if (lastUp >= 0L) {
                val upS = ((up - lastUp).coerceAtLeast(0L) * 1000) / dt
                val downS = ((down - lastDown).coerceAtLeast(0L) * 1000) / dt
                text = "↓ ${speed(downS)}   ↑ ${speed(upS)}"
            }
            lastUp = up; lastDown = down; lastTick = now
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, KupuVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE
        )
        val b = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this))
            .setSmallIcon(R.drawable.ic_tile)
            .setColor(0xFF0186F2.toInt())
            .setContentTitle(if (connected) "Подключено · $session" else "KupuTUN · $session")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(Notification.Action.Builder(null, "Отключить", stop).build())
        if (connected && VpnController.since > 0L) {
            b.setWhen(VpnController.since).setShowWhen(true).setUsesChronometer(true)
            if (showSpeed && lastUp >= 0L) b.setSubText("${total(lastDown)} ↓ · ${total(lastUp)} ↑")
        }
        if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return b.build()
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN-подключение", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                }
            )
        }
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }
}
