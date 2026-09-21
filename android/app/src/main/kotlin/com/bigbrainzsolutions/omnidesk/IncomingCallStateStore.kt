package com.bigbrainzsolutions.omnidesk

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Durable, credential-free hand-off between FCM, Android Telecom and Flutter.
 * Event de-duplication and call-presentation de-duplication are deliberately
 * separate: a cancellation event shares an offer identity with its incoming
 * event and must never be discarded.
 */
object IncomingCallStateStore {
    private const val preferencesName = "omnidesk_incoming_call"
    private const val offerKey = "offer_json"
    private const val fcmTokenKey = "fcm_token"
    private const val actionKey = "pending_action_json"
    private const val eventIdsKey = "processed_event_ids"
    private const val activePresentationKey = "active_presentation_key"
    private const val presentationReceiptKey = "presentation_receipt_json"
    private const val maxEventIds = 96
    private val lock = Any()

    fun markEventIfNew(context: Context, eventId: String): Boolean = synchronized(lock) {
        if (eventId.isBlank()) return false
        val prefs = preferences(context)
        val values = JSONArray(prefs.getString(eventIdsKey, "[]") ?: "[]")
        val ids = mutableListOf<String>()
        for (index in 0 until values.length()) values.optString(index).takeIf { it.isNotBlank() }?.let(ids::add)
        if (ids.contains(eventId)) return false
        ids.add(eventId)
        prefs.edit().putString(eventIdsKey, JSONArray(ids.takeLast(maxEventIds)).toString()).commit()
        true
    }

    fun saveIncomingOffer(context: Context, payload: Map<String, String>): Boolean = synchronized(lock) {
        if (payload["type"]?.lowercase() != "incoming_call") return false
        val required = listOf("call_id", "offer_id", "caller_number", "workspace_id", "event_id")
        if (required.any { payload[it].isNullOrBlank() }) return false
        val json = JSONObject().also { target -> payload.forEach { (key, value) -> target.put(key, value) } }
        preferences(context).edit().putString(offerKey, json.toString()).commit()
    }

    fun takeOffer(context: Context): Map<String, Any?>? = synchronized(lock) {
        val prefs = preferences(context)
        val raw = prefs.getString(offerKey, null) ?: return null
        prefs.edit().remove(offerKey).commit()
        jsonMap(raw)
    }

    fun isPresentationActive(context: Context, callId: String, offerId: String): Boolean =
        preferences(context).getString(activePresentationKey, null) == presentationKey(callId, offerId)

    fun markPresentationActive(context: Context, callId: String, offerId: String) {
        preferences(context).edit().putString(activePresentationKey, presentationKey(callId, offerId)).commit()
    }

    fun savePresentationReceipt(
        context: Context,
        callId: String,
        offerId: String,
        receivedAt: String,
        nativePresentedAt: String,
    ) {
        preferences(context).edit().putString(
            presentationReceiptKey,
            JSONObject()
                .put("callId", callId)
                .put("offerId", offerId)
                .put("receivedAt", receivedAt)
                .put("nativePresentedAt", nativePresentedAt)
                .toString(),
        ).commit()
    }

    fun presentationReceipt(context: Context, callId: String, offerId: String): Map<String, Any?>? {
        val receipt = preferences(context).getString(presentationReceiptKey, null)?.let(::jsonMap) ?: return null
        return if (receipt["callId"] == callId && receipt["offerId"] == offerId) receipt else null
    }

    fun clearPresentation(context: Context, callId: String? = null, offerId: String? = null) = synchronized(lock) {
        val prefs = preferences(context)
        val current = prefs.getString(activePresentationKey, null)
        if (callId == null || offerId == null || current == presentationKey(callId, offerId)) {
            prefs.edit().remove(activePresentationKey).remove(presentationReceiptKey).remove(offerKey).commit()
        }
    }

    fun saveAction(context: Context, callId: String, action: String, reason: String? = null) {
        val actionJson = JSONObject()
            .put("callId", callId)
            .put("action", action)
            .put("reason", reason)
            .put("occurredAt", System.currentTimeMillis())
        preferences(context).edit().putString(actionKey, actionJson.toString()).commit()
    }

    fun takeAction(context: Context): Map<String, Any?>? = synchronized(lock) {
        val prefs = preferences(context)
        val raw = prefs.getString(actionKey, null) ?: return null
        prefs.edit().remove(actionKey).commit()
        jsonMap(raw)
    }

    fun saveFcmToken(context: Context, token: String) {
        if (token.isBlank()) return
        preferences(context).edit().putString(fcmTokenKey, token).apply()
    }

    fun readFcmToken(context: Context): String? =
        preferences(context).getString(fcmTokenKey, null)?.takeIf { it.isNotBlank() }

    private fun presentationKey(callId: String, offerId: String) = "$callId::$offerId"

    private fun jsonMap(raw: String): Map<String, Any?>? = runCatching {
        val json = JSONObject(raw)
        buildMap<String, Any?> {
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                put(key, json.opt(key))
            }
        }
    }.getOrNull()

    private fun preferences(context: Context) =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
}
