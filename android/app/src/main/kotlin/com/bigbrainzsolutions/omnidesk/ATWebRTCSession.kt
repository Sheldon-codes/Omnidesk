package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.media.AudioAttributes
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.AudioDeviceModule
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.atomic.AtomicBoolean

internal interface ATPeerConnection {
    var onLocalCandidate: ((Map<String, Any?>?) -> Unit)?
    var onPeerState: ((String) -> Unit)?
    var onIceState: ((String) -> Unit)?
    var onDiagnostic: ((String, String) -> Unit)?
    var onFailure: ((String) -> Unit)?
    fun createOffer(callback: (Result<Map<String, Any?>>) -> Unit)
    fun createAnswer(remoteOffer: Map<String, Any?>, callback: (Result<Map<String, Any?>>) -> Unit)
    fun applyRemoteDescription(jsep: Map<String, Any?>, callback: (Result<Unit>) -> Unit)
    fun addRemoteCandidate(value: Map<String, Any?>)
    fun setMuted(muted: Boolean)
    fun closePeer()
    fun dispose()
}

/** One service-owned audio-only Unified Plan peer connection. */
internal class ATWebRTCSession(
    context: Context,
    private val executor: ScheduledExecutorService,
    private val audioCoordinator: AndroidCallAudioCoordinator,
) : ATPeerConnection {
    private val appContext = context.applicationContext
    private var factory: PeerConnectionFactory? = null
    private var audioDeviceModule: AudioDeviceModule? = null
    private var peer: PeerConnection? = null
    private var audioSource: AudioSource? = null
    private var localTrack: AudioTrack? = null
    private val pendingRemoteCandidates = mutableListOf<IceCandidate>()
    private var hasRemoteDescription = false
    private var endOfCandidatesSent = false
    private var peerGeneration = 0L
    private var disposed = false
    private var peerCreationFailure = "peer_connection_unavailable"

    /** Candidate is null for AT's {"completed":true} end-of-candidates frame. */
    override var onLocalCandidate: ((Map<String, Any?>?) -> Unit)? = null
    override var onPeerState: ((String) -> Unit)? = null
    override var onIceState: ((String) -> Unit)? = null
    override var onDiagnostic: ((String, String) -> Unit)? = null
    override var onFailure: ((String) -> Unit)? = null

    override fun createOffer(callback: (Result<Map<String, Any?>>) -> Unit) {
        executor.execute {
            val connection = createPeer()
            if (connection == null) {
                callback(Result.failure(IllegalStateException(peerCreationFailure)))
                return@execute
            }
            val constraints = MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            }
            val generation = peerGeneration
            connection.createOffer(object : SdpObserver {
                override fun onCreateSuccess(description: SessionDescription) {
                    executor.execute {
                        if (!isCurrent(generation)) return@execute
                        connection.setLocalDescription(object : SdpObserver {
                            override fun onSetSuccess() = executor.execute {
                                if (isCurrent(generation)) {
                                    callback(Result.success(jsep(description)))
                                }
                            }
                            override fun onSetFailure(error: String) = executor.execute {
                                if (isCurrent(generation)) {
                                    closePeer()
                                    callback(Result.failure(IllegalStateException("local_description_failed")))
                                }
                            }
                            override fun onCreateSuccess(description: SessionDescription) = Unit
                            override fun onCreateFailure(error: String) = Unit
                        }, description)
                    }
                }
                override fun onCreateFailure(error: String) = executor.execute {
                    if (isCurrent(generation)) {
                        closePeer()
                        callback(Result.failure(IllegalStateException("offer_creation_failed")))
                    }
                }
                override fun onSetSuccess() = Unit
                override fun onSetFailure(error: String) = Unit
            }, constraints)
        }
    }

    override fun applyRemoteDescription(jsep: Map<String, Any?>, callback: (Result<Unit>) -> Unit) {
        executor.execute {
            val type = jsep["type"] as? String
            val sdp = jsep["sdp"] as? String
            val connection = peer
            val descriptionType = when (type) {
                "offer" -> SessionDescription.Type.OFFER
                "answer" -> SessionDescription.Type.ANSWER
                "pranswer" -> SessionDescription.Type.PRANSWER
                else -> null
            }
            if (connection == null || descriptionType == null || sdp.isNullOrBlank()) {
                callback(Result.failure(IllegalArgumentException("invalid_remote_description")))
                return@execute
            }
            val generation = peerGeneration
            connection.setRemoteDescription(object : SdpObserver {
                override fun onSetSuccess() = executor.execute {
                    if (!isCurrent(generation)) return@execute
                    hasRemoteDescription = true
                    onDiagnostic?.invoke(if (descriptionType == SessionDescription.Type.OFFER) "remote_offer" else "remote_description", "applied")
                    val buffered = pendingRemoteCandidates.toList()
                    pendingRemoteCandidates.clear()
                    val failed = buffered.any { !connection.addIceCandidate(it) }
                    if (failed) callback(Result.failure(IllegalStateException("remote_candidate_rejected")))
                    else callback(Result.success(Unit))
                }
                override fun onSetFailure(error: String) = executor.execute {
                    if (isCurrent(generation)) callback(Result.failure(IllegalStateException("remote_description_failed")))
                }
                override fun onCreateSuccess(description: SessionDescription) = Unit
                override fun onCreateFailure(error: String) = Unit
            }, SessionDescription(descriptionType, sdp))
        }
    }

    override fun createAnswer(remoteOffer: Map<String, Any?>, callback: (Result<Map<String, Any?>>) -> Unit) {
        executor.execute {
            val connection = createPeer()
            if (connection == null) {
                callback(Result.failure(IllegalStateException(peerCreationFailure)))
                return@execute
            }
            applyRemoteDescription(remoteOffer) { applied -> executor.execute {
                if (applied.isFailure) {
                    callback(Result.failure(applied.exceptionOrNull() ?: IllegalStateException("remote_offer_failed")))
                    return@execute
                }
                val generation = peerGeneration
                val constraints = MediaConstraints()
                connection.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(description: SessionDescription) = executor.execute {
                        if (!isCurrent(generation)) return@execute
                        onDiagnostic?.invoke("answer", "created")
                        connection.setLocalDescription(object : SdpObserver {
                            override fun onSetSuccess() = executor.execute {
                                if (isCurrent(generation)) {
                                    onDiagnostic?.invoke("answer", "set")
                                    callback(Result.success(jsep(description)))
                                }
                            }
                            override fun onSetFailure(error: String) = executor.execute {
                                if (isCurrent(generation)) callback(Result.failure(IllegalStateException("local_description_failed")))
                            }
                            override fun onCreateSuccess(description: SessionDescription) = Unit
                            override fun onCreateFailure(error: String) = Unit
                        }, description)
                    }
                    override fun onCreateFailure(error: String) = executor.execute {
                        if (isCurrent(generation)) callback(Result.failure(IllegalStateException("answer_creation_failed")))
                    }
                    override fun onSetSuccess() = Unit
                    override fun onSetFailure(error: String) = Unit
                }, constraints)
            } }
        }
    }

    override fun addRemoteCandidate(value: Map<String, Any?>) {
        executor.execute {
            val candidate = if (value["completed"] == true) {
                IceCandidate("audio", 0, "")
            } else {
                val sdp = value["candidate"] as? String ?: return@execute
                val mid = value["sdpMid"] as? String ?: return@execute
                val line = (value["sdpMLineIndex"] as? Number)?.toInt() ?: return@execute
                if (line < 0) return@execute
                IceCandidate(mid, line, sdp)
            }
            val connection = peer
            if (connection == null || !hasRemoteDescription) {
                pendingRemoteCandidates.add(candidate)
            } else if (!connection.addIceCandidate(candidate)) {
                onFailure?.invoke("remote_candidate_rejected")
            }
        }
    }

    override fun setMuted(muted: Boolean) {
        dispatch { localTrack?.setEnabled(!muted) }
    }

    override fun closePeer() {
        dispatch { closePeerOnExecutor() }
    }

    override fun dispose() {
        dispatch {
            if (disposed) return@dispatch
            disposed = true
            closePeerOnExecutor()
            factory?.dispose()
            factory = null
            audioDeviceModule?.release()
            audioDeviceModule = null
        }
    }

    private fun createPeer(): PeerConnection? {
        if (disposed || peer != null) return peer
        peerCreationFailure = "peer_connection_unavailable"
        if (ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            peerCreationFailure = "microphone_permission_denied"
            return null
        }
        // Capture/playout is gated by a service-owned Telecom readiness lease.
        // WebRTC never requests focus or mutates Android audio routing.
        if (!audioCoordinator.acquireMediaLease()) {
            peerCreationFailure = "system_audio_not_ready"
            return null
        }
        val pcFactory = ensureFactory() ?: run {
            audioCoordinator.releaseMediaLease()
            peerCreationFailure = "peer_factory_unavailable"
            return null
        }
        val configuration = PeerConnection.RTCConfiguration(emptyList()).apply {
            bundlePolicy = PeerConnection.BundlePolicy.BALANCED
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }
        val generation = ++peerGeneration
        val connection = pcFactory.createPeerConnection(configuration, observer(generation)) ?: run {
            audioCoordinator.releaseMediaLease()
            peerCreationFailure = "peer_connection_unavailable"
            return null
        }
        peer = connection
        val source = pcFactory.createAudioSource(MediaConstraints())
        val track = pcFactory.createAudioTrack("at-audio", source)
        audioSource = source
        localTrack = track
        if (connection.addTrack(track, listOf("at-audio-stream")) == null) {
            peerCreationFailure = "audio_track_attach_failed"
            closePeerOnExecutor()
            return null
        }
        return connection
    }

    private fun ensureFactory(): PeerConnectionFactory? {
        factory?.let { return it }
        return try {
            if (factoryInitialized.compareAndSet(false, true)) {
                PeerConnectionFactory.initialize(
                    PeerConnectionFactory.InitializationOptions.builder(appContext)
                        .createInitializationOptions(),
                )
            }
            val adm = JavaAudioDeviceModule.builder(appContext)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setUseHardwareAcousticEchoCanceler(JavaAudioDeviceModule.isBuiltInAcousticEchoCancelerSupported())
                .setUseHardwareNoiseSuppressor(JavaAudioDeviceModule.isBuiltInNoiseSuppressorSupported())
                .setEnableVolumeLogger(false)
                .setAudioRecordStateCallback(object : JavaAudioDeviceModule.AudioRecordStateCallback {
                    override fun onWebRtcAudioRecordStart() { onDiagnostic?.invoke("audio_record", "started") }
                    override fun onWebRtcAudioRecordStop() { onDiagnostic?.invoke("audio_record", "stopped") }
                })
                .setAudioTrackStateCallback(object : JavaAudioDeviceModule.AudioTrackStateCallback {
                    override fun onWebRtcAudioTrackStart() { onDiagnostic?.invoke("audio_playout", "started") }
                    override fun onWebRtcAudioTrackStop() { onDiagnostic?.invoke("audio_playout", "stopped") }
                })
                .createAudioDeviceModule()
            audioDeviceModule = adm
            PeerConnectionFactory.builder()
                .setAudioDeviceModule(adm)
                .createPeerConnectionFactory()
                .also { factory = it }
        } catch (_: Throwable) {
            null
        }
    }

    private fun observer(generation: Long) = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState) = Unit
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
            executor.execute {
                if (!isCurrent(generation)) return@execute
                onIceState?.invoke(state.name.lowercase())
                when (state) {
                    PeerConnection.IceConnectionState.FAILED -> onFailure?.invoke("ice_failed")
                    else -> Unit
                }
            }
        }
        override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
            executor.execute {
                if (!isCurrent(generation)) return@execute
                onPeerState?.invoke(state.name.lowercase())
            }
        }
        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
            if (state == PeerConnection.IceGatheringState.COMPLETE) emitEndOfCandidates(generation)
        }
        override fun onIceCandidate(candidate: IceCandidate?) {
            if (candidate == null) {
                emitEndOfCandidates(generation)
            } else {
                executor.execute {
                    if (!isCurrent(generation)) return@execute
                    onLocalCandidate?.invoke(
                        mapOf(
                            "candidate" to candidate.sdp,
                            "sdpMid" to (candidate.sdpMid ?: "audio"),
                            "sdpMLineIndex" to candidate.sdpMLineIndex,
                        ),
                    )
                }
            }
        }
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
        override fun onAddStream(stream: org.webrtc.MediaStream) = Unit
        override fun onRemoveStream(stream: org.webrtc.MediaStream) = Unit
        override fun onDataChannel(channel: org.webrtc.DataChannel) = Unit
        override fun onRenegotiationNeeded() = Unit
        override fun onAddTrack(receiver: org.webrtc.RtpReceiver, streams: Array<out org.webrtc.MediaStream>) {
            (receiver.track() as? AudioTrack)?.setEnabled(true)
        }
    }

    private fun emitEndOfCandidates(generation: Long) {
        executor.execute {
            if (!isCurrent(generation) || endOfCandidatesSent) return@execute
            endOfCandidatesSent = true
            onLocalCandidate?.invoke(null)
        }
    }

    private fun closePeerOnExecutor() {
        peerGeneration++
        peer?.close()
        peer?.dispose()
        peer = null
        localTrack?.dispose()
        localTrack = null
        audioSource?.dispose()
        audioSource = null
        pendingRemoteCandidates.clear()
        hasRemoteDescription = false
        endOfCandidatesSent = false
        audioCoordinator.releaseMediaLease()
    }

    private fun isCurrent(generation: Long): Boolean = !disposed && peerGeneration == generation

    private fun dispatch(block: () -> Unit) {
        if (Thread.currentThread().name == SERVICE_EXECUTOR_NAME) block()
        else executor.execute(block)
    }

    private fun jsep(description: SessionDescription) = mapOf(
        "type" to description.type.canonicalForm(),
        "sdp" to description.description,
    )

    companion object {
        private const val SERVICE_EXECUTOR_NAME = "OmniDeskCallMedia"
        private val factoryInitialized = AtomicBoolean(false)
    }
}
