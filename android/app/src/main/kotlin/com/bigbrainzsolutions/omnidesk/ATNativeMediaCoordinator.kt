package com.bigbrainzsolutions.omnidesk

import android.util.Log
import java.net.URI
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Service-owned AT signaling and media lifecycle; callbacks are generation-fenced. */
internal class ATNativeMediaCoordinator(
    private val executor: ScheduledExecutorService,
    private val publish: (Map<String, Any?>) -> Unit,
    private val clientFactory: ((ATSignalingClient.Listener) -> ATSignalingTransport)? = null,
    private val timeoutScale: Double = 1.0,
    private val log: (String) -> Unit = { message -> Log.i(LOG_TAG, message) },
    private val peerConnection: ATPeerConnection? = null,
) {
    enum class State { idle, connecting, creating, registering, registered, failed, disposed }
    data class Snapshot(val state: State, val sessionId: String?, val generation: Long, val sequence: Long)

    @Volatile private var snapshot = Snapshot(State.idle, null, 0, 0)
    private var signaling: ATSignalingTransport? = null
    private var timeout: ScheduledFuture<*>? = null
    private var keepalive: ScheduledFuture<*>? = null
    private var tokenFingerprint: ByteArray? = null
    private var endpoint: String? = null
    private var completion: ((Result<String>) -> Unit)? = null
    private var sequence = 0L
    @Volatile private var activeCallSid: String? = null
    private var callGeneration = 0L
    private var callAccepted = false
    private var iceConnected = false
    private var peerConnected = false
    private var connectedEmitted = false
    private var callRequestSent = false
    private var expectedIncomingCallId: String? = null
    private var pendingIncomingOffer: Map<String, Any?>? = null
    private var incomingCall = false
    private var answerInProgress = false
    private val answerCallbacks = mutableListOf<(Result<Unit>) -> Unit>()
    private var callTimeout: ScheduledFuture<*>? = null
    private val pendingLocalCandidates = mutableListOf<Map<String, Any?>?>()

    init {
        peerConnection?.onLocalCandidate = { candidate -> executor.execute {
            if (activeCallSid == null) return@execute
            if (callRequestSent) sendCandidate(candidate) else pendingLocalCandidates += candidate
        } }
        peerConnection?.onPeerState = { state -> executor.execute {
            if (activeCallSid == null) return@execute
            when (state) {
                "connected" -> {
                    peerConnected = true
                    diagnostic("webrtc_state", state)
                    emitConnectedIfReady()
                }
                "failed", "closed" -> terminateForMediaFailure("webrtc_$state", "peer_state")
                else -> { peerConnected = false; diagnostic("webrtc_state", state) }
            }
        } }
        peerConnection?.onIceState = { state -> executor.execute {
            if (activeCallSid == null) return@execute
            iceConnected = state == "connected" || state == "completed"
            diagnostic("ice_state", state)
            emitConnectedIfReady()
            if (state == "failed") terminateForMediaFailure("ice_failed", "ice_state")
        } }
        peerConnection?.onDiagnostic = { phase, result -> executor.execute {
            if (activeCallSid != null) diagnostic(phase, result)
        } }
        peerConnection?.onFailure = { reason -> executor.execute {
            if (activeCallSid != null) terminateForMediaFailure(reason, "peer_failure")
        } }
    }

    fun currentSnapshot(): Snapshot = snapshot
    fun hasActiveCall(): Boolean = activeCallSid != null

    /** Called on the service executor before ConnectionService acknowledges focus release. */
    fun onSystemAudioFocusLost(callback: () -> Unit = {}) {
        executor.execute {
            if (activeCallSid != null) terminateForMediaFailure("system_audio_focus_lost", "system_audio")
            callback()
        }
    }

    fun initialize(gateway: String, token: String, incomingCallId: String? = null, callback: (Result<String>) -> Unit) {
        executor.execute {
            if (!incomingCallId.isNullOrBlank()) {
                if (activeCallSid != null && activeCallSid != incomingCallId) {
                    callback(Result.failure(IllegalStateException("Another native call is active."))); return@execute
                }
                if (expectedIncomingCallId != null && expectedIncomingCallId != incomingCallId) {
                    callback(Result.failure(IllegalStateException("A different inbound call is already pending."))); return@execute
                }
                expectedIncomingCallId = incomingCallId
            }
            if (snapshot.state == State.registered && endpoint == gateway &&
                tokenFingerprint?.contentEquals(fingerprint(token)) == true
            ) {
                callback(Result.success(snapshot.sessionId!!))
                diagnostic("registration", "reused")
                return@execute
            }
            if (snapshot.state in setOf(State.connecting, State.creating, State.registering)) {
                if (endpoint == gateway && tokenFingerprint?.contentEquals(fingerprint(token)) == true) {
                    // Join the one in-flight registration; no second WebSocket is opened.
                    val existing = completion
                    completion = { result -> existing?.invoke(result); callback(result) }
                    return@execute
                }
                callback(Result.failure(IllegalStateException("A different AT registration is already in progress.")))
                return@execute
            }
            val uri = try { URI(gateway) } catch (_: Exception) { null }
            if (uri?.scheme != "wss" || uri.host.isNullOrBlank() || token.isBlank()) {
                callback(Result.failure(IllegalArgumentException("AT media configuration is invalid.")))
                return@execute
            }
            disposeTransport()
            val generation = snapshot.generation + 1
            endpoint = gateway
            tokenFingerprint = fingerprint(token)
            completion = callback
            setState(State.connecting, generation, UUID.randomUUID().toString())
            val socketListener = object : ATSignalingClient.Listener {
                override fun onSocketOpened(selectedProtocol: String?) = executor.execute {
                    if (!isCurrent(generation, State.connecting)) return@execute
                    val result = when (selectedProtocol) {
                        "at-protocol" -> "accepted_at_protocol"
                        null, "" -> "accepted_no_protocol"
                        else -> "accepted_other_or_none"
                    }
                    diagnostic("websocket", "opened:$result")
                    setState(State.creating, generation)
                    transportSend(generation, ATSignalingModels.createCommand(), State.creating)
                    armTimeout(generation, State.creating, 10)
                }
                override fun onText(text: String) = executor.execute { handle(text, generation) }
                override fun onClosed() = executor.execute { failIfCurrent(generation, "transport_closed") }
                override fun onFailure() = executor.execute { failIfCurrent(generation, "transport_failed") }
            }
            val client = clientFactory?.invoke(socketListener) ?: ATSignalingClient(socketListener)
            signaling = client
            armTimeout(generation, State.connecting, 15)
            try { client.connect(gateway, token) } catch (_: Throwable) {
                fail(generation, "transport_failed")
            }
        }
    }

    /** Outbound call setup. Backend call creation remains owned by Flutter. */
    fun dial(callSid: String, number: String, callback: (Result<String>) -> Unit) {
        executor.execute {
            if (snapshot.state != State.registered || signaling == null) {
                callback(Result.failure(IllegalStateException("AT signaling is not registered.")))
                return@execute
            }
            if (activeCallSid != null) {
                callback(Result.failure(IllegalStateException("Native media already has an active call.")))
                return@execute
            }
            if (callSid.isBlank() || number.isBlank()) {
                callback(Result.failure(IllegalArgumentException("Outbound call identity is invalid.")))
                return@execute
            }
            val rtc = peerConnection
            if (rtc == null) {
                callback(Result.failure(IllegalStateException("Native WebRTC is unavailable.")))
                return@execute
            }
            val generation = ++callGeneration
            activeCallSid = callSid
            incomingCall = false
            callAccepted = false
            iceConnected = false
            peerConnected = false
            connectedEmitted = false
            callRequestSent = false
            pendingLocalCandidates.clear()
            rtc.createOffer { outcome -> executor.execute {
                if (generation != callGeneration || activeCallSid != callSid) return@execute
                outcome.fold(
                    onSuccess = { offer ->
                        if (signaling?.send(ATSignalingModels.callCommand(number, offer)) != true) {
                            finishCall("call_request_failed", sendHangup = false)
                            callback(Result.failure(IllegalStateException("AT call request could not be sent.")))
                            return@fold
                        }
                        callRequestSent = true
                        pendingLocalCandidates.toList().forEach(::sendCandidate)
                        pendingLocalCandidates.clear()
                        diagnostic("provider_call", "request_sent")
                        mediaEvent("ringing", callSid)
                        callTimeout?.cancel(false)
                        callTimeout = executor.schedule({
                            if (generation == callGeneration && !connectedEmitted) {
                                finishCall("media_connection_timeout", sendHangup = true, emitProcessFailure = true)
                            }
                        }, (30 * timeoutScale).toLong().coerceAtLeast(1), TimeUnit.SECONDS)
                        callback(Result.success(snapshot.sessionId ?: callSid))
                    },
                    onFailure = {
                        finishCall("offer_failed", sendHangup = false)
                        callback(Result.failure(IllegalStateException("Native WebRTC offer creation failed.")))
                    },
                )
            } }
        }
    }

    fun endCall(mediaSessionId: String, callback: (Result<Unit>) -> Unit) {
        executor.execute {
            if (mediaSessionId != snapshot.sessionId) {
                callback(Result.failure(IllegalArgumentException("Native media session does not match.")))
                return@execute
            }
            finishCall("local_end", sendHangup = true)
            callback(Result.success(Unit))
        }
    }

    /** Explicit user-answer path; never invoked by AT incomingcall itself. */
    fun answerIncoming(callSid: String, callback: (Result<Unit>) -> Unit) {
        executor.execute {
            val offer = pendingIncomingOffer
            val rtc = peerConnection
            if (snapshot.state != State.registered || !incomingCall || activeCallSid != callSid || offer == null || rtc == null) {
                callback(Result.failure(IllegalStateException("No matching inbound AT offer is ready.")))
                return@execute
            }
            if (callRequestSent) { callback(Result.success(Unit)); return@execute }
            answerCallbacks += callback
            if (answerInProgress) return@execute
            answerInProgress = true
            diagnostic("answer_setup", "started")
            val generation = callGeneration
            rtc.createAnswer(offer) { outcome -> executor.execute {
                if (generation != callGeneration || activeCallSid != callSid || !incomingCall) return@execute
                outcome.fold(onSuccess = { answer ->
                    if (signaling?.send(ATSignalingModels.acceptCommand(answer)) != true) {
                        answerInProgress = false
                        terminateForMediaFailure("accept_send_failed", "answer_setup", sendHangup = false)
                        return@fold
                    }
                    answerInProgress = false
                    callRequestSent = true
                    diagnostic("provider_call", "accept_sent")
                    pendingLocalCandidates.toList().forEach(::sendCandidate)
                    pendingLocalCandidates.clear()
                    armCallTimeout(generation)
                    completeAnswerCallbacks(Result.success(Unit))
                }, onFailure = {
                    answerInProgress = false
                    terminateForMediaFailure(it, "answer_setup", sendHangup = false)
                })
            } }
        }
    }

    fun setMuted(muted: Boolean, callback: (Result<Unit>) -> Unit) {
        executor.execute {
            if (activeCallSid == null || peerConnection == null) {
                callback(Result.failure(IllegalStateException("No native call is active.")))
                return@execute
            }
            peerConnection.setMuted(muted)
            callback(Result.success(Unit))
        }
    }

    fun setHeld(held: Boolean, callback: (Result<Unit>) -> Unit) = sendControl(
        if (held) "hold" else "unhold", emptyMap(), callback,
    )

    fun sendDtmf(digit: String, callback: (Result<Unit>) -> Unit) {
        if (!digit.matches(Regex("^[0-9*#]$"))) {
            callback(Result.failure(IllegalArgumentException("DTMF digit is invalid.")))
            return
        }
        sendControl("dtmf", mapOf("dtmf" to mapOf("tones" to digit)), callback)
    }

    private fun sendControl(request: String, fields: Map<String, Any?>, callback: (Result<Unit>) -> Unit) {
        executor.execute {
            if (activeCallSid == null || snapshot.state != State.registered ||
                signaling?.send(ATSignalingModels.controlCommand(request, fields)) != true
            ) {
                callback(Result.failure(IllegalStateException("AT call signaling is unavailable.")))
            } else callback(Result.success(Unit))
        }
    }

    fun dispose(callback: (() -> Unit)? = null) {
        executor.execute {
            val old = snapshot
            timeout?.cancel(false); timeout = null
            keepalive?.cancel(false); keepalive = null
            completion?.invoke(Result.failure(IllegalStateException("AT registration disposed.")))
            completion = null
            finishCall("dispose", sendHangup = true)
            peerConnection?.dispose()
            disposeTransport()
            endpoint = null
            tokenFingerprint?.fill(0); tokenFingerprint = null
            setState(State.disposed, old.generation + 1, null)
            diagnostic("registration", "disposed")
            callback?.invoke()
        }
    }

    private fun handle(text: String, generation: Long) {
        if (snapshot.generation != generation) return
        when (val message = ATSignalingModels.decode(text)) {
            ATSignalingModels.Incoming.CreateSucceeded -> {
                if (snapshot.state != State.creating) return
                timeout?.cancel(false); timeout = null
                diagnostic("janus", "create_success")
                setState(State.registering, generation)
                diagnostic("at", "register_sent")
                transportSend(generation, ATSignalingModels.registerCommand(), State.registering)
                armTimeout(generation, State.registering, 15)
            }
            ATSignalingModels.Incoming.Registered -> {
                if (snapshot.state != State.registering) return
                timeout?.cancel(false); timeout = null
                setState(State.registered, generation)
                diagnostic("at", "registered")
                val ready = completion; completion = null
                ready?.invoke(Result.success(snapshot.sessionId!!))
                keepalive = executor.scheduleAtFixedRate({
                    if (isCurrent(generation, State.registered)) {
                        transportSend(generation, ATSignalingModels.keepaliveCommand(), State.registered)
                        diagnostic("janus", "keepalive_sent")
                    }
                }, (30 * timeoutScale).toLong().coerceAtLeast(1), (30 * timeoutScale).toLong().coerceAtLeast(1), TimeUnit.SECONDS)
            }
            is ATSignalingModels.Incoming.Trickle -> if (activeCallSid != null || expectedIncomingCallId != null) {
                message.candidate?.let { peerConnection?.addRemoteCandidate(it) }
            }
            is ATSignalingModels.Incoming.Event -> handleProviderEvent(message)
            is ATSignalingModels.Incoming.RegistrationFailed -> fail(generation, "registration_rejected")
            is ATSignalingModels.Incoming.Known -> {
                if (message.name == "closed") failIfCurrent(generation, "transport_closed")
                else if (message.name == "hangup") finishCall("hangup", sendHangup = false, remote = true)
                else diagnostic("signaling", "ignored_${message.name}")
            }
            ATSignalingModels.Incoming.Unknown -> diagnostic("signaling", "unknown_message_ignored")
        }
    }

    private fun transportSend(generation: Long, frame: String, required: State) {
        if (snapshot.generation != generation || snapshot.state != required || signaling?.send(frame) != true) {
            failIfCurrent(generation, "transport_send_failed")
        }
    }

    private fun armTimeout(generation: Long, state: State, seconds: Long) {
        timeout?.cancel(false)
        timeout = executor.schedule({
            if (isCurrent(generation, state)) fail(generation, "${state.name}_timeout")
        }, (seconds * timeoutScale).toLong().coerceAtLeast(1), TimeUnit.SECONDS)
    }

    private fun failIfCurrent(generation: Long, reason: String) {
        if (snapshot.generation == generation && snapshot.state !in setOf(State.failed, State.disposed, State.idle)) fail(generation, reason)
    }

    private fun fail(generation: Long, reason: String) {
        if (snapshot.generation != generation) return
        timeout?.cancel(false); timeout = null
        keepalive?.cancel(false); keepalive = null
        finishCall(reason, sendHangup = false, emitProcessFailure = true)
        disposeTransport()
        setState(State.failed, generation)
        diagnostic("registration", reason)
        val done = completion; completion = null
        done?.invoke(Result.failure(IllegalStateException("AT registration failed ($reason).")))
    }

    private fun disposeTransport() { signaling?.dispose(); signaling = null }
    private fun isCurrent(generation: Long, state: State) = snapshot.generation == generation && snapshot.state == state

    private fun setState(state: State, generation: Long, sessionId: String? = snapshot.sessionId) {
        snapshot = Snapshot(state, sessionId, generation, sequence)
        publish(mapOf("type" to "snapshot", "state" to state.name, "sessionId" to sessionId,
            "generation" to generation, "sequence" to sequence))
    }

    private fun diagnostic(phase: String, result: String) {
        sequence += 1
        snapshot = snapshot.copy(sequence = sequence)
        log("media phase=$phase result=$result generation=${snapshot.generation}")
        publish(mapOf("type" to "diagnostic", "phase" to phase, "result" to result,
            "sessionId" to snapshot.sessionId, "generation" to snapshot.generation, "sequence" to sequence))
    }

    private fun fingerprint(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))

    private fun handleProviderEvent(event: ATSignalingModels.Incoming.Event) {
        when (event.name) {
            "incomingcall" -> {
                val expected = expectedIncomingCallId
                val offer = event.jsep
                if (expected.isNullOrBlank()) {
                    diagnostic("incoming_call", "ignored_missing_call_identity")
                    return
                }
                if (activeCallSid == expected && pendingIncomingOffer != null) {
                    diagnostic("incoming_call", "duplicate_ignored")
                    return
                }
                if (activeCallSid != null || offer?.get("type") != "offer" || (offer["sdp"] as? String).isNullOrBlank()) {
                    diagnostic("incoming_call", "ignored_busy_or_invalid_offer")
                    return
                }
                callGeneration++
                activeCallSid = expected
                incomingCall = true
                pendingIncomingOffer = offer
                callAccepted = false
                iceConnected = false
                peerConnected = false
                connectedEmitted = false
                callRequestSent = false
                answerInProgress = false
                pendingLocalCandidates.clear()
                diagnostic("incoming_call", "offer_received")
                diagnostic("remote_offer", "stored")
                mediaEvent("incoming", expected)
            }
            "calling", "progress" -> {
                if (!incomingCall) event.jsep?.let(::applyRemoteJsep)
                activeCallSid?.let { mediaEvent("ringing", it) }
            }
            "accepted" -> {
                callAccepted = true
                diagnostic("provider_call", "accepted")
                if (!incomingCall) event.jsep?.let(::applyRemoteJsep)
                emitConnectedIfReady()
            }
            "hangup", "decline", "missed_call" -> finishCall(event.name, sendHangup = false, remote = true)
            "registration_failed" -> diagnostic("registration", "provider_rejected")
            else -> diagnostic("signaling", "ignored_event")
        }
    }

    private fun applyRemoteJsep(jsep: Map<String, Any?>) {
        val rtc = peerConnection ?: return
        rtc.applyRemoteDescription(jsep) { result -> executor.execute {
            if (activeCallSid == null) return@execute
            if (result.isFailure) {
                finishCall("remote_description_failed", sendHangup = true, emitProcessFailure = true)
            } else emitConnectedIfReady()
        } }
    }

    private fun sendCandidate(candidate: Map<String, Any?>?) {
        if (signaling?.send(ATSignalingModels.trickleCommand(candidate)) != true) {
            finishCall("trickle_send_failed", sendHangup = true, emitProcessFailure = true)
        }
    }

    private fun emitConnectedIfReady() {
        if (!connectedEmitted && callAccepted && callRequestSent && iceConnected && peerConnected) {
            activeCallSid?.let {
                connectedEmitted = true
                callTimeout?.cancel(false); callTimeout = null
                mediaEvent("connected", it)
            }
        }
    }

    private fun finishCall(
        reason: String,
        sendHangup: Boolean,
        emitProcessFailure: Boolean = false,
        remote: Boolean = false,
        processFailureMessage: String? = null,
    ) {
        val sid = activeCallSid ?: expectedIncomingCallId
        if (sid == null && pendingIncomingOffer == null) return
        if (sendHangup && activeCallSid != null) signaling?.send(ATSignalingModels.controlCommand("hangup"))
        callGeneration++
        callTimeout?.cancel(false); callTimeout = null
        activeCallSid = null
        expectedIncomingCallId = null
        pendingIncomingOffer = null
        incomingCall = false
        answerInProgress = false
        completeAnswerCallbacks(Result.failure(IllegalStateException("Inbound call ended before media answer completed.")))
        callAccepted = false
        iceConnected = false
        peerConnected = false
        connectedEmitted = false
        callRequestSent = false
        pendingLocalCandidates.clear()
        peerConnection?.closePeer()
        val terminalResult = when {
            remote -> "remote_hangup"
            reason == "local_end" -> "local_hangup"
            emitProcessFailure -> "failed_${failureCode(reason)}"
            else -> "terminated"
        }
        diagnostic("call", terminalResult)
        if (sid != null) {
            if (emitProcessFailure) mediaEvent("processTerminated", sid, processFailureMessage ?: reason)
            else mediaEvent("ended", sid, reason)
        }
    }

    private fun armCallTimeout(generation: Long) {
        callTimeout?.cancel(false)
        callTimeout = executor.schedule({
            if (generation == callGeneration && !connectedEmitted) {
                finishCall("media_connection_timeout", sendHangup = true, emitProcessFailure = true)
            }
        }, (30 * timeoutScale).toLong().coerceAtLeast(1), TimeUnit.SECONDS)
    }

    private fun completeAnswerCallbacks(result: Result<Unit>) {
        val callbacks = answerCallbacks.toList()
        answerCallbacks.clear()
        callbacks.forEach { it(result) }
    }

    private fun terminateForMediaFailure(reason: Any?, phase: String, sendHangup: Boolean = true) {
        val code = failureCode(reason)
        val message = failureMessage(code)
        diagnostic(phase, "failed_$code")
        completeAnswerCallbacks(Result.failure(IllegalStateException(message)))
        activeCallSid?.let { mediaEvent("error", it, message) }
        finishCall(
            "media_$code",
            sendHangup = sendHangup,
            emitProcessFailure = true,
            processFailureMessage = message,
        )
    }

    /** Allowlisted classification only: never emit native exception or SDP text. */
    private fun failureCode(value: Any?): String {
        val rawValue = when (value) {
            is Throwable -> value.message
            else -> value?.toString()
        }?.substringBefore(':')?.trim()?.lowercase().orEmpty()
        val raw = rawValue.removePrefix("media_").removePrefix("answer_").removePrefix("peer_")
        return when (raw) {
            "microphone_permission_denied" -> "microphone_permission_denied"
            "audio_focus_denied" -> "audio_focus_denied"
            "peer_factory_unavailable" -> "peer_factory_unavailable"
            "peer_connection_unavailable" -> "peer_connection_unavailable"
            "audio_track_attach_failed" -> "audio_track_attach_failed"
            "invalid_remote_description" -> "invalid_remote_description"
            "remote_description_failed", "remote_offer_failed" -> "remote_description_failed"
            "remote_candidate_rejected" -> "remote_candidate_rejected"
            "answer_creation_failed" -> "answer_creation_failed"
            "local_description_failed" -> "local_description_failed"
            "ice_failed" -> "ice_failed"
            "media_connection_timeout" -> "media_connection_timeout"
            "accept_send_failed" -> "accept_send_failed"
            else -> "native_media_setup_failed"
        }
    }

    private fun failureMessage(code: String): String = when (code) {
        "microphone_permission_denied" -> "Microphone permission is required to answer this call."
        "audio_focus_denied" -> "Android denied audio focus while preparing the call. Please try again."
        "peer_factory_unavailable", "peer_connection_unavailable" -> "Android could not initialize native call media. Please try again."
        "audio_track_attach_failed" -> "Android could not prepare the call audio track. Please try again."
        "invalid_remote_description", "remote_description_failed" -> "The incoming call offer could not be applied. Please try again."
        "remote_candidate_rejected" -> "The incoming call network candidate could not be applied. Please try again."
        "answer_creation_failed", "local_description_failed" -> "Android could not create the incoming call answer. Please try again."
        "ice_failed", "media_connection_timeout" -> "The call media connection could not be established. Please try again."
        "accept_send_failed" -> "The incoming call answer could not be sent to the provider. Please try again."
        else -> "Native call media setup failed. Please try again."
    }

    private fun mediaEvent(type: String, callSid: String?, reason: String? = null) {
        sequence += 1
        val event = mutableMapOf<String, Any?>(
            "type" to "media_event", "event" to type, "callSid" to callSid,
            "sessionId" to snapshot.sessionId, "generation" to snapshot.generation,
            "sequence" to sequence,
        )
        if (reason != null) event["reason"] = reason
        publish(event)
    }

    companion object { private const val LOG_TAG = "ATNativeMedia" }
}
