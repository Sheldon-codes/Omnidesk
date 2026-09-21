package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause

class OmniDeskConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest,
    ): Connection = OmniDeskTelecomManager.createIncomingConnection(this, request.extras ?: Bundle())

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest,
    ): Connection = OmniDeskTelecomManager.createOutgoingConnection(this, request.extras ?: Bundle())

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
        OmniDeskTelecomManager.markFailed(this, request.extras?.getString(OmniDeskTelecomManager.extraCallId).orEmpty(), "telecom_outgoing_rejected")
    }
}

class OmniDeskConnection(
    private val context: Context,
    private val callId: String,
    private val incoming: Boolean,
) : Connection() {
    init {
        connectionCapabilities = CAPABILITY_HOLD or CAPABILITY_MUTE
    }

    override fun onAnswer() {
        if (incoming) OmniDeskTelecomManager.answer(context, callId)
    }

    override fun onReject() {
        if (incoming) OmniDeskTelecomManager.decline(context, callId)
    }

    override fun onDisconnect() {
        OmniDeskTelecomManager.disconnect(context, callId)
    }

    override fun onHold() {
        setOnHold()
    }

    override fun onUnhold() {
        setActive()
    }

}
