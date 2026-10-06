package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Small encrypted mirror for background Telecom API calls. Never logs values. */
internal object NativeCallCredentials {
    private const val prefsName = "omnidesk_managed_call_credentials"
    private const val blobKey = "encrypted_session"
    private const val alias = "omnidesk_managed_call_session_v1"
    private const val transformation = "AES/GCM/NoPadding"

    data class Session(val baseUrl: String, val accessToken: String, val workspaceId: String, val installationId: String)

    @Synchronized fun write(context: Context, baseUrl: String, token: String, workspaceId: String, installationId: String) {
        require(baseUrl.startsWith("https://") && token.isNotBlank() && installationId.isNotBlank())
        val bytes = JSONObject().put("baseUrl", baseUrl.trimEnd('/')).put("token", token)
            .put("workspaceId", workspaceId).put("installationId", installationId).toString().toByteArray()
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(bytes)
        val blob = ByteBuffer.allocate(4 + cipher.iv.size + encrypted.size)
            .putInt(cipher.iv.size).put(cipher.iv).put(encrypted).array()
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
            .putString(blobKey, Base64.encodeToString(blob, Base64.NO_WRAP)).commit()
    }

    @Synchronized fun read(context: Context): Session? = try {
        val encoded = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).getString(blobKey, null) ?: return null
        val blob = ByteBuffer.wrap(Base64.decode(encoded, Base64.NO_WRAP))
        val ivSize = blob.int
        require(ivSize in 12..16 && blob.remaining() > ivSize)
        val iv = ByteArray(ivSize).also(blob::get)
        val ciphertext = ByteArray(blob.remaining()).also(blob::get)
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        val json = JSONObject(String(cipher.doFinal(ciphertext)))
        Session(json.getString("baseUrl"), json.getString("token"), json.optString("workspaceId"), json.getString("installationId"))
    } catch (_: Exception) { null }

    @Synchronized fun clear(context: Context) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit().remove(blobKey).commit()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }
}
