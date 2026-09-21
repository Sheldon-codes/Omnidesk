package com.bigbrainzsolutions.omnidesk

import android.content.pm.ApplicationInfo
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * The sole Android owner of FCM's MESSAGING_EVENT for this application.
 *
 * Incoming call offers are written synchronously before any UI work. This is
 * safe when the Flutter engine is absent and avoids relying on a background
 * Dart isolate for time-sensitive call signalling. Gate 3 will add Telecom
 * presentation after this durable hand-off has been exercised in isolation.
 */
class OmniDeskMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val payload = message.data
        // The full data map is valuable while integrating the backend call
        // contract, but it can contain caller PII. Keep it strictly in debug
        // builds; release logs expose only the payload keys and message ID.
        Log.d(
            logTag,
            "FCM received messageId=${message.messageId ?: "none"} " +
                "data=${payloadForLog(payload)} " +
                "notificationPresent=${message.notification != null}"
        )
        val eventId = payload["event_id"].orEmpty().ifBlank {
            message.messageId.orEmpty().ifBlank {
                listOf(payload["type"], payload["call_id"], payload["offer_id"], payload["timestamp"], payload["reason"])
                    .joinToString(":")
            }
        }
        val normalizedPayload = payload.toMutableMap().apply {
            if (eventId.isNotBlank()) put("event_id", eventId)
        }
        if (!IncomingCallStateStore.markEventIfNew(applicationContext, eventId)) {
            Log.i(logTag, "Duplicate FCM event ignored eventId=$eventId")
            return
        }
        when (normalizedPayload["type"]?.lowercase()) {
            "incoming_call" -> {
                if (!IncomingCallStateStore.saveIncomingOffer(applicationContext, normalizedPayload)) {
                    Log.w(logTag, "Invalid incoming-call payload eventId=$eventId")
                    return
                }
                val callId = normalizedPayload["call_id"] ?: return
                try {
                    val receipt = OmniDeskTelecomManager.presentIncoming(applicationContext, mapOf(
                        "callId" to callId,
                        "offerId" to normalizedPayload["offer_id"].orEmpty(),
                        "callerName" to normalizedPayload["caller_name"].orEmpty(),
                        "callerNumber" to normalizedPayload["caller_number"].orEmpty(),
                        "receivedAt" to normalizedPayload["timestamp"].orEmpty(),
                    ))
                    Log.i(logTag, "Incoming Telecom presented callId=$callId eventId=$eventId nativePresentedAt=${receipt.nativePresentedAt}")
                } catch (error: Throwable) {
                    Log.e(logTag, "Incoming Telecom presentation failed callId=$callId eventId=$eventId", error)
                }
                AndroidCallEventBridge.offerAvailable(callId)
            }
            "call_cancelled" -> {
                val callId = normalizedPayload["call_id"].orEmpty()
                if (callId.isNotBlank()) {
                    OmniDeskTelecomManager.cancel(applicationContext, callId, normalizedPayload["offer_id"], normalizedPayload["reason"])
                    Log.i(logTag, "Cancellation processed callId=$callId eventId=$eventId reason=${normalizedPayload["reason"] ?: "none"}")
                }
            }
            else -> Log.d(logTag, "Ignored non-call FCM event eventId=$eventId")
        }
    }

    override fun onNewToken(token: String) {
        IncomingCallStateStore.saveFcmToken(applicationContext, token)
        AndroidCallEventBridge.pushTokenChanged()
        Log.i(logTag, "FCM token updated")
    }

    private companion object {
        const val logTag = "OmniDeskCallPush"
    }

    private fun payloadForLog(payload: Map<String, String>): String =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            payload.toSortedMap().toString()
        } else {
            "keys=${payload.keys.sorted()}"
        }
}
