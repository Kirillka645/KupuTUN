package dev.kuputun.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Reconnects after reboot if the VPN was on (consent must already be granted). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val last = LastConfigStore.load(ctx) ?: return
        if (last.optBoolean("autoConnect", false)) VpnController.startFromLast(ctx)
    }
}
