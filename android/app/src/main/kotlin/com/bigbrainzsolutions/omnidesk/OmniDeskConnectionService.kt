package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.os.Build
import android.os.OutcomeReceiver
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi

class OmniDeskConnectionService : ConnectionService() {
    override fun onConnectionServiceFocusGained() {
        super.onConnectionServiceFocusGained()
        OmniDeskTelecomManager.onConnectionServiceFocusChanged(applicationContext, true)
    }

    override fun onConnectionServiceFocusLost() {
        OmniDeskTelecomManager.onConnectionServiceFocusChanged(applicationContext, false) {
            // ConnectionService focus is acknowledged only after the service
            // has stopped WebRTC capture/playout for the lost lease.
            if (Build.VERSION.SDK_INT >= 28) connectionServiceFocusReleased()
        }
    }
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest,
    ): Connection = OmniDeskTelecomManager.createIncomingConnection(this, request.extras ?: Bundle())

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest,
    ): Connection = OmniDeskTelecomManager.createOutgoingConnection(this, request)

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest,
    ) {
        OmniDeskTelecomManager.markFailed(this, request.extras?.getString(OmniDeskTelecomManager.extraCallId).orEmpty(), "telecom_incoming_rejected")
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest,
    ) {
        OmniDeskTelecomManager.handleOutgoingConnectionFailed(
            this,
            request.extras ?: Bundle(),
            "telecom_outgoing_rejected",
        )
    }
}

open class OmniDeskConnection(
    protected val context: Context,
    val identity: SystemCallIdentity,
    val incoming: Boolean,
) : Connection() {
    private data class PendingLegacyRoute(val target: Int, val callbacks: MutableList<(Result<Unit>) -> Unit>)
    private var pendingLegacyRoute: PendingLegacyRoute? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    init {
        connectionCapabilities = CAPABILITY_HOLD or CAPABILITY_MUTE
    }

    override fun onAnswer() {
        if (incoming) OmniDeskTelecomManager.answer(context, identity.systemCallId)
    }

    override fun onReject() {
        if (incoming) OmniDeskTelecomManager.decline(context, identity.systemCallId)
    }

    override fun onDisconnect() {
        OmniDeskTelecomManager.disconnect(context, identity.systemCallId)
    }

    override fun onHold() {
        AndroidCallMediaRuntime.setHeld(true)
        setOnHold()
    }

    override fun onUnhold() {
        AndroidCallMediaRuntime.setHeld(false)
        setActive()
    }

    override fun onPlayDtmfTone(digit: Char) {
        AndroidCallMediaRuntime.sendDtmf(digit.toString())
    }

    @Synchronized override fun onCallAudioStateChanged(state: android.telecom.CallAudioState) {
        super.onCallAudioStateChanged(state)
        Log.i("OmniDeskTelecom", "Connection audio state observed state=${this.state} managed=${OmniDeskTelecomManager.isManagedCall(context, identity.systemCallId)}")
        AndroidCallMediaRuntime.setMuted(state.isMuted)
        AndroidCallMediaRuntime.onTelecomConnectionState(
            context, identity.systemCallId,
            state = this.state,
            audioStateObserved = true,
        )
        pendingLegacyRoute?.takeIf { state.route == it.target }?.let { pending ->
            pendingLegacyRoute = null
            pending.callbacks.forEach { it(Result.success(Unit)) }
        }
    }

    @Synchronized open fun requestSpeakerRoute(enabled: Boolean, callback: (Result<Unit>) -> Unit) {
        var localLegacyRequest: PendingLegacyRoute? = null
        try {
            val route = if (enabled) android.telecom.CallAudioState.ROUTE_SPEAKER else android.telecom.CallAudioState.ROUTE_EARPIECE
            if (callAudioState?.route == route) {
                callback(Result.success(Unit))
                return
            }
            pendingLegacyRoute?.let { pending ->
                if (pending.target == route) {
                    pending.callbacks += callback
                    return
                }
                pendingLegacyRoute = null
                pending.callbacks.forEach { it(Result.failure(IllegalStateException("telecom_route_superseded"))) }
            }
            val pending = PendingLegacyRoute(route, mutableListOf(callback))
            localLegacyRequest = pending
            pendingLegacyRoute = pending
            @Suppress("DEPRECATION")
            setAudioRoute(route)
            mainHandler.postDelayed({
                synchronized(this@OmniDeskConnection) {
                    if (pendingLegacyRoute === pending) {
                        pendingLegacyRoute = null
                        pending.callbacks.forEach { it(Result.failure(IllegalStateException("telecom_route_timeout"))) }
                    }
                }
            }, LEGACY_ROUTE_TIMEOUT_MS)
        } catch (_: Throwable) {
            val pending = localLegacyRequest
            if (pending != null && pendingLegacyRoute === pending) {
                pendingLegacyRoute = null
                pending.callbacks.forEach { it(Result.failure(IllegalStateException("telecom_route_failed"))) }
            } else {
                callback(Result.failure(IllegalStateException("telecom_route_failed")))
            }
        }
    }

    companion object { private const val LEGACY_ROUTE_TIMEOUT_MS = 3_000L }

}

/** API-34 Telecom endpoint adapter; never loaded on older Android releases. */
@RequiresApi(34)
internal class OmniDeskConnectionApi34(
    context: android.content.Context,
    identity: SystemCallIdentity,
    incoming: Boolean,
) : OmniDeskConnection(context, identity, incoming) {
    private var endpoints: List<android.telecom.CallEndpoint> = emptyList()

    @Synchronized override fun onAvailableCallEndpointsChanged(callEndpoints: MutableList<android.telecom.CallEndpoint>) {
        endpoints = callEndpoints.toList()
        AndroidCallMediaRuntime.onTelecomConnectionState(
            context, identity.systemCallId, state = this.state, audioStateObserved = false,
        )
    }

    @Synchronized override fun onCallEndpointChanged(callEndpoint: android.telecom.CallEndpoint) {
        endpoints = endpoints.filter { it.identifier != callEndpoint.identifier } + callEndpoint
        AndroidCallMediaRuntime.onTelecomConnectionState(
            context, identity.systemCallId, state = this.state, audioStateObserved = false,
        )
    }

    @Synchronized override fun requestSpeakerRoute(enabled: Boolean, callback: (Result<Unit>) -> Unit) {
        val targetType = if (enabled) android.telecom.CallEndpoint.TYPE_SPEAKER else android.telecom.CallEndpoint.TYPE_EARPIECE
        val endpoint = endpoints.firstOrNull { it.endpointType == targetType }
        if (endpoint == null) {
            callback(Result.failure(IllegalStateException("requested_telecom_endpoint_unavailable")))
            return
        }
        requestCallEndpointChange(endpoint, context.mainExecutor,
            object : OutcomeReceiver<Void, android.telecom.CallEndpointException> {
                override fun onResult(result: Void?) = callback(Result.success(Unit))
                override fun onError(error: android.telecom.CallEndpointException) {
                    callback(Result.failure(IllegalStateException("telecom_route_rejected")))
                }
            })
    }
}
