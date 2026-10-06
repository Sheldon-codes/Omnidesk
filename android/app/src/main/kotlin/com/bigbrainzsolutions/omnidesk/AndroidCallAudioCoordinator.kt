package com.bigbrainzsolutions.omnidesk

import android.os.Build
import android.util.Log
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Service-owned readiness/lease state. Telecom owns focus and AudioManager policy for calls. */
internal class AndroidCallAudioCoordinator(
    private val executor: ScheduledExecutorService,
    private val routeRequest: (String, Boolean, (Result<Unit>) -> Unit) -> Unit,
    private val sdkInt: Int = Build.VERSION.SDK_INT,
    private val readinessTimeoutSeconds: Long = 8,
    private val log: (String) -> Unit = { Log.i(TAG, it) },
) {
    enum class OwnershipMode { Telecom }
    enum class ReadinessState { Waiting, Ready, Failed }
    class Lease internal constructor(val systemCallId: String, val generation: Long)
    private data class Session(
        val callId: String, val generation: Long, val incoming: Boolean,
        val ownershipMode: OwnershipMode = OwnershipMode.Telecom,
        var readinessState: ReadinessState = ReadinessState.Waiting,
        var terminalFailure: String? = null,
        var connectionEligible: Boolean = false, var foregroundReady: Boolean = false,
        var focusGained: Boolean = false, var legacyAudioStateSeen: Boolean = false,
        var mediaLease: Boolean = false, var timeout: ScheduledFuture<*>? = null,
        val waiters: MutableList<(Result<Lease>) -> Unit> = mutableListOf(),
    )
    private var generation = 0L
    private var session: Session? = null
    private val foregroundResults = mutableMapOf<String, Boolean>()
    private val connectionResults = mutableMapOf<String, Pair<Boolean, Boolean>>()
    private val focusResults = mutableMapOf<String, Boolean>()

    @Synchronized fun begin(callId: String, incoming: Boolean, callback: (Result<Lease>) -> Unit) {
        require(callId.isNotBlank())
        var current = session
        if (current != null && current.callId != callId) {
            callback(Result.failure(IllegalStateException("Another system call owns audio readiness.")))
            return
        }
        if (current == null) {
            current = Session(callId, ++generation, incoming).also {
                it.foregroundReady = foregroundResults.remove(callId) == true
                val connection = connectionResults.remove(callId)
                it.connectionEligible = connection?.first == true
                it.legacyAudioStateSeen = connection?.second == true
                it.focusGained = focusResults.remove(callId) == true
                if (sdkInt < 28 && it.connectionEligible && it.legacyAudioStateSeen) it.focusGained = true
            }
            session = current
        }
        if (current.readinessState == ReadinessState.Failed) {
            callback(Result.failure(IllegalStateException(current.terminalFailure ?: "system_audio_not_ready")))
            return
        }
        current.waiters += callback
        if (ready(current)) grant(current)
        else if (current.timeout == null) {
            val expected = current
            current.timeout = executor.schedule({ synchronized(this) {
                if (session === expected && !ready(expected)) {
                    complete(expected, Result.failure(IllegalStateException("system_audio_readiness_timeout")))
                    log("Telecom audio readiness timeout callId=${expected.callId} generation=${expected.generation} ${conditions(expected)}")
                }
            } }, readinessTimeoutSeconds, TimeUnit.SECONDS)
            log("Telecom audio readiness wait callId=$callId generation=${current.generation} ${conditions(current)}")
        }
    }

    @Synchronized fun foregroundStarted(callId: String, success: Boolean) {
        val s = session?.takeIf { it.callId == callId } ?: run {
            foregroundResults[callId] = success
            log("Call FGS readiness cached callId=$callId ready=$success")
            return
        }
        s.foregroundReady = success
        log("Call FGS readiness callId=$callId ready=$success generation=${s.generation}")
        if (!success) complete(s, Result.failure(IllegalStateException("call_foreground_service_failed"))) else tryGrant(s)
    }

    @Synchronized fun connectionState(callId: String, eligible: Boolean, audioStateObserved: Boolean = false) {
        val s = session?.takeIf { it.callId == callId } ?: run {
            connectionResults[callId] = eligible to (eligible && audioStateObserved)
            log("Telecom state cached callId=$callId eligible=$eligible audioState=$audioStateObserved")
            return
        }
        s.connectionEligible = eligible
        s.legacyAudioStateSeen = if (!eligible) false else s.legacyAudioStateSeen || audioStateObserved
        if (sdkInt < 28 && eligible && s.legacyAudioStateSeen) s.focusGained = true
        log("Telecom state callId=$callId eligible=$eligible ownership=${s.ownershipMode} generation=${s.generation}")
        tryGrant(s)
    }

    @Synchronized fun focusChanged(callId: String, gained: Boolean) {
        val s = session?.takeIf { it.callId == callId } ?: run {
            focusResults[callId] = gained
            log("Telecom focus cached callId=$callId gained=$gained")
            return
        }
        s.focusGained = gained
        log("Telecom focus ${if (gained) "gained" else "lost"} callId=${s.callId} generation=${s.generation}")
        if (gained) tryGrant(s)
        else if (s.waiters.isNotEmpty()) {
            complete(s, Result.failure(IllegalStateException("system_audio_focus_lost")))
        }
    }

    @Synchronized fun acquireMediaLease(): Boolean {
        val s = session ?: return false
        if (!ready(s)) return false
        s.mediaLease = true
        return true
    }

    @Synchronized fun releaseMediaLease() { session?.mediaLease = false }

    fun requestSpeaker(enabled: Boolean, callback: (Result<Unit>) -> Unit) {
        val current = synchronized(this) { session?.takeIf { ready(it) } }
            ?: run { callback(Result.failure(IllegalStateException("system_audio_not_ready"))); return }
        val callId = current.callId
        log("Telecom route request callId=$callId route=${if (enabled) "speaker" else "receiver"}")
        routeRequest(callId, enabled) { result ->
            val stillCurrent = synchronized(this) { session === current && ready(current) }
            log("Telecom route result callId=$callId success=${result.isSuccess && stillCurrent}")
            callback(if (stillCurrent) result else Result.failure(IllegalStateException("system_audio_session_replaced")))
        }
    }

    @Synchronized fun end(callId: String) {
        foregroundResults.remove(callId)
        connectionResults.remove(callId)
        focusResults.remove(callId)
        val s = session?.takeIf { it.callId == callId } ?: return
        complete(s, Result.failure(IllegalStateException("system_call_ended")))
        s.timeout?.cancel(false)
        session = null
        log("Telecom audio lease released callId=$callId generation=${s.generation}")
    }

    @Synchronized fun release() {
        session?.let { end(it.callId) }
        foregroundResults.clear()
        connectionResults.clear()
        focusResults.clear()
    }

    private fun ready(s: Session) = s.readinessState != ReadinessState.Failed &&
        s.connectionEligible && s.foregroundReady && s.focusGained
    private fun conditions(s: Session) =
        "connection=${s.connectionEligible} foreground=${s.foregroundReady} focus=${s.focusGained} audioState=${s.legacyAudioStateSeen}"
    private fun tryGrant(s: Session) { if (ready(s)) grant(s) }
    private fun grant(s: Session) {
        s.readinessState = ReadinessState.Ready
        log("Telecom audio readiness granted callId=${s.callId} generation=${s.generation}")
        complete(s, Result.success(Lease(s.callId, s.generation)))
    }
    private fun complete(s: Session, result: Result<Lease>) {
        if (result.isFailure) {
            s.readinessState = ReadinessState.Failed
            s.terminalFailure = result.exceptionOrNull()?.message ?: "system_audio_not_ready"
        } else {
            s.readinessState = ReadinessState.Ready
        }
        s.timeout?.cancel(false); s.timeout = null
        val callbacks = s.waiters.toList(); s.waiters.clear()
        callbacks.forEach { it(result) }
    }
    companion object { private const val TAG = "OmniDeskCallAudio" }
}
