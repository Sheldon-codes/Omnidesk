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
    fun emitOutgoingDialing(callId: String) = emit("outgoingDialing", mapOf("callId" to callId))
    fun emitActive(callId: String) = emit("active", mapOf("callId" to callId))
    fun emitDisconnected(callId: String, reason: String) = emit("disconnected", mapOf("callId" to callId, "reason" to reason))
    fun emitFailed(callId: String, reason: String?) = emit("failed", mapOf("callId" to callId, "reason" to reason))
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
