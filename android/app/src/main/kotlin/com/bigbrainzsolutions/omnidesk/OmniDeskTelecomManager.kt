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
    private const val selfManagedAccountId = "omnidesk_self_managed"
    private const val managedAccountId = "omnidesk_system_managed"
    private const val logTag = "OmniDeskTelecom"
    private val connections = ConcurrentHashMap<String, OmniDeskConnection>()
    private val focusTracker = TelecomFocusTracker()
    private val pendingOutgoingLock = Any()
    private var pendingOutgoing: SystemCallIdentity? = null

    data class PresentationReceipt(val receivedAt: String, val nativePresentedAt: String) {
        fun toMap() = mapOf("receivedAt" to receivedAt, "nativePresentedAt" to nativePresentedAt)
    }

    fun ensurePhoneAccount(context: Context) {
        val telecom = context.getSystemService(TelecomManager::class.java)
        telecom.registerPhoneAccount(PhoneAccount.builder(selfManagedPhoneAccountHandle(context), "OmniDesk calls")
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED).build())
        telecom.registerPhoneAccount(PhoneAccount.builder(managedPhoneAccountHandle(context), "OmniDesk calls (System UI)")
            .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
            .setSupportedUriSchemes(listOf("tel")).build())
    }

    fun managedCallingEnabled(context: Context): Boolean =
        context.getSharedPreferences("omnidesk_call_settings", Context.MODE_PRIVATE)
            .getBoolean("managed_calling_enabled", false)

    fun setManagedCallingEnabled(context: Context, enabled: Boolean) {
        if (enabled && NativeCallCredentials.read(context) == null) {
            throw IllegalStateException("managed_call_session_not_synchronized")
        }
        ensurePhoneAccount(context)
        if (!enabled) NativeCallCredentials.clear(context)
        context.getSharedPreferences("omnidesk_call_settings", Context.MODE_PRIVATE).edit()
            .putBoolean("managed_calling_enabled", enabled).apply()
    }

    @Suppress("UNUSED_PARAMETER")
    fun isManagedAccountEnabled(context: Context): Boolean? = null

    fun openPhoneAccountSettings(context: Context) {
        context.startActivity(Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
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
        val selection = try {
            ManagedCallAccountPolicy.select(managedCallingEnabled(context), isManagedAccountEnabled(context))
        } catch (error: IllegalStateException) {
            OmniDeskCallNotification.showManagedAccountSetupRequired(context)
            throw error
        }
        val managed = selection == ManagedCallAccountPolicy.Account.SYSTEM_MANAGED
        val account = if (managed) managedPhoneAccountHandle(context) else selfManagedPhoneAccountHandle(context)
        if (!managed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            !telecom.isIncomingCallPermitted(selfManagedPhoneAccountHandle(context))) {
            throw IllegalStateException("Android Telecom cannot present an incoming call")
        }
        extras.putBoolean(extraManagedCall, managed)
        routeForConnection(context, callId, managed)
        // Android may synchronously invoke ConnectionService from
        // addNewIncomingCall. Persist idempotency before that call so a
        // legitimate connection cannot be mistaken for a late/cancelled one.
        IncomingCallStateStore.markPresentationActive(context, callId, offerId)
        try {
            telecom.addNewIncomingCall(account, extras)
        } catch (error: Throwable) {
            IncomingCallStateStore.clearPresentation(context, callId, offerId)
            callRoutes(context).edit().remove(callId).apply()
            if (managed && error is SecurityException) {
                OmniDeskCallNotification.showManagedAccountSetupRequired(context)
            }
            throw error
        }
        val receipt = receipt(values["receivedAt"])
        IncomingCallStateStore.savePresentationReceipt(
            context, callId, offerId, receipt.receivedAt, receipt.nativePresentedAt
        )
        if (!managed) try {
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
        // System-managed accounts use Telecom's incoming UI; self-managed
        // accounts retain the existing CallStyle notification.
        // Starting an Activity directly from an FCM service is blocked on
        // modern Android and would bypass the system's full-screen policy.
        if (!managed) AndroidCallEventBridge.emitIncomingPresented(callId)
        Log.i(logTag, "Incoming Telecom call presented callId=$callId offerId=$offerId")
        return receipt
    }

    fun createIncomingConnection(context: Context, extras: Bundle): Connection {
        val callId = extras.getString(extraCallId).orEmpty()
        val offerId = extras.getString(extraOfferId).orEmpty()
        val managed = isManagedRequest(extras) || isManagedCall(context, callId)
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
        // This is a managed VoIP call, not a cellular call. Telecom still owns
        // focus, mode, and routing; this tells it to choose its VoIP audio
        // policy before the connection enters RINGING. On Samsung, leaving
        // the flag false selects MODE_IN_CALL and silences WebRTC capture.
        if (managed) connection.setAudioModeIsVoip(true)
        Log.i(logTag, "Incoming Telecom audio policy managed=$managed voip=${connection.audioModeIsVoip}")
        connections[callId] = connection
        routeForConnection(context, callId, managed)
        if (!managed) connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setAddress(Uri.fromParts("tel", extras.getString(extraCallerNumber).orEmpty(), null), TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(extras.getString(extraCallerName).orEmpty().ifBlank { extras.getString(extraCallerNumber).orEmpty() }, TelecomManager.PRESENTATION_ALLOWED)
        connection.setRinging()
        AndroidCallMediaRuntime.onTelecomConnectionState(context, callId, connection.state, false)
        dispatchPendingTelecomFocus(context)
        return connection
    }

    fun createOutgoingConnection(context: Context, extras: Bundle): Connection {
        // Several OEM Telecom implementations omit app-defined extras from
        // the outgoing ConnectionRequest. Claim the identity reserved before
        // placeCall() instead of creating an untrackable empty-key connection.
        val requestIdentity = identityFromExtras(extras).takeIf { it.systemCallId.isNotBlank() }
        val identity = synchronized(pendingOutgoingLock) {
            pendingOutgoing?.takeIf { requestIdentity == null || requestIdentity.systemCallId == it.systemCallId }
        }
        if (identity == null) {
            // Telecom can deliver this callback after the originating call
            // has already timed out or been cancelled. Never create a live
            // Connection without an application call identity.
            Log.w(logTag, "Rejecting outgoing Telecom connection without a reserved identity")
            return Connection.createFailedConnection(
                android.telecom.DisconnectCause(android.telecom.DisconnectCause.CANCELED),
            )
        }
        logTrackedConnections("createOutgoingConnection callId=${identity.callId}")
        val connection = createConnection(context, identity, false)
        val managed = isManagedRequest(extras) || isManagedCall(context, identity.systemCallId)
        val stillReserved = synchronized(pendingOutgoingLock) {
            if (pendingOutgoing?.systemCallId != identity.systemCallId) false
            else {
                connections[identity.systemCallId] = connection
                pendingOutgoing = null
                true
            }
        }
        if (!stillReserved) {
            Log.w(logTag, "Rejecting cancelled outgoing Telecom connection")
            return Connection.createFailedConnection(
                android.telecom.DisconnectCause(android.telecom.DisconnectCause.CANCELED),
            )
        }
        // Set before DIALING so Telecom never routes this managed WebRTC call
        // through the cellular MODE_IN_CALL microphone policy.
        if (managed) connection.setAudioModeIsVoip(true)
        Log.i(logTag, "Outgoing Telecom audio policy managed=$managed voip=${connection.audioModeIsVoip}")
        routeForConnection(context, identity.systemCallId, managed)
        if (!managed) connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
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
        dispatchPendingTelecomFocus(context)
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
        ensurePhoneAccount(context)
        val extras = Bundle().apply {
            putString(extraCallId, identity.callId)
            putString(extraCallSid, identity.callSid)
            putString(extraCallerName, identity.displayName)
            putString(extraCallerNumber, identity.phoneNumber)
            putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, selfManagedPhoneAccountHandle(context))
        }
        val selection = try {
            ManagedCallAccountPolicy.select(managedCallingEnabled(context), isManagedAccountEnabled(context))
        } catch (error: IllegalStateException) {
            clearPendingOutgoing(identity.systemCallId)
            throw error
        }
        val managed = selection == ManagedCallAccountPolicy.Account.SYSTEM_MANAGED
        if (managed && androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.CALL_PHONE
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("call_phone_permission_required")
        }
        reservePendingOutgoing(identity)
        logTrackedConnections("beginOutgoing callId=${identity.callId}")
        extras.putBoolean(extraManagedCall, managed)
        extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE,
            if (managed) managedPhoneAccountHandle(context) else selfManagedPhoneAccountHandle(context))
        routeForConnection(context, identity.systemCallId, managed)
        try {
            context.getSystemService(TelecomManager::class.java).placeCall(
                Uri.fromParts("tel", identity.phoneNumber, null), extras
            )
        } catch (error: Throwable) {
            clearPendingOutgoing(identity.systemCallId)
            callRoutes(context).edit().remove(identity.systemCallId).apply()
            throw error
        }
        AndroidCallEventBridge.emitOutgoingDialing(identity)
    }

    fun markActive(context: Context, callId: String, emitFlutter: Boolean = true) {
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
        dispatchPendingTelecomFocus(context)
        if (androidx.core.content.ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.RECORD_AUDIO
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            startForegroundServiceSafely(context, callId)
        } else {
            Log.w(logTag, "Skipping call foreground service: RECORD_AUDIO is not granted")
        }
        if (emitFlutter) AndroidCallEventBridge.emitActive(identity)
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
        if (isManagedCall(context, callId)) {
            startForegroundServiceSafely(context, callId)
            AndroidCallMediaRuntime.startManagedInbound(context, callId)
            Log.i(logTag, "Managed Telecom answer delegated to service callId=$callId")
            return
        }
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
        // placeCall() is asynchronous on Samsung (and other OEMs). The
        // service-owned coordinator already waits for the eligible Telecom
        // connection, foreground promotion and focus together; do not fail
        // the outbound wait merely because onCreateOutgoingConnection has
        // not yet arrived.
        val pendingOutbound = !incoming && connection == null && pendingIdentity(callId) != null
        if ((!pendingOutbound && connection == null) || connection?.state == Connection.STATE_DISCONNECTED ||
            (incoming && connection?.state != Connection.STATE_RINGING && connection?.state != Connection.STATE_ACTIVE) ||
            (!incoming && !pendingOutbound && connection?.state != Connection.STATE_DIALING && connection?.state != Connection.STATE_ACTIVE)
        ) {
            callback(Result.failure(IllegalStateException("matching_telecom_connection_unavailable")))
            return
        }
        if (pendingOutbound) Log.i(logTag, "Awaiting pending outbound Telecom connection callId=$callId")
        if (incoming && connection?.state == Connection.STATE_RINGING) {
            OmniDeskCallNotification.dismissIncoming(context, callId)
            connection.setActive()
            AndroidCallMediaRuntime.onTelecomConnectionState(context, callId, Connection.STATE_ACTIVE, false)
            dispatchPendingTelecomFocus(context)
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
        val managed = isManagedCall(context, callId)
        if (managed) AndroidCallMediaRuntime.managedCallDeclined(context, callId, reason)
        OmniDeskCallNotification.dismissIncoming(context, callId)
        IncomingCallStateStore.saveAction(context, callId, "decline", reason)
        cleanup(
            context,
            callId,
            null,
            android.telecom.DisconnectCause(android.telecom.DisconnectCause.REJECTED),
        )
        AndroidCallEventBridge.emitAction("decline", callId, reason)
        if (!managed) launchFlutter(context)
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

    fun remoteHangup(context: Context, callId: String) {
        cleanup(context, callId, null,
            android.telecom.DisconnectCause(android.telecom.DisconnectCause.REMOTE))
        AndroidCallEventBridge.emitDisconnected(callId, "remote_hangup")
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
        val candidates = focusCandidates()
        val change = focusTracker.focusChanged(gained, candidates)
        Log.i(logTag, "ConnectionService focus callback gained=$gained " +
            "states=${candidates.joinToString(",") { it.state.name }} " +
            "mapped=${change != null} pending=${focusTracker.hasUnassignedFocus()}")
        if (change != null) {
            AndroidCallMediaRuntime.onTelecomFocusChanged(context, change.callId, change.gained, released)
        } else if (!gained) {
            released()
        }
    }

    private fun dispatchPendingTelecomFocus(context: Context) {
        val change = focusTracker.connectionAvailable(focusCandidates()) ?: return
        Log.i(logTag, "ConnectionService pending focus assigned state=connection_created")
        AndroidCallMediaRuntime.onTelecomFocusChanged(context, change.callId, change.gained)
    }

    private fun focusCandidates(): List<TelecomFocusTracker.Candidate> = connections.mapNotNull { (callId, connection) ->
        val state = when (connection.state) {
            Connection.STATE_ACTIVE -> TelecomFocusTracker.State.ACTIVE
            Connection.STATE_DIALING -> TelecomFocusTracker.State.DIALING
            Connection.STATE_RINGING -> TelecomFocusTracker.State.RINGING
            else -> null
        }
        state?.let { TelecomFocusTracker.Candidate(callId, it) }
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
        if (isManagedCall(context, callId)) AndroidCallMediaRuntime.managedCallDisconnected(callId)
        val connection = synchronized(pendingOutgoingLock) {
            clearPendingOutgoing(callId)
            connections.remove(callId)
        }
        focusTracker.connectionRemoved(callId, connections.isEmpty())
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
        callRoutes(context).edit().remove(callId).apply()
        MainActivity.clearIncomingCallLaunchPresentation(callId)
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

    fun isManagedCall(context: Context, callId: String): Boolean =
        callRoutes(context).getBoolean(callId, false)

    private fun callRoutes(context: Context) = context.getSharedPreferences("omnidesk_call_routes", Context.MODE_PRIVATE)

    internal fun routeForConnection(context: Context, callId: String, managed: Boolean) {
        if (callId.isNotBlank()) callRoutes(context).edit().putBoolean(callId, managed).apply()
    }

    internal fun isManagedRequest(extras: Bundle): Boolean = extras.getBoolean(extraManagedCall, false)

    private fun selfManagedPhoneAccountHandle(context: Context) = PhoneAccountHandle(
        ComponentName(context, OmniDeskConnectionService::class.java), selfManagedAccountId
    )

    private fun managedPhoneAccountHandle(context: Context) = PhoneAccountHandle(
        ComponentName(context, OmniDeskConnectionService::class.java), managedAccountId
    )

    const val extraManagedCall = "com.bigbrainzsolutions.omnidesk.MANAGED_CALL"
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
