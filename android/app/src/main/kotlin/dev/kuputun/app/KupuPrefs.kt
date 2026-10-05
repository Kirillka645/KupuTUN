package dev.kuputun.app

import android.content.Context

/** Small plain prefs shared by the tile / service / Flutter side (no secrets). */
object KupuPrefs {
    private const val FILE = "kuputun_native"
    const val TILE_TOGGLE = "toggleLast"
    const val TILE_BEST = "connectBest"
    const val TILE_APP = "openApp"

    private fun p(ctx: Context) = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun tileAction(ctx: Context): String = p(ctx).getString("tileAction", TILE_TOGGLE) ?: TILE_TOGGLE
    fun setTileAction(ctx: Context, v: String) = p(ctx).edit().putString("tileAction", v).apply()

    fun notifSpeed(ctx: Context): Boolean = p(ctx).getBoolean("notifSpeed", true)
    fun setNotifSpeed(ctx: Context, v: Boolean) = p(ctx).edit().putBoolean("notifSpeed", v).apply()

    fun lastServerName(ctx: Context): String? = p(ctx).getString("lastServer", null)
    fun setLastServerName(ctx: Context, v: String) = p(ctx).edit().putString("lastServer", v).apply()
}
