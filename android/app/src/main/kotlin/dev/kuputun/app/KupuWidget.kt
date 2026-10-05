package dev.kuputun.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** Home-screen widget with a single connect/disconnect button. */
class KupuWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        ids.forEach { mgr.updateAppWidget(it, views(ctx)) }
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        super.onReceive(ctx, intent)
        if (intent.action == ACTION_TOGGLE) {
            VpnController.toggle(ctx)
            refresh(ctx)
        }
    }

    companion object {
        const val ACTION_TOGGLE = "dev.kuputun.app.TOGGLE"

        /** Repaints every widget instance; also called when the app, the tile or
         *  the service changes the state rather than the widget itself. */
        fun refresh(ctx: Context) {
            runCatching {
                AppWidgetManager.getInstance(ctx)
                    .updateAppWidget(ComponentName(ctx, KupuWidget::class.java), views(ctx))
            }
        }

        private fun views(ctx: Context) = RemoteViews(ctx.packageName, R.layout.widget).apply {
            setTextViewText(R.id.widget_state, if (VpnController.running) "ON" else "OFF")
            val pi = PendingIntent.getBroadcast(
                ctx, 0, Intent(ctx, KupuWidget::class.java).setAction(ACTION_TOGGLE),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            setOnClickPendingIntent(R.id.widget_root, pi)
        }
    }
}
