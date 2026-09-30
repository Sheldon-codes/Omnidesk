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
    private const val incomingLaunchKey = "incoming_launch_json"
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

    /**
     * Reads the persisted offer without consuming it.  Flutter uses this on a
     * cold notification launch so it can decide whether call UI must win over
     * ordinary navigation before the lifecycle coordinator takes ownership.
     */
    fun peekOffer(context: Context): Map<String, Any?>? = synchronized(lock) {
        preferences(context).getString(offerKey, null)?.let(::jsonMap)
    }

    /**
     * A notification tap is a durable launch intent, not an answer action.
     * Persist it only while the matching Telecom presentation and offer still
     * exist; this prevents a stale PendingIntent from resurrecting a finished
     * call after cancellation or expiry.
     */
    fun saveIncomingLaunch(context: Context, callId: String, offerId: String): Boolean = synchronized(lock) {
        if (callId.isBlank() || offerId.isBlank()) return false
        if (!isPresentationActive(context, callId, offerId)) return false
        val offer = peekOffer(context) ?: return false
        if (offer["call_id"] != callId || offer["offer_id"] != offerId) return false
        preferences(context).edit().putString(
            incomingLaunchKey,
            JSONObject()
                .put("callId", callId)
                .put("offerId", offerId)
                .put("reason", "incoming_call")
                .put("openedAt", System.currentTimeMillis())
                .toString(),
        ).commit()
        true
    }

    fun takeIncomingLaunch(context: Context): Map<String, Any?>? = synchronized(lock) {
        val prefs = preferences(context)
        val raw = prefs.getString(incomingLaunchKey, null) ?: return null
        prefs.edit().remove(incomingLaunchKey).commit()
        jsonMap(raw)
    }

    fun peekIncomingLaunch(context: Context): Map<String, Any?>? = synchronized(lock) {
        preferences(context).getString(incomingLaunchKey, null)?.let(::jsonMap)
    }

    /**
     * Removes only the offer just rejected by native presentation. This is
     * deliberately narrower than clearPresentation: a failed new offer must
     * not erase another active call's persisted identity.
     */
    fun discardOffer(context: Context, callId: String, offerId: String) = synchronized(lock) {
        val prefs = preferences(context)
        val stored = prefs.getString(offerKey, null)?.let(::jsonMap)
        if (stored?.get("call_id") == callId && stored["offer_id"] == offerId) {
            prefs.edit().remove(offerKey).commit()
        }
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
        val shouldClear = when {
            callId == null -> true
            offerId == null -> current?.startsWith("$callId::") == true
            else -> current == presentationKey(callId, offerId)
        }
        if (shouldClear) {
            prefs.edit()
                .remove(activePresentationKey)
                .remove(presentationReceiptKey)
                .remove(offerKey)
                .remove(incomingLaunchKey)
                .commit()
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
