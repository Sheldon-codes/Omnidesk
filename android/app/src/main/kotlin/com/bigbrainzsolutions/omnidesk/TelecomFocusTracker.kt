package com.bigbrainzsolutions.omnidesk

/** Attributes service-wide Telecom focus to the one call that can use it. */
internal class TelecomFocusTracker {
    enum class State { ACTIVE, DIALING, RINGING }
    data class Candidate(val callId: String, val state: State)
    data class Change(val callId: String, val gained: Boolean)

    private var focusHeld = false
    private var ownerCallId: String? = null

    @Synchronized fun focusChanged(gained: Boolean, candidates: List<Candidate>): Change? {
        if (!gained) {
            focusHeld = false
            val previous = ownerCallId
            ownerCallId = null
            return previous?.let { Change(it, false) }
        }
        focusHeld = true
        if (ownerCallId != null && candidates.any { it.callId == ownerCallId }) return null
        ownerCallId = null
        return assign(candidates)
    }

    /** Focus can arrive before Telecom creates or activates the Connection. */
    @Synchronized fun connectionAvailable(candidates: List<Candidate>): Change? =
        if (focusHeld && ownerCallId == null) assign(candidates) else null

    @Synchronized fun connectionRemoved(callId: String, noConnectionsRemain: Boolean) {
        if (ownerCallId == callId || noConnectionsRemain) {
            ownerCallId = null
            // A late focus-loss callback belongs to this removed call; never
            // carry its earlier focus into a replacement Connection.
            focusHeld = false
        }
    }

    @Synchronized fun hasUnassignedFocus(): Boolean = focusHeld && ownerCallId == null

    private fun assign(candidates: List<Candidate>): Change? {
        val selected = listOf(State.ACTIVE, State.DIALING, State.RINGING)
            .firstNotNullOfOrNull { state ->
                candidates.filter { it.state == state }.takeIf { it.isNotEmpty() }
            }?.singleOrNull() ?: return null
        ownerCallId = selected.callId
        return Change(selected.callId, true)
    }
}
