package dev.kuputun.app

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile. Behaviour is configurable in the app
 * (Settings → Плитка быстрых настроек):
 *  - toggleLast:  one tap connects to the last server / disconnects;
 *  - connectBest: opens the app, which picks the best server and connects;
 *  - openApp:     just opens the app.
 * While connected a tap always disconnects (except openApp).
 */
class QsTileService : TileService() {
    companion object {
        private var appCtx: Context? = null
        fun requestUpdate() {
            val c = appCtx ?: return
            runCatching { requestListeningState(c, ComponentName(c, QsTileService::class.java)) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        appCtx = applicationContext
    }

    override fun onTileAdded() = render()
    override fun onStartListening() = render()

    override fun onClick() {
        val mode = KupuPrefs.tileAction(this)
        val run = Runnable { handleClick(mode) }
        // Starting a VPN from the lock screen would bypass the keyguard.
        if (isLocked && !(VpnController.running && mode != KupuPrefs.TILE_APP)) unlockAndRun(run) else run.run()
    }

    private fun handleClick(mode: String) {
        when {
            mode == KupuPrefs.TILE_APP -> openApp(null)
            VpnController.running -> VpnController.stop(this)
            // The UI owns the tester / Smart Score: open it with a "connect best" request.
            mode == KupuPrefs.TILE_BEST -> openApp("connect_best")
            !VpnController.startFromLast(this) -> openApp(null) // no consent / no saved config yet
        }
        render()
    }

    private fun openApp(action: String?) {
        val i = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (action != null) i.putExtra(MainActivity.EXTRA_ACTION, action)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 2, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            )
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated") startActivityAndCollapse(i)
        }
    }

    private fun render() {
        val t = qsTile ?: return
        val on = VpnController.running
        t.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.icon = Icon.createWithResource(this, R.drawable.ic_tile)
        t.label = "KupuTUN"
        val server = (if (on) VpnController.serverName else null) ?: KupuPrefs.lastServerName(this)
        val sub = when {
            on -> server ?: "Подключено"
            KupuPrefs.tileAction(this) == KupuPrefs.TILE_BEST -> "Лучший сервер"
            KupuPrefs.tileAction(this) == KupuPrefs.TILE_APP -> "Открыть"
            else -> server ?: "Отключено"
        }
        if (Build.VERSION.SDK_INT >= 29) t.subtitle = sub
        t.contentDescription = "KupuTUN: $sub"
        t.updateTile()
    }
}
