package com.bigbrainzsolutions.omnidesk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Build
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
    const val extraCallSid = "com.bigbrainzsolutions.omnidesk.CALL_SID"
    const val extraOfferId = "com.bigbrainzsolutions.omnidesk.OFFER_ID"
    const val extraCallerName = "com.bigbrainzsolutions.omnidesk.CALLER_NAME"
    const val extraCallerNumber = "com.bigbrainzsolutions.omnidesk.CALLER_NUMBER"
    private const val accountId = "omnidesk_self_managed"
    private const val logTag = "OmniDeskTelecom"
    private val connections = ConcurrentHashMap<String, OmniDeskConnection>()
    private val pendingOutgoingLock = Any()
    private var pendingOutgoing: SystemCallIdentity? = null

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
        val connection = createConnection(context, SystemCallIdentity(callId = callId, callSid = null), true)
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
        AndroidCallMediaRuntime.onTelecomConnectionState(context, callId, connection.state, false)
        return connection
    }

    fun createOutgoingConnection(context: Context, extras: Bundle): Connection {
        // Several OEM Telecom implementations omit app-defined extras from
        // the outgoing ConnectionRequest. Claim the identity reserved before
        // placeCall() instead of creating an untrackable empty-key connection.
        val identity = identityFromExtras(extras).takeIf { it.systemCallId.isNotBlank() }
            ?: claimPendingOutgoing()
            ?: SystemCallIdentity(callId = "", callSid = null)
        logTrackedConnections("createOutgoingConnection callId=${identity.callId}")
        val connection = createConnection(context, identity, false)
        if (identity.systemCallId.isNotBlank()) {
            connections[identity.systemCallId] = connection
            clearPendingOutgoing(identity.systemCallId)
        } else {
            Log.e(logTag, "Outgoing Telecom connection arrived without a reserved identity")
        }
        connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setAddress(
            Uri.fromParts("tel", identity.phoneNumber, null),
            TelecomManager.PRESENTATION_ALLOWED,
        )
        connection.setCallerDisplayName(
            identity.displayName.ifBlank { identity.phoneNumber },
            TelecomManager.PRESENTATION_ALLOWED,
        )
        connection.setDialing()
        AndroidCallMediaRuntime.onTelecomConnectionState(context, identity.systemCallId, connection.state, false)
        return connection
    }

    fun beginOutgoing(context: Context, values: Map<String, String>) {
        val identity = SystemCallIdentity(
            callId = values["callId"].orEmpty(),
            callSid = values["callSid"].orEmpty().ifBlank { null },
            displayName = values["displayName"].orEmpty(),
            phoneNumber = values["phoneNumber"].orEmpty(),
        )
        require(identity.systemCallId.isNotBlank()) { "Missing outbound call identity" }
        reservePendingOutgoing(identity)
        logTrackedConnections("beginOutgoing callId=${identity.callId}")
        ensurePhoneAccount(context)
        val extras = Bundle().apply {
            putString(extraCallId, identity.callId)
            putString(extraCallSid, identity.callSid)
            putString(extraCallerName, identity.displayName)
            putString(extraCallerNumber, identity.phoneNumber)
            putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccountHandle(context))
        }
        try {
            context.getSystemService(TelecomManager::class.java).placeCall(
                Uri.fromParts("tel", identity.phoneNumber, null), extras
            )
        } catch (error: Throwable) {
            clearPendingOutgoing(identity.systemCallId)
            throw error
        }
        AndroidCallEventBridge.emitOutgoingDialing(identity)
    }

    fun markActive(context: Context, callId: String) {
        val identity = connections[callId]?.identity
            ?: pendingIdentity(callId)
            ?: SystemCallIdentity(callId = callId, callSid = null)
        // The incoming CallStyle notification owns ringtone/vibration until
        // it is explicitly cancelled.  Do this defensively here too in case
        // a platform callback reaches ACTIVE without first reaching
        // markAnswering.
        OmniDeskCallNotification.dismissIncoming(context, callId)
        connections[callId]?.setActive()
        AndroidCallMediaRuntime.onTelecomConnectionState(context, callId, Connection.STATE_ACTIVE, false)
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.RECORD_AUDIO
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            startForegroundServiceSafely(context, callId)
        } else {
            Log.w(logTag, "Skipping call foreground service: RECORD_AUDIO is not granted")
        }
        AndroidCallEventBridge.emitActive(identity)
    }

    fun markFailed(context: Context, callId: String, reason: String?) {
        // Read the complete identity before cleanup removes the native
        // connection. Never relabel a backend call ID as a provider SID.
        val identity = connections[callId]?.identity
            ?: pendingIdentity(callId)
            ?: SystemCallIdentity(callId = callId, callSid = null)
        cleanup(
            context,
            callId,
            null,
            android.telecom.DisconnectCause(android.telecom.DisconnectCause.ERROR, reason),
        )
        AndroidCallEventBridge.emitFailed(identity, reason)
    }

    fun handleOutgoingConnectionFailed(context: Context, extras: Bundle, reason: String) {
        val identity = identityFromExtras(extras).takeIf { it.systemCallId.isNotBlank() }
            ?: claimPendingOutgoing()
        if (identity == null) {
            Log.w(logTag, "Outgoing Telecom creation failed without an identity")
            return
        }
        markFailed(context, identity.systemCallId, reason)
    }

    fun answer(context: Context, callId: String) {
        markAnswering(context, callId)
        IncomingCallStateStore.saveAction(context, callId, "answer")
        AndroidCallEventBridge.emitAction("answer", callId)
        // Re-launching an already visible Flutter Activity triggers lifecycle
        // refresh/recovery races during /accept. Only bring the task forward
        // when it is genuinely backgrounded or absent.
        if (!MainActivity.isForeground) launchFlutter(context)
    }

    /**
     * Stop the native ringing surface once the user has answered, while the
     * Flutter/API/WebRTC work is still in progress.  It intentionally does
     * not persist an action or emit an event: callers using the Flutter UI
     * already own that authoritative answer flow.
     */
    fun markAnswering(context: Context, callId: String) {
        OmniDeskCallNotification.dismissIncoming(context, callId)
        // The bridge/WebView has to survive the entire preparation phase,
        // not only the already-connected phase. Starting here also covers a
        // cold Flutter engine after an Answer action from the system surface.
        startForegroundServiceSafely(context, callId)
        Log.i(logTag, "Incoming Telecom ringing stopped; preparing callId=$callId")
    }

    /** Called only after backend /accept succeeds for incoming calls. */
    fun prepareSystemAudio(context: Context, callId: String, incoming: Boolean, callback: (Result<Unit>) -> Unit) {
        val connection = connections[callId]
        if (connection == null || connection.state == Connection.STATE_DISCONNECTED ||
            (incoming && connection.state != Connection.STATE_RINGING && connection.state != Connection.STATE_ACTIVE) ||
            (!incoming && connection.state != Connection.STATE_DIALING && connection.state != Connection.STATE_ACTIVE)
        ) {
            callback(Result.failure(IllegalStateException("matching_telecom_connection_unavailable")))
            return
        }
        if (incoming && connection.state == Connection.STATE_RINGING) {
            OmniDeskCallNotification.dismissIncoming(context, callId)
            connection.setActive()
            AndroidCallMediaRuntime.onTelecomConnectionState(context, callId, Connection.STATE_ACTIVE, false)
            Log.i(logTag, "Telecom transition callId=$callId state=ACTIVE ownership=telecom reason=backend_accept")
        }
        startForegroundServiceSafely(context, callId)
        AndroidCallMediaRuntime.awaitSystemAudioReadiness(context, callId, incoming, callback)
    }

    /** Telecom surface adapter; audio policy/readiness decisions stay in the foreground service coordinator. */
    fun requestSpeakerRoute(callId: String, enabled: Boolean, callback: (Result<Unit>) -> Unit) {
        val connection = connections[callId]
        if (connection == null || connection.state == Connection.STATE_DISCONNECTED) {
            callback(Result.failure(IllegalStateException("matching_telecom_connection_unavailable")))
            return
        }
        connection.requestSpeakerRoute(enabled, callback)
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

    fun setSpeaker(context: Context, enabled: Boolean, callback: (Result<Unit>) -> Unit = {}) {
        AndroidCallMediaRuntime.setSpeaker(context, enabled, callback)
    }

    fun onConnectionServiceFocusChanged(context: Context, gained: Boolean, released: () -> Unit = {}) {
        val callId = connections.entries.firstOrNull { it.value.state == Connection.STATE_ACTIVE }?.key
            ?: connections.entries.firstOrNull { it.value.state == Connection.STATE_DIALING }?.key
        if (callId == null) {
            if (!gained) released()
            return
        }
        AndroidCallMediaRuntime.onTelecomFocusChanged(context, callId, gained, released)
    }

    private fun cleanup(
        context: Context,
        callId: String,
        offerId: String?,
        disconnectCause: android.telecom.DisconnectCause? = null,
    ) {
        // Cancellation, Flutter hang-up, provider hang-up, and backend
        // failure can all reach cleanup without going through native Answer
        // or Decline. Always cancel the CallStyle notification here so its
        // ringtone/vibration cannot outlive the underlying Telecom call.
        OmniDeskCallNotification.dismissIncoming(context, callId)
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
        MainActivity.clearIncomingCallLaunchPresentation(callId)
        clearPendingOutgoing(callId)
        AndroidCallMediaRuntime.endSystemAudio(context, callId)
    }

    private fun identityFromExtras(extras: Bundle): SystemCallIdentity = SystemCallIdentity(
        callId = extras.getString(extraCallId).orEmpty(),
        callSid = extras.getString(extraCallSid)?.takeIf { it.isNotBlank() },
        displayName = extras.getString(extraCallerName).orEmpty(),
        phoneNumber = extras.getString(extraCallerNumber).orEmpty(),
    )

    private fun createConnection(context: Context, identity: SystemCallIdentity, incoming: Boolean): OmniDeskConnection =
        if (Build.VERSION.SDK_INT >= 34) OmniDeskConnectionApi34(context, identity, incoming)
        else OmniDeskConnection(context, identity, incoming)

    private fun reservePendingOutgoing(identity: SystemCallIdentity) = synchronized(pendingOutgoingLock) {
        val existing = pendingOutgoing
        check(existing == null || existing.systemCallId == identity.systemCallId) {
            "Another outgoing Telecom call is already pending"
        }
        pendingOutgoing = identity
    }

    private fun claimPendingOutgoing(): SystemCallIdentity? = synchronized(pendingOutgoingLock) {
        val identity = pendingOutgoing
        pendingOutgoing = null
        identity
    }

    private fun pendingIdentity(systemCallId: String): SystemCallIdentity? = synchronized(pendingOutgoingLock) {
        pendingOutgoing?.takeIf { it.systemCallId == systemCallId }
    }

    private fun clearPendingOutgoing(systemCallId: String) = synchronized(pendingOutgoingLock) {
        if (pendingOutgoing?.systemCallId == systemCallId) pendingOutgoing = null
    }

    private fun logTrackedConnections(action: String) {
        // Call IDs are opaque backend correlation values, not caller data.
        // This log makes a stale native Connection diagnosable without using
        // it as an unreliable concurrency gate.
        Log.i(logTag, "$action trackedConnections=${connections.keys.joinToString(",")}")
    }

    /** Keep the native Answer path usable if an OEM rejects an FGS start. */
    private fun startForegroundServiceSafely(context: Context, callId: String) {
        val microphoneGranted = androidx.core.content.ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        try {
            OmniDeskCallForegroundService.start(context, callId, microphoneGranted)
            Log.i(logTag, "Starting call FGS callId=$callId microphone=$microphoneGranted")
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

/**
 * The only native representation of a system call. [systemCallId] is used
 * for Telecom tracking, while [callSid] remains available for provider-side
 * completion and Flutter event matching.
 */
data class SystemCallIdentity(
    val callId: String,
    val callSid: String?,
    val displayName: String = "",
    val phoneNumber: String = "",
) {
    val systemCallId: String get() = callId.ifBlank { callSid.orEmpty() }

    fun toFlutterMap(): Map<String, String> = buildMap {
        if (callId.isNotBlank()) put("callId", callId)
        if (!callSid.isNullOrBlank()) put("callSid", callSid)
    }
}
