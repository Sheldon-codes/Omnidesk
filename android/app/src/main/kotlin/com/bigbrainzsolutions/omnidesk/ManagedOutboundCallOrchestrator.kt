package com.bigbrainzsolutions.omnidesk

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.SystemClock
import android.telecom.DisconnectCause
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Headless external-dialer calls. Telecom and media identities are deliberately separate. */
internal class ManagedOutboundCallOrchestrator(
    private val context: Context,
    private val scheduler: ScheduledExecutorService,
    private val media: ATNativeMediaCoordinator,
    private val backendFactory: () -> ManagedCallBackendClient = { ManagedCallBackendClient(context) },
    private val emit: (Map<String, Any?>) -> Unit = {},
) {
    private class Attempt(val localId: String, val number: String, val generation: Long,
                          val backend: ManagedCallBackendClient) {
        val gate = ManagedOutboundAttemptGate()
        var mediaSessionId: String? = null
        var timeout: ScheduledFuture<*>? = null
    }

    private val io = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "OmniDeskOutboundApi").apply { isDaemon = true }
    }
    private val lock = Any()
    private var generation = 0L
    private var attempt: Attempt? = null
    private val cancelledBeforeStart = mutableSetOf<String>()

    fun start(localId: String, number: String) {
        val current = synchronized(lock) {
            if (cancelledBeforeStart.remove(localId)) return
            if (attempt?.localId == localId && attempt?.gate?.isOpen() == true) return
            if (attempt?.gate?.isOpen() == true || media.hasActiveCall()) {
                OmniDeskTelecomManager.finishExternalCall(context, localId, DisconnectCause.BUSY, "another_call_active")
                return
            }
            Attempt(localId, number, ++generation, backendFactory()).also { attempt = it }
        }
        Log.i(TAG, "External outbound started attempt=${current.generation}")
        publish(current, "dialing")
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            fail(current, "microphone_permission_required")
            return
        }
        if (NativeCallCredentials.read(context) == null) {
            OmniDeskCallNotification.showManagedSignInRequired(context)
            fail(current, "managed_call_session_unavailable")
            return
        }
        current.timeout = scheduler.schedule({ fail(current, "outbound_setup_timeout") }, 75, TimeUnit.SECONDS)
        OmniDeskTelecomManager.prepareSystemAudio(context, localId, incoming = false) { audio ->
            if (!isCurrent(current)) return@prepareSystemAudio
            audio.fold(onSuccess = { io.execute { initiate(current) } },
                onFailure = { fail(current, safeCode(it)) })
        }
    }

    private fun initiate(current: Attempt) {
        try {
            if (!isCurrent(current)) return
            val outbound = current.backend.initiate(current.number)
            current.gate.backendCreated(outbound.callId, outbound.callSid)
            if (!isCurrent(current)) {
                finalizeBackend(current)
                return
            }
            publish(current, "backend_initiated")
            val config = current.backend.mediaConfig()
            if (!isCurrent(current)) return
            val gateway = config.optString("gatewayUrl")
            val token = config.optString("token")
            check(gateway.startsWith("wss://") && token.isNotBlank()) { "media_config_unavailable" }
            media.initialize(gateway, token, null) { initialized ->
                if (!isCurrent(current)) return@initialize
                initialized.fold(onSuccess = { sessionId ->
                    synchronized(lock) { current.mediaSessionId = sessionId }
                    media.dial(outbound.callSid, outbound.number) { dialed ->
                        if (!isCurrent(current)) return@dial
                        dialed.fold(onSuccess = {
                            Log.i(TAG, "External outbound AT dial requested attempt=${current.generation}")
                        }, onFailure = { fail(current, safeCode(it)) })
                    }
                }, onFailure = { fail(current, safeCode(it)) })
            }
        } catch (error: Throwable) {
            if (error is ManagedCallBackendClient.HttpFailure && error.status in listOf(401, 403)) {
                NativeCallCredentials.clear(context)
                OmniDeskCallNotification.showManagedSignInRequired(context)
                fail(current, "managed_call_sign_in_required")
            } else fail(current, safeCode(error))
        }
    }

    fun onMediaEvent(event: Map<String, Any?>) {
        val current = synchronized(lock) { attempt?.takeIf { it.gate.isOpen() } } ?: return
        if (event["callSid"]?.toString() != current.gate.callSid()) return
        when (event["event"]?.toString()) {
            "connected" -> {
                val first = synchronized(lock) {
                    if (!current.gate.isOpen() || current.gate.connectedAt() != null) false
                    else if (OmniDeskTelecomManager.markExternalActive(context, current.localId)) {
                        current.gate.markConnected(SystemClock.elapsedRealtime())
                    } else false
                }
                if (first) {
                    current.timeout?.cancel(false)
                    Log.i(TAG, "External outbound connected attempt=${current.generation}")
                    publish(current, "connected")
                }
            }
            "ended" -> terminate(current, DisconnectCause.REMOTE, "remote_hangup")
            "error", "processTerminated" -> fail(current, "native_media_failed")
        }
    }

    fun onDisconnected(localId: String) {
        val current = synchronized(lock) { attempt?.takeIf { it.localId == localId && it.gate.isOpen() } }
        if (current == null) {
            synchronized(lock) { cancelledBeforeStart.add(localId) }
            OmniDeskTelecomManager.finishExternalCall(context, localId, DisconnectCause.LOCAL, "local_disconnect")
            return
        }
        terminate(current, DisconnectCause.LOCAL, "local_disconnect")
    }

    private fun fail(current: Attempt, code: String) = terminate(current, DisconnectCause.ERROR, code)

    private fun terminate(current: Attempt, cause: Int, reason: String) {
        val session = synchronized(lock) {
            if (attempt !== current || !current.gate.close()) return
            current.timeout?.cancel(false)
            current.mediaSessionId
        }
        Log.i(TAG, "External outbound terminal attempt=${current.generation} reason=$reason")
        publish(current, "ended", reason)
        val finish = {
            OmniDeskTelecomManager.finishExternalCall(context, current.localId, cause, reason)
            io.execute { finalizeBackend(current) }
        }
        if (session == null) finish()
        else media.endCall(session) { finish() }
    }

    private fun finalizeBackend(current: Attempt) {
        val backendIds = current.gate.claimCompletion()
        if (backendIds == null) {
            current.backend.clearCallSession()
            return
        }
        try {
            if (backendIds.connectedAtElapsedMs != null) {
                val seconds = (SystemClock.elapsedRealtime() - backendIds.connectedAtElapsedMs).coerceAtLeast(0) / 1000
                current.backend.complete(backendIds.callSid, seconds)
            } else current.backend.end(backendIds.callId, "media_setup_failed")
        } catch (error: Throwable) {
            Log.w(TAG, "External outbound backend completion failed code=${safeCode(error)}")
        } finally { current.backend.clearCallSession() }
    }

    private fun isCurrent(current: Attempt): Boolean = synchronized(lock) { attempt === current && current.gate.isOpen() }

    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        attempt?.let { current ->
            mapOf("type" to "external_outbound_snapshot", "attemptId" to current.localId,
                "generation" to current.generation,
                "state" to if (!current.gate.isOpen()) "ended" else if (current.gate.connectedAt() != null) "connected" else "dialing",
                "backendCallId" to current.gate.callId())
        } ?: mapOf("type" to "external_outbound_snapshot", "state" to "idle", "generation" to generation)
    }

    fun hasLiveAttempt(): Boolean = synchronized(lock) { attempt?.gate?.isOpen() == true }

    private fun publish(current: Attempt, state: String, reason: String? = null) {
        emit(mapOf("type" to "external_outbound_snapshot", "attemptId" to current.localId,
            "generation" to current.generation, "state" to state,
            "backendCallId" to current.gate.callId(), "reason" to reason))
    }

    fun dispose() {
        synchronized(lock) { attempt?.gate?.close(); attempt?.timeout?.cancel(false); attempt = null }
        io.shutdownNow()
    }

    private fun safeCode(error: Throwable): String =
        error.message?.takeIf { it.matches(Regex("[a-z0-9_]{1,64}")) } ?: "outbound_setup_failed"

    private companion object { const val TAG = "OmniDeskExternalCall" }
}
