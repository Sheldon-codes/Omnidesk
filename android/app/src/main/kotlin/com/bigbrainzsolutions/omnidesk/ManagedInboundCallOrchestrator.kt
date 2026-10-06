package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Headless Telecom answer flow. The call media/service remains the source of truth. */
internal class ManagedInboundCallOrchestrator(
    private val context: Context,
    private val scheduler: ScheduledExecutorService,
    private val media: ATNativeMediaCoordinator,
) {
    private data class Attempt(val callId: String, val offerId: String, var mediaSessionId: String? = null,
        var waitingForOffer: ScheduledFuture<*>? = null, var terminal: Boolean = false)
    private val io: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "OmniDeskManagedCallApi").apply { isDaemon = true } }
    private val backend = ManagedCallBackendClient(context)
    private val lock = Any()
    private var attempt: Attempt? = null

    fun answer(callId: String) {
        val offer = IncomingCallStateStore.peekOffer(context)
        val offerId = offer?.get("offer_id")?.toString().orEmpty()
        if (offer?.get("call_id") != callId || offerId.isBlank()) {
            failBeforeAttempt(callId, offerId, "incoming_offer_unavailable")
            return
        }
        val auth = NativeCallCredentials.read(context)
        if (auth == null) {
            failBeforeAttempt(callId, offerId, "managed_call_session_unavailable")
            return
        }
        val offerWorkspace = offer["workspace_id"]?.toString().orEmpty()
        if (auth.workspaceId.isNotBlank() && offerWorkspace.isNotBlank() && auth.workspaceId != offerWorkspace) {
            failBeforeAttempt(callId, offerId, "managed_call_workspace_mismatch")
            return
        }
        val active = synchronized(lock) {
            attempt?.takeIf { it.callId == callId && !it.terminal }?.let { return }
            if (attempt?.terminal == false) {
                failBeforeAttempt(callId, offerId, "another_managed_call_active")
                return
            }
            Attempt(callId, offerId).also { attempt = it }
        }
        Log.i(TAG, "Managed inbound answer started callId=$callId generation=${media.currentSnapshot().generation + 1}")
        io.execute {
            try {
                if (context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    error("microphone_permission_required_before_managed_call")
                }
                backend.accept(callId, offerId)
                if (!isCurrent(active)) return@execute
                Log.i(TAG, "Managed inbound backend accept succeeded callId=$callId")
                OmniDeskTelecomManager.markActive(context, callId, emitFlutter = false)
                OmniDeskTelecomManager.prepareSystemAudio(context, callId, incoming = true) { audio ->
                    if (!isCurrent(active)) return@prepareSystemAudio
                    audio.fold(onSuccess = {
                        io.execute { initializeMedia(active) }
                    }, onFailure = { fail(callId, safeCode(it)) })
                }
            } catch (error: Throwable) {
                fail(callId, safeCode(error))
            }
        }
    }

    private fun initializeMedia(current: Attempt) {
        try {
            if (!isCurrent(current)) return
            val config = backend.mediaConfig()
            val gateway = config.optString("gatewayUrl")
            val token = config.optString("token")
            check(gateway.startsWith("wss://") && token.isNotBlank()) { "native_media_config_invalid" }
            media.initialize(gateway, token, current.callId) { initialized ->
                if (!isCurrent(current)) return@initialize
                initialized.fold(onSuccess = { sessionId ->
                    current.mediaSessionId = sessionId
                    io.execute {
                        try {
                            backend.mediaReady(current.callId, current.offerId)
                            Log.i(TAG, "Managed inbound media-ready succeeded callId=${current.callId}")
                            current.waitingForOffer = scheduler.schedule({
                                if (isCurrent(current)) fail(current.callId, "provider_offer_timeout")
                            }, 30, TimeUnit.SECONDS)
                        } catch (error: Throwable) { fail(current.callId, safeCode(error)) }
                    }
                }, onFailure = { fail(current.callId, safeCode(it)) })
            }
        } catch (error: Throwable) { fail(current.callId, safeCode(error)) }
    }

    fun onMediaEvent(event: Map<String, Any?>) {
        val current = synchronized(lock) { attempt?.takeIf { !it.terminal } } ?: return
        if (event["callSid"]?.toString() != current.callId) return
        when (event["event"]?.toString()) {
            "incoming" -> {
                current.waitingForOffer?.cancel(false)
                media.answerIncoming(current.callId) { result ->
                    result.fold(
                        onSuccess = { Log.i(TAG, "Managed inbound AT answer sent callId=${current.callId}") },
                        onFailure = { fail(current.callId, safeCode(it)) },
                    )
                }
            }
            "connected" -> {
                Log.i(TAG, "Managed inbound media connected callId=${current.callId}")
                finish(current)
            }
            "ended" -> remoteHangup(current)
            "error", "processTerminated" -> fail(current.callId, "native_media_${event["event"]}")
        }
    }

    fun onDisconnected(callId: String) {
        val current = synchronized(lock) { attempt?.takeIf { it.callId == callId && !it.terminal } } ?: return
        current.waitingForOffer?.cancel(false)
        current.terminal = true
        current.mediaSessionId?.let { media.endCall(it) { } }
        io.execute { try { backend.end(callId, "telecom_disconnected") } catch (_: Throwable) { }
            finally { backend.clearCallSession() } }
    }

    fun decline(callId: String, reason: String) {
        val offerId = IncomingCallStateStore.peekOffer(context)
            ?.takeIf { it["call_id"] == callId }?.get("offer_id")?.toString().orEmpty()
        if (offerId.isNotBlank()) io.execute {
            try { backend.decline(callId, offerId, reason) }
            catch (_: Throwable) { Log.w(TAG, "Managed call decline API failed callId=$callId") }
            finally {
                if (synchronized(lock) { attempt == null || attempt?.terminal == true }) {
                    OmniDeskCallForegroundService.stop(context)
                }
            }
        }
    }

    private fun remoteHangup(current: Attempt) {
        if (!isCurrent(current)) return
        synchronized(lock) {
            current.terminal = true
            current.waitingForOffer?.cancel(false)
        }
        Log.i(TAG, "Managed inbound remote hangup callId=${current.callId}")
        OmniDeskTelecomManager.remoteHangup(context, current.callId)
        io.execute { try { backend.end(current.callId, "remote_hangup") } catch (_: Throwable) { }
            finally { backend.clearCallSession() } }
    }

    private fun finish(current: Attempt) = synchronized(lock) {
        if (attempt === current) {
            current.waitingForOffer?.cancel(false)
        }
    }

    private fun fail(callId: String, reason: String) {
        val current = synchronized(lock) {
            attempt?.takeIf { it.callId == callId && !it.terminal }?.also {
                it.terminal = true
                it.waitingForOffer?.cancel(false)
            }
        } ?: return
        Log.w(TAG, "Managed inbound call failed callId=$callId reason=$reason")
        current.mediaSessionId?.let { session -> media.endCall(session) { } }
        OmniDeskTelecomManager.markFailed(context, callId, reason)
        io.execute { try { backend.end(callId, reason) } catch (_: Throwable) { }
            finally { backend.clearCallSession() } }
    }

    private fun failBeforeAttempt(callId: String, offerId: String, reason: String) {
        Log.w(TAG, "Managed inbound call rejected before setup callId=$callId reason=$reason")
        OmniDeskTelecomManager.markFailed(context, callId, reason)
        if (offerId.isNotBlank() && NativeCallCredentials.read(context) != null) io.execute {
            try { backend.decline(callId, offerId, reason) }
            catch (_: Throwable) { Log.w(TAG, "Managed call decline API failed callId=$callId") }
        }
    }

    private fun isCurrent(value: Attempt): Boolean = synchronized(lock) { attempt === value && !value.terminal }

    private fun safeCode(error: Throwable): String = when (error.message) {
        "microphone_permission_required_before_managed_call" -> "microphone_permission_required"
        "managed_call_session_unavailable" -> "managed_call_session_unavailable"
        "managed_call_workspace_mismatch" -> "managed_call_workspace_mismatch"
        "media_config_unavailable", "native_media_config_invalid" -> "media_config_unavailable"
        else -> error.message?.takeIf { it.matches(Regex("[a-z0-9_]{1,64}")) } ?: "managed_call_setup_failed"
    }

    fun dispose() { io.shutdownNow(); synchronized(lock) { attempt?.waitingForOffer?.cancel(false); attempt = null } }

    private companion object { const val TAG = "OmniDeskManagedCall" }
}
