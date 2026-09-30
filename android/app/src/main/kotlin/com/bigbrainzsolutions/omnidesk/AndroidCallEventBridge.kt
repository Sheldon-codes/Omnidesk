package com.bigbrainzsolutions.omnidesk

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/** Delivers native events only while a Flutter engine is attached. */
object AndroidCallEventBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var channel: MethodChannel? = null

    fun attach(value: MethodChannel) {
        channel = value
        Log.i(logTag, "Flutter call-event bridge attached")
    }

    fun detach(value: MethodChannel) {
        if (channel === value) {
            channel = null
            Log.i(logTag, "Flutter call-event bridge detached")
        }
    }

    fun offerAvailable(callId: String) {
        Log.i(logTag, "Bridging native offerAvailable callId=$callId")
        emit("offerAvailable", mapOf("callId" to callId))
    }

    fun emitIncomingPresented(callId: String) = emit("incomingPresented", mapOf("callId" to callId))
    fun emitIncomingOpened(callId: String) = emit("incomingOpened", mapOf("callId" to callId))
    /**
     * A backend call ID and the provider call SID are distinct identifiers.
     * Outbound calls receive both from /calls/initiate, and both must survive
     * the native boundary: Telecom tracks the former while backend completion
     * is keyed by the latter.
     */
    fun emitOutgoingDialing(identity: SystemCallIdentity) = emit(
        "outgoingDialing",
        identity.toFlutterMap(),
    )

    fun emitActive(identity: SystemCallIdentity) = emit("active", identity.toFlutterMap())
    fun emitDisconnected(callId: String, reason: String) = emit("disconnected", mapOf("callId" to callId, "reason" to reason))
    fun emitFailed(identity: SystemCallIdentity, reason: String?) = emit(
        "failed",
        identity.toFlutterMap() + mapOf("reason" to reason),
    )
    fun emitAction(action: String, callId: String, reason: String? = null) =
        emit(action, mapOf("callId" to callId, "reason" to reason))

    fun pushTokenChanged() {
        Log.i(logTag, "Bridging nativePushTokenChanged")
        emit("nativePushTokenChanged", emptyMap())
    }

    private fun emit(method: String, arguments: Map<String, Any?>) {
        mainHandler.post {
            val current = channel
            if (current == null) {
                Log.w(logTag, "Dropping native event method=$method: Flutter bridge absent")
            } else {
                current.invokeMethod(method, arguments)
                Log.i(logTag, "Native event delivered to Flutter method=$method")
            }
        }
    }

    private const val logTag = "OmniDeskCallPush"
}
