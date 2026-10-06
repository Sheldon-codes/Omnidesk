package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Implements the existing Dart CallApi wire contract for background managed calls. */
internal class ManagedCallBackendClient(context: Context) {
    class HttpFailure(val status: Int) : IllegalStateException("managed_call_api_http_$status")
    data class Outbound(val callId: String, val callSid: String, val number: String)
    private val app = context.applicationContext
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS).callTimeout(25, TimeUnit.SECONDS).build()
    @Volatile private var activeCallSession: NativeCallCredentials.Session? = null

    fun accept(callId: String, offerId: String): JSONObject {
        validateId(callId); validateId(offerId)
        val session = credentials().also { activeCallSession = it }
        val response = post(session, "/calls/$callId/accept", JSONObject()
            .put("installation_id", session.installationId).put("offer_id", offerId))
        val acceptedId = response.optString("call_id").ifBlank { response.optString("id") }
        check(acceptedId.isNotBlank() && acceptedId == callId) { "accept_identity_mismatch" }
        val acceptedOffer = response.optString("offer_id")
        check(acceptedOffer.isBlank() || acceptedOffer == offerId) { "accept_offer_mismatch" }
        return response
    }

    fun mediaConfig(): JSONObject {
        val session = activeCallSession ?: credentials()
        val response = get(session, "/calls/media-config")
        val webrtc = response.optJSONObject("webrtc") ?: JSONObject()
        check(response.optString("provider") == "africas_talking" && webrtc.optString("token").isNotBlank()) {
            "media_config_unavailable"
        }
        return JSONObject().put("gatewayUrl", webrtc.optString("gateway_url", webrtc.optString("gatewayUrl")))
            .put("token", webrtc.optString("token"))
    }

    fun mediaReady(callId: String, offerId: String) {
        validateId(callId); validateId(offerId)
        val session = activeCallSession ?: credentials()
        post(session, "/calls/$callId/media-ready", JSONObject()
            .put("installation_id", session.installationId).put("offer_id", offerId).put("transport", "webrtc"))
    }

    fun initiate(number: String): Outbound {
        val session = credentials().also { activeCallSession = it }
        val response = post(session, "/calls/initiate", JSONObject().put("to_number", number))
        return decodeOutbound(response, number)
    }

    fun complete(callSid: String, connectedSeconds: Long) {
        validateId(callSid)
        val session = activeCallSession ?: credentials()
        post(session, "/calls/complete", JSONObject()
            .put("call_sid", callSid).put("duration", connectedSeconds.coerceAtLeast(0)))
        activeCallSession = null
    }

    fun end(callId: String, reason: String) {
        validateId(callId)
        val session = activeCallSession ?: NativeCallCredentials.read(app) ?: return
        post(session, "/calls/$callId/end", JSONObject().put("reason", reason))
        activeCallSession = null
    }

    fun decline(callId: String, offerId: String, reason: String) {
        validateId(callId); validateId(offerId)
        val session = NativeCallCredentials.read(app) ?: return
        post(session, "/calls/$callId/decline", JSONObject()
            .put("installation_id", session.installationId)
            .put("offer_id", offerId).put("reason", reason))
    }

    fun clearCallSession() { activeCallSession = null }

    private fun credentials() = NativeCallCredentials.read(app) ?: error("managed_call_session_unavailable")

    private fun validateId(value: String) {
        require(value.matches(Regex("[A-Za-z0-9_-]{1,128}"))) { "managed_call_identity_invalid" }
    }

    private fun get(session: NativeCallCredentials.Session, path: String): JSONObject = execute(session, path, null)
    private fun post(session: NativeCallCredentials.Session, path: String, payload: JSONObject): JSONObject = execute(session, path, payload)

    private fun execute(session: NativeCallCredentials.Session, path: String, payload: JSONObject?): JSONObject {
        require(path.startsWith("/calls/"))
        val builder = Request.Builder().url(session.baseUrl + path)
            .header("Accept", "application/json").header("Content-Type", "application/json")
            .header("Authorization", "Bearer ${session.accessToken}")
        if (session.workspaceId.isNotBlank()) builder.header("X-Workspace-Id", session.workspaceId)
        val request = builder.method(if (payload == null) "GET" else "POST",
            payload?.toString()?.toRequestBody(JSON)).build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                Log.w(TAG, "Managed call API failed path=$path status=${response.code}")
                throw HttpFailure(response.code)
            }
            val root = JSONObject(response.body?.string().orEmpty())
            return root.optJSONObject("data") ?: root
        }
    }

    internal companion object {
        private const val TAG = "OmniDeskManagedCall"
        private val JSON = "application/json; charset=utf-8".toMediaType()
        fun decodeOutbound(response: JSONObject, dialedNumber: String): Outbound {
            check(response.optBoolean("success", true)) { "outbound_initiate_rejected" }
            val callId = response.optString("call_id")
            val callSid = response.optString("call_sid")
            require(callId.matches(Regex("[A-Za-z0-9_-]{1,128}")) &&
                callSid.matches(Regex("[A-Za-z0-9_-]{1,128}"))) { "outbound_identity_invalid" }
            return Outbound(callId, callSid,
                response.optString("normalized_to_number").ifBlank { dialedNumber })
        }
    }
}
