package com.bigbrainzsolutions.omnidesk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
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
        // `connections` is only this process's bookkeeping. It can outlive a
        // cancelled ConnectionService callback, so it is not an authority for
        // whether Telecom may present the next call. Telecom's own
        // isIncomingCallPermitted check below is the policy authority.
        logTrackedConnections("presentIncoming callId=$callId")
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
        // Android may synchronously invoke ConnectionService from
        // addNewIncomingCall. Persist idempotency before that call so a
        // legitimate connection cannot be mistaken for a late/cancelled one.
        IncomingCallStateStore.markPresentationActive(context, callId, offerId)
        try {
            telecom.addNewIncomingCall(phoneAccountHandle(context), extras)
        } catch (error: Throwable) {
            IncomingCallStateStore.clearPresentation(context, callId, offerId)
            throw error
        }
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
            cleanup(
                context,
                callId,
                offerId,
                android.telecom.DisconnectCause(
                    android.telecom.DisconnectCause.ERROR,
                    "notification_failed",
                ),
            )
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
        val offerId = extras.getString(extraOfferId).orEmpty()
        val connection = OmniDeskConnection(context, callId, true)
        // A cancellation can race Telecom's asynchronous ConnectionService
        // callback. Never resurrect a cancelled offer into a fresh ringing
        // system connection.
        if (callId.isBlank() || offerId.isBlank() ||
            !IncomingCallStateStore.isPresentationActive(context, callId, offerId)
        ) {
            Log.i(logTag, "Ignoring stale incoming Telecom connection callId=$callId")
            connection.setDisconnected(
                android.telecom.DisconnectCause(android.telecom.DisconnectCause.CANCELED),
            )
            connection.destroy()
            return connection
        }
        logTrackedConnections("createIncomingConnection callId=$callId")
        connections[callId] = connection
        connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setAddress(Uri.fromParts("tel", extras.getString(extraCallerNumber).orEmpty(), null), TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(extras.getString(extraCallerName).orEmpty().ifBlank { extras.getString(extraCallerNumber).orEmpty() }, TelecomManager.PRESENTATION_ALLOWED)
        connection.setRinging()
        return connection
    }

    fun createOutgoingConnection(context: Context, extras: Bundle): Connection {
        val callId = extras.getString(extraCallId).orEmpty()
        logTrackedConnections("createOutgoingConnection callId=$callId")
        val connection = OmniDeskConnection(context, callId, false)
        connections[callId] = connection
        connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setDialing()
        return connection
    }

    fun beginOutgoing(context: Context, values: Map<String, String>) {
        val callId = values["callId"].orEmpty().ifBlank { values["callSid"].orEmpty() }
        require(callId.isNotBlank()) { "Missing outbound call identity" }
        logTrackedConnections("beginOutgoing callId=$callId")
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
            startForegroundServiceSafely(context, callId)
        } else {
            Log.w(logTag, "Skipping call foreground service: RECORD_AUDIO is not granted")
        }
        AndroidCallEventBridge.emitActive(callId)
    }

    fun markFailed(context: Context, callId: String, reason: String?) {
        cleanup(
            context,
            callId,
            null,
            android.telecom.DisconnectCause(android.telecom.DisconnectCause.ERROR, reason),
        )
        AndroidCallEventBridge.emitFailed(callId, reason)
    }

    fun answer(context: Context, callId: String) {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        IncomingCallStateStore.saveAction(context, callId, "answer")
        connections[callId]?.setInitializing()
        // The bridge/WebView has to survive the entire preparation phase,
        // not only the already-connected phase. Starting here also covers a
        // cold Flutter engine after an Answer action from the system surface.
        startForegroundServiceSafely(context, callId)
        AndroidCallEventBridge.emitAction("answer", callId)
        // Re-launching an already visible Flutter Activity triggers lifecycle
        // refresh/recovery races during /accept. Only bring the task forward
        // when it is genuinely backgrounded or absent.
        if (!MainActivity.isForeground) launchFlutter(context)
    }

    fun decline(context: Context, callId: String, reason: String = "user_declined") {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        IncomingCallStateStore.saveAction(context, callId, "decline", reason)
        cleanup(
            context,
            callId,
            null,
            android.telecom.DisconnectCause(android.telecom.DisconnectCause.REJECTED),
        )
        AndroidCallEventBridge.emitAction("decline", callId, reason)
        launchFlutter(context)
    }

    fun disconnect(context: Context, callId: String, reason: String = "local_disconnect") {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        IncomingCallStateStore.saveAction(context, callId, "end", reason)
        cleanup(
            context,
            callId,
            null,
            android.telecom.DisconnectCause(android.telecom.DisconnectCause.LOCAL),
        )
        AndroidCallEventBridge.emitAction("end", callId, reason)
    }

    fun cancel(context: Context, callId: String, offerId: String?, reason: String?) {
        if (offerId == null || IncomingCallStateStore.isPresentationActive(context, callId, offerId)) {
            OmniDeskCallNotification.dismissIncoming(context, callId)
            cleanup(
                context,
                callId,
                offerId,
                android.telecom.DisconnectCause(android.telecom.DisconnectCause.CANCELED),
            )
            AndroidCallEventBridge.emitDisconnected(callId, reason ?: "call_cancelled")
        }
    }

    fun dismiss(context: Context, callId: String) = cleanup(context, callId, null)

    fun setSpeaker(context: Context, enabled: Boolean) {
        val audioManager = context.getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val target = if (enabled) {
                audioManager.availableCommunicationDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                } ?: throw IllegalStateException("No built-in speaker route is available")
            } else {
                audioManager.availableCommunicationDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                }
            }
            val routed = target?.let(audioManager::setCommunicationDevice)
                ?: run {
                    audioManager.clearCommunicationDevice()
                    true
                }
            if (!routed) {
                throw IllegalStateException("Android rejected the requested call audio route")
            }
        } else {
            @Suppress("DEPRECATION")
            run {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.isSpeakerphoneOn = enabled
            }
        }
        Log.i(logTag, "Call audio route changed speaker=$enabled")
    }

    private fun cleanup(
        context: Context,
        callId: String,
        offerId: String?,
        disconnectCause: android.telecom.DisconnectCause? = null,
    ) {
        val connection = connections.remove(callId)
        Log.i(
            logTag,
            "Cleaning up Telecom call callId=$callId trackedConnection=${connection != null} " +
                "trackedAfter=${connections.keys.joinToString(",")}",
        )
        connection?.let {
            if (disconnectCause != null) connection.setDisconnected(disconnectCause)
            // setDisconnected changes call state, but does not guarantee the
            // Connection object is released promptly. destroy() is required
            // to remove this self-managed call from Telecom's active set.
            connection.destroy()
        }
        IncomingCallStateStore.clearPresentation(context, callId, offerId)
        releaseCommunicationRoute(context)
        OmniDeskCallForegroundService.stop(context)
    }

    private fun logTrackedConnections(action: String) {
        // Call IDs are opaque backend correlation values, not caller data.
        // This log makes a stale native Connection diagnosable without using
        // it as an unreliable concurrency gate.
        Log.i(logTag, "$action trackedConnections=${connections.keys.joinToString(",")}")
    }

    private fun releaseCommunicationRoute(context: Context) {
        val audioManager = context.getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            run {
                audioManager.isSpeakerphoneOn = false
                audioManager.mode = AudioManager.MODE_NORMAL
            }
        }
    }

    /** Keep the native Answer path usable if an OEM rejects an FGS start. */
    private fun startForegroundServiceSafely(context: Context, callId: String) {
        try {
            OmniDeskCallForegroundService.start(context, callId)
        } catch (error: Throwable) {
            Log.w(logTag, "Unable to start call foreground service callId=$callId", error)
        }
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
