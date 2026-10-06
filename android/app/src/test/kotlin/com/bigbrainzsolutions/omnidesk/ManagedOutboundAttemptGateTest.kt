package com.bigbrainzsolutions.omnidesk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ManagedOutboundAttemptGateTest {
    @Test fun lateBackendResponseAfterHangupStillProducesExactlyOneCleanup() {
        val gate = ManagedOutboundAttemptGate()
        assertTrue(gate.close())
        assertFalse(gate.close())
        assertFalse(gate.backendCreated("backend_1", "sid_1"))
        val cleanup = gate.claimCompletion()
        assertEquals("backend_1", cleanup?.callId)
        assertEquals("sid_1", cleanup?.callSid)
        assertNull(cleanup?.connectedAtElapsedMs)
        assertNull(gate.claimCompletion())
        assertFalse(gate.markConnected(1000))
    }

    @Test fun connectedCallCompletesOnceWithItsOwnProviderSidAndTime() {
        val gate = ManagedOutboundAttemptGate()
        assertTrue(gate.backendCreated("backend_2", "sid_2"))
        assertTrue(gate.markConnected(2000))
        assertFalse(gate.markConnected(3000))
        assertNull(gate.claimCompletion())
        assertTrue(gate.close())
        assertEquals(ManagedOutboundAttemptGate.Completion("backend_2", "sid_2", 2000), gate.claimCompletion())
        assertNull(gate.claimCompletion())
    }

    @Test fun failedInitiationHasNoBackendRowToFinalize() {
        val gate = ManagedOutboundAttemptGate()
        assertTrue(gate.close())
        assertNull(gate.claimCompletion())
    }
}
