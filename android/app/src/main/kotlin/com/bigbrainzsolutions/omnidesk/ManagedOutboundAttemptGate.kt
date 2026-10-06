package com.bigbrainzsolutions.omnidesk

/** Pure, synchronized state for late backend responses and exactly-once completion. */
internal class ManagedOutboundAttemptGate {
    data class Completion(val callId: String, val callSid: String, val connectedAtElapsedMs: Long?)

    private var terminal = false
    private var backendCallId: String? = null
    private var providerCallSid: String? = null
    private var connectedAt: Long? = null
    private var completionClaimed = false

    @Synchronized fun isOpen(): Boolean = !terminal
    @Synchronized fun callId(): String? = backendCallId
    @Synchronized fun callSid(): String? = providerCallSid
    @Synchronized fun connectedAt(): Long? = connectedAt

    /** Always records the backend identity; a cancelled caller must still end its late row. */
    @Synchronized fun backendCreated(callId: String, callSid: String): Boolean {
        backendCallId = callId
        providerCallSid = callSid
        return !terminal
    }

    @Synchronized fun markConnected(elapsedMs: Long): Boolean {
        if (terminal || connectedAt != null) return false
        connectedAt = elapsedMs
        return true
    }

    @Synchronized fun close(): Boolean {
        if (terminal) return false
        terminal = true
        return true
    }

    @Synchronized fun claimCompletion(): Completion? {
        if (!terminal || completionClaimed || backendCallId == null || providerCallSid == null) return null
        completionClaimed = true
        return Completion(backendCallId!!, providerCallSid!!, connectedAt)
    }
}
