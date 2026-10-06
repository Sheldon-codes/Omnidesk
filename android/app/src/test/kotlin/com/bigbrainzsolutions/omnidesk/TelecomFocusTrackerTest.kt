package com.bigbrainzsolutions.omnidesk

import org.junit.Assert.*
import org.junit.Test

class TelecomFocusTrackerTest {
    private val ringing = TelecomFocusTracker.Candidate("incoming", TelecomFocusTracker.State.RINGING)
    private val active = TelecomFocusTracker.Candidate("incoming", TelecomFocusTracker.State.ACTIVE)

    @Test fun focusDuringRingingIsHeldThroughAnswerAndReleasedForSameCall() {
        val tracker = TelecomFocusTracker()
        assertEquals(TelecomFocusTracker.Change("incoming", true), tracker.focusChanged(true, listOf(ringing)))
        assertNull(tracker.connectionAvailable(listOf(active)))
        assertEquals(TelecomFocusTracker.Change("incoming", false), tracker.focusChanged(false, listOf(active)))
    }

    @Test fun focusBeforeConnectionCreationIsAssignedWhenConnectionArrives() {
        val tracker = TelecomFocusTracker()
        assertNull(tracker.focusChanged(true, emptyList()))
        assertTrue(tracker.hasUnassignedFocus())
        assertEquals(TelecomFocusTracker.Change("incoming", true), tracker.connectionAvailable(listOf(ringing)))
        assertFalse(tracker.hasUnassignedFocus())
    }

    @Test fun ambiguousRingingCallsCannotClaimServiceFocus() {
        val tracker = TelecomFocusTracker()
        val other = TelecomFocusTracker.Candidate("other", TelecomFocusTracker.State.RINGING)
        assertNull(tracker.focusChanged(true, listOf(ringing, other)))
        assertNull(tracker.connectionAvailable(listOf(ringing, other)))
        assertEquals(TelecomFocusTracker.Change("incoming", true), tracker.connectionAvailable(listOf(ringing)))
    }

    @Test fun removedCallCannotPassItsFocusToReplacement() {
        val tracker = TelecomFocusTracker()
        tracker.focusChanged(true, listOf(ringing))
        tracker.connectionRemoved("incoming", noConnectionsRemain = true)
        val replacement = TelecomFocusTracker.Candidate("replacement", TelecomFocusTracker.State.RINGING)
        assertNull(tracker.connectionAvailable(listOf(replacement)))
        assertNull(tracker.focusChanged(false, listOf(replacement)))
        assertEquals(TelecomFocusTracker.Change("replacement", true), tracker.focusChanged(true, listOf(replacement)))
    }

    @Test fun ambiguousActiveCallsDoNotAssignFocusToRingingCall() {
        val tracker = TelecomFocusTracker()
        val activeOther = TelecomFocusTracker.Candidate("other", TelecomFocusTracker.State.ACTIVE)
        assertNull(tracker.focusChanged(true, listOf(active, activeOther, ringing)))
        assertTrue(tracker.hasUnassignedFocus())
    }
}
