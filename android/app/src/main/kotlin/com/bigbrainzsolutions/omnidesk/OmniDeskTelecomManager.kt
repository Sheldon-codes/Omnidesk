package com.bigbrainzsolutions.omnidesk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.telecom.Connection
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Android system-call ownership; it deliberately has no WebRTC or API code. */
object OmniDeskTelecomManager {
    const val extraCallId = "com.bigbrainzsolutions.omnidesk.CALL_ID"
    const val extraOfferId = "com.bigbrainzsolutions.omnidesk.OFFER_ID"
    const val extraCallerName = "com.bigbrainzsolutions.omnidesk.CALLER_NAME"
    const val extraCallerNumber = "com.bigbrainzsolutions.omnidesk.CALLER_NUMBER"
    private const val accountId = "omnidesk_self_managed"
    private const val logTag = "OmniDeskTelecom"
    private val connections = ConcurrentHashMap<String, OmniDeskConnection>()

    data class PresentationReceipt(val receivedAt: String, val nativePresentedAt: String) {
        fun toMap() = mapOf("receivedAt" to receivedAt, "nativePresentedAt" to nativePresentedAt)
    }

    fun ensurePhoneAccount(context: Context) {
        val telecom = context.getSystemService(TelecomManager::class.java)
        val handle = phoneAccountHandle(context)
        val account = PhoneAccount.builder(handle, "OmniDesk calls")
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .build()
        telecom.registerPhoneAccount(account)
    }

    fun presentIncoming(context: Context, values: Map<String, String>): PresentationReceipt {
        val callId = values["callId"].orEmpty()
        val offerId = values["offerId"].orEmpty()
        require(callId.isNotBlank() && offerId.isNotBlank()) { "Missing call identity" }
        if (IncomingCallStateStore.isPresentationActive(context, callId, offerId)) {
            Log.i(logTag, "Incoming Telecom presentation already active callId=$callId")
            return IncomingCallStateStore.presentationReceipt(context, callId, offerId)
                ?.let { PresentationReceipt(it["receivedAt"].toString(), it["nativePresentedAt"].toString()) }
                ?: receipt(values["receivedAt"])
        }
        ensurePhoneAccount(context)
        val extras = Bundle().apply {
            putString(extraCallId, callId)
            putString(extraOfferId, offerId)
            putString(extraCallerName, values["callerName"])
            putString(extraCallerNumber, values["callerNumber"])
        }
        val telecom = context.getSystemService(TelecomManager::class.java)
        if (!telecom.isIncomingCallPermitted(phoneAccountHandle(context))) {
            throw IllegalStateException("Android Telecom cannot present an incoming self-managed call")
        }
        telecom.addNewIncomingCall(phoneAccountHandle(context), extras)
        IncomingCallStateStore.markPresentationActive(context, callId, offerId)
        val receipt = receipt(values["receivedAt"])
        IncomingCallStateStore.savePresentationReceipt(
            context, callId, offerId, receipt.receivedAt, receipt.nativePresentedAt
        )
        try {
            OmniDeskCallNotification.showIncoming(context, values)
        } catch (error: Throwable) {
            // Do not leave a Telecom call/presentation reservation behind if
            // Android rejects the notification (for example, permission or
            // OEM notification policy). A stale reservation blocks the next
            // incoming call through isIncomingCallPermitted().
            connections.remove(callId)?.setDisconnected(
                android.telecom.DisconnectCause(android.telecom.DisconnectCause.ERROR, "notification_failed")
            )
            IncomingCallStateStore.clearPresentation(context, callId, offerId)
            throw error
        }
        // Full-screen presentation is owned by the CallStyle notification.
        // Starting an Activity directly from an FCM service is blocked on
        // modern Android and would bypass the system's full-screen policy.
        AndroidCallEventBridge.emitIncomingPresented(callId)
        Log.i(logTag, "Incoming Telecom call presented callId=$callId offerId=$offerId")
        return receipt
    }

    fun createIncomingConnection(context: Context, extras: Bundle): Connection {
        val callId = extras.getString(extraCallId).orEmpty()
        val connection = OmniDeskConnection(context, callId, true)
        connections[callId] = connection
        connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setAddress(Uri.fromParts("tel", extras.getString(extraCallerNumber).orEmpty(), null), TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(extras.getString(extraCallerName).orEmpty().ifBlank { extras.getString(extraCallerNumber).orEmpty() }, TelecomManager.PRESENTATION_ALLOWED)
        connection.setRinging()
        return connection
    }

    fun createOutgoingConnection(context: Context, extras: Bundle): Connection {
        val callId = extras.getString(extraCallId).orEmpty()
        val connection = OmniDeskConnection(context, callId, false)
        connections[callId] = connection
        connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setDialing()
        return connection
    }

    fun beginOutgoing(context: Context, values: Map<String, String>) {
        val callId = values["callId"].orEmpty().ifBlank { values["callSid"].orEmpty() }
        require(callId.isNotBlank()) { "Missing outbound call identity" }
        ensurePhoneAccount(context)
        val extras = Bundle().apply {
            putString(extraCallId, callId)
            putString(extraCallerName, values["displayName"])
            putString(extraCallerNumber, values["phoneNumber"])
            putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccountHandle(context))
        }
        context.getSystemService(TelecomManager::class.java).placeCall(
            Uri.fromParts("tel", values["phoneNumber"].orEmpty(), null), extras
        )
        AndroidCallEventBridge.emitOutgoingDialing(callId)
    }

    fun markActive(context: Context, callId: String) {
        connections[callId]?.setActive()
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.RECORD_AUDIO
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            OmniDeskCallForegroundService.start(context, callId)
        } else {
            Log.w(logTag, "Skipping call foreground service: RECORD_AUDIO is not granted")
        }
        AndroidCallEventBridge.emitActive(callId)
    }

    fun markFailed(context: Context, callId: String, reason: String?) {
        connections.remove(callId)?.setDisconnected(android.telecom.DisconnectCause(android.telecom.DisconnectCause.ERROR, reason))
        cleanup(context, callId, null)
        AndroidCallEventBridge.emitFailed(callId, reason)
    }

    fun answer(context: Context, callId: String) {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        IncomingCallStateStore.saveAction(context, callId, "answer")
        connections[callId]?.setInitializing()
        AndroidCallEventBridge.emitAction("answer", callId)
        launchFlutter(context)
    }

    fun decline(context: Context, callId: String, reason: String = "user_declined") {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        connections.remove(callId)?.setDisconnected(android.telecom.DisconnectCause(android.telecom.DisconnectCause.REJECTED))
        IncomingCallStateStore.saveAction(context, callId, "decline", reason)
        cleanup(context, callId, null)
        AndroidCallEventBridge.emitAction("decline", callId, reason)
        launchFlutter(context)
    }

    fun disconnect(context: Context, callId: String, reason: String = "local_disconnect") {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        connections.remove(callId)?.setDisconnected(android.telecom.DisconnectCause(android.telecom.DisconnectCause.LOCAL))
        IncomingCallStateStore.saveAction(context, callId, "end", reason)
        cleanup(context, callId, null)
        AndroidCallEventBridge.emitAction("end", callId, reason)
    }

    fun cancel(context: Context, callId: String, offerId: String?, reason: String?) {
        if (offerId == null || IncomingCallStateStore.isPresentationActive(context, callId, offerId)) {
            OmniDeskCallNotification.dismissIncoming(context, callId)
            connections.remove(callId)?.setDisconnected(android.telecom.DisconnectCause(android.telecom.DisconnectCause.CANCELED))
            cleanup(context, callId, offerId)
            AndroidCallEventBridge.emitDisconnected(callId, reason ?: "call_cancelled")
        }
    }

    fun dismiss(context: Context, callId: String) = cleanup(context, callId, null)

    fun setSpeaker(context: Context, enabled: Boolean) {
        // Telecom is the audio-route authority. Flutter's WebRTC bridge owns
        // output selection until route callbacks are wired in a follow-up.
        Log.i(logTag, "Speaker request enabled=$enabled")
    }

    fun onConnectionDestroyed(context: Context, callId: String) {
        connections.remove(callId)
        OmniDeskCallNotification.dismissIncoming(context, callId)
        OmniDeskCallForegroundService.stop(context)
    }

    private fun cleanup(context: Context, callId: String, offerId: String?) {
        connections.remove(callId)
        IncomingCallStateStore.clearPresentation(context, callId, offerId)
        OmniDeskCallForegroundService.stop(context)
    }

    private fun receipt(receivedAt: String?): PresentationReceipt = PresentationReceipt(
        receivedAt ?: Instant.now().toString(),
        Instant.now().toString(),
    )

    private fun launchFlutter(context: Context) {
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(this)
        }
    }

    fun notifyIncomingOpened(callId: String) {
        AndroidCallEventBridge.emitIncomingOpened(callId)
    }

    private fun phoneAccountHandle(context: Context) = PhoneAccountHandle(
        ComponentName(context, OmniDeskConnectionService::class.java), accountId
    )
}
