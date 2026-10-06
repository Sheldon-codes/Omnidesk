package com.bigbrainzsolutions.omnidesk

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class AndroidCallAudioCoordinatorTest {
    @Test fun focusBeforeWaiterAndDuplicateRequestsShareOneLease() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 34, log = {})
            audio.focusChanged("call-a", true)
            audio.foregroundStarted("call-a", true)
            audio.connectionState("call-a", eligible = true)
            val first = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            val second = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            val firstLatch = CountDownLatch(1)
            val secondLatch = CountDownLatch(1)
            audio.begin("call-a", true) { first.set(it); firstLatch.countDown() }
            audio.begin("call-a", true) { second.set(it); secondLatch.countDown() }
            assertTrue(firstLatch.await(1, TimeUnit.SECONDS))
            assertTrue(secondLatch.await(1, TimeUnit.SECONDS))
            assertEquals(first.get()!!.getOrThrow().systemCallId, second.get()!!.getOrThrow().systemCallId)
            assertEquals(first.get()!!.getOrThrow().generation, second.get()!!.getOrThrow().generation)
            assertTrue(audio.acquireMediaLease())
        } finally { executor.shutdownNow() }
    }

    @Test fun focusAfterWaiterGatesUntilAllTelecomPrerequisitesAreReady() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 34, log = {})
            val result = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            val latch = CountDownLatch(1)
            audio.begin("call-b", incoming = false) { result.set(it); latch.countDown() }
            audio.foregroundStarted("call-b", true)
            audio.connectionState("call-b", eligible = true)
            assertNull(result.get())
            audio.focusChanged("call-b", true)
            assertTrue(latch.await(1, TimeUnit.SECONDS))
            assertEquals("call-b", result.get()!!.getOrThrow().systemCallId)
        } finally { executor.shutdownNow() }
    }

    @Test fun outboundWaitSurvivesFocusAndForegroundBeforeLateConnection() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 36, log = {})
            val result = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            val latch = CountDownLatch(1)
            audio.begin("late-outbound", incoming = false) { result.set(it); latch.countDown() }
            audio.focusChanged("late-outbound", true)
            audio.foregroundStarted("late-outbound", true)
            assertNull(result.get())
            audio.connectionState("late-outbound", eligible = true)
            assertTrue(latch.await(1, TimeUnit.SECONDS))
            assertEquals("late-outbound", result.get()!!.getOrThrow().systemCallId)
        } finally { executor.shutdownNow() }
    }

    @Test fun legacyApiUsesEligibleConnectionAudioStateSignal() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 27, log = {})
            audio.foregroundStarted("legacy", true)
            audio.connectionState("legacy", eligible = true, audioStateObserved = true)
            val latch = CountDownLatch(1)
            audio.begin("legacy", incoming = true) { assertTrue(it.isSuccess); latch.countDown() }
            assertTrue(latch.await(1, TimeUnit.SECONDS))
        } finally { executor.shutdownNow() }
    }

    @Test fun legacyRingingAudioCallbackCannotSatisfyActiveReadiness() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 27, log = {})
            audio.foregroundStarted("legacy-race", true)
            audio.connectionState("legacy-race", eligible = false, audioStateObserved = true)
            audio.connectionState("legacy-race", eligible = true, audioStateObserved = false)
            val first = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            audio.begin("legacy-race", incoming = true) { first.set(it) }
            assertNull(first.get())
            val completed = CountDownLatch(1)
            audio.connectionState("legacy-race", eligible = true, audioStateObserved = true)
            // A duplicate waiter observes the same readiness generation.
            audio.begin("legacy-race", incoming = true) { assertTrue(it.isSuccess); completed.countDown() }
            assertTrue(completed.await(1, TimeUnit.SECONDS))
        } finally { executor.shutdownNow() }
    }

    @Test fun timeoutAndCallEndCompletePendingWaitersOnce() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 34, readinessTimeoutSeconds = 1, log = {})
            val count = java.util.concurrent.atomic.AtomicInteger()
            val terminal = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            val latch = CountDownLatch(1)
            audio.begin("call-c", true) { terminal.set(it); count.incrementAndGet(); latch.countDown() }
            audio.end("call-c")
            assertTrue(latch.await(1, TimeUnit.SECONDS))
            Thread.sleep(1100)
            assertEquals(1, count.get())
            assertFalse(terminal.get()!!.isSuccess)
        } finally { executor.shutdownNow() }
    }

    @Test fun timeoutIsTerminalAndLateFocusCannotGrantAStaleLease() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            val audio = AndroidCallAudioCoordinator(executor, { _, _, callback -> callback(Result.success(Unit)) }, sdkInt = 34, readinessTimeoutSeconds = 1, log = {})
            val first = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            val latch = CountDownLatch(1)
            audio.begin("timed-out", true) { first.set(it); latch.countDown() }
            assertTrue(latch.await(2, TimeUnit.SECONDS))
            assertEquals("system_audio_readiness_timeout", first.get()!!.exceptionOrNull()!!.message)
            audio.foregroundStarted("timed-out", true)
            audio.connectionState("timed-out", eligible = true)
            audio.focusChanged("timed-out", true)
            val retry = AtomicReference<Result<AndroidCallAudioCoordinator.Lease>?>()
            audio.begin("timed-out", true) { retry.set(it) }
            assertFalse(retry.get()!!.isSuccess)
        } finally { executor.shutdownNow() }
    }

    @Test fun lateRouteResultAfterCallEndIsRejected() {
        val executor = Executors.newSingleThreadScheduledExecutor()
        try {
            var routeCompletion: ((Result<Unit>) -> Unit)? = null
            val audio = AndroidCallAudioCoordinator(
                executor,
                { _, _, callback -> routeCompletion = callback },
                sdkInt = 34,
                log = {},
            )
            audio.foregroundStarted("route-call", true)
            audio.connectionState("route-call", eligible = true)
            audio.focusChanged("route-call", true)
            audio.begin("route-call", true) { assertTrue(it.isSuccess) }
            val result = AtomicReference<Result<Unit>?>()
            audio.requestSpeaker(true) { result.set(it) }
            audio.end("route-call")
            routeCompletion!!(Result.success(Unit))
            assertFalse(result.get()!!.isSuccess)
            assertEquals("system_audio_session_replaced", result.get()!!.exceptionOrNull()!!.message)
        } finally { executor.shutdownNow() }
    }
}
