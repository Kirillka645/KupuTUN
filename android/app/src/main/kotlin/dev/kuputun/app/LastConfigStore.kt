package dev.kuputun.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Last connection (core + JSON config + VPN args) encrypted with a
 * non-exportable AES-256-GCM key in Android Keystore. Used by the Quick
 * Settings tile, widget, boot receiver and Always-on VPN, which must connect
 * without the Flutter UI running.
 */
object LastConfigStore {
    private const val ALIAS = "kuputun.lastconfig.v1"
    private const val FILE = "last_config.bin"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    fun save(ctx: Context, json: JSONObject) {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val ct = c.doFinal(json.toString().toByteArray(Charsets.UTF_8))
        val out = c.iv + ct // iv is 12 bytes
        File(ctx.noBackupFilesDir, FILE).writeBytes(out)
    }

    fun load(ctx: Context): JSONObject? {
        val f = File(ctx.noBackupFilesDir, FILE)
        if (!f.exists()) return null
        return try {
            val all = f.readBytes()
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all.copyOfRange(0, 12)))
            JSONObject(String(c.doFinal(all.copyOfRange(12, all.size)), Charsets.UTF_8))
        } catch (e: Exception) {
            null
        }
    }

    @Suppress("unused")
    fun debugFingerprint(ctx: Context): String? =
        load(ctx)?.optString("core")?.let { Base64.encodeToString(it.toByteArray(), Base64.NO_WRAP) }
}
