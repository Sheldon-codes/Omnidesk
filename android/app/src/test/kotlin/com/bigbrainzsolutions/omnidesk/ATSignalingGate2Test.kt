package com.bigbrainzsolutions.omnidesk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ATSignalingGate2Test {
    @Test fun commandsMatchAtWireContract() {
        assertEquals("create", JSONObject(ATSignalingModels.createCommand()).getString("command"))
        val register = JSONObject(ATSignalingModels.registerCommand())
        assertEquals("message", register.getString("command"))
        assertEquals("register", register.getJSONObject("body").getString("request"))
        assertEquals("keepalive", JSONObject(ATSignalingModels.keepaliveCommand()).getString("command"))
        assertEquals("destroy", JSONObject(ATSignalingModels.destroyCommand()).getString("command"))
        val call = JSONObject(ATSignalingModels.callCommand(
            "+254700000001", mapOf("type" to "offer", "sdp" to "v=0\r\na=sendrecv\r\n"),
        ))
        assertEquals("message", call.getString("command"))
        assertEquals("call", call.getJSONObject("body").getString("request"))
        assertEquals("+254700000001", call.getJSONObject("body").getString("to"))
        assertEquals("v=0\r\na=sendrecv\r\n", call.getJSONObject("jsep").getString("sdp"))
        val trickle = JSONObject(ATSignalingModels.trickleCommand(
            mapOf("candidate" to "candidate:1", "sdpMid" to "audio", "sdpMLineIndex" to 0),
        )).getJSONObject("candidate")
        assertEquals("candidate:1", trickle.getString("candidate"))
        assertEquals(true, JSONObject(ATSignalingModels.trickleCommand(null))
            .getJSONObject("candidate").getBoolean("completed"))
    }

    @Test fun decodesCreateAndRegistrationResponsesAndIgnoresUnknown() {
        assertEquals(ATSignalingModels.Incoming.CreateSucceeded, ATSignalingModels.decode("""{"response":"success","data":{"id":1}}"""))
        assertEquals(ATSignalingModels.Incoming.Registered, ATSignalingModels.decode("""{"response":"event","eventdata":{"result":{"event":"registered"}}}"""))
        assertTrue(ATSignalingModels.decode("not json") is ATSignalingModels.Incoming.Unknown)
        assertTrue(ATSignalingModels.decode("""{"response":"event","eventdata":{"result":{"event":"x"}}}""") is ATSignalingModels.Incoming.Event)
        val accepted = ATSignalingModels.decode("""{"response":"event","eventdata":{"result":{"event":"accepted"}},"jsep":{"type":"answer","sdp":"raw-sdp"}}""")
        assertTrue(accepted is ATSignalingModels.Incoming.Event && accepted.jsep?.get("sdp") == "raw-sdp")
        val trickle = ATSignalingModels.decode("""{"response":"trickle","candidate":{"candidate":"candidate:2","sdpMid":"audio","sdpMLineIndex":0}}""")
        assertTrue(trickle is ATSignalingModels.Incoming.Trickle && trickle.candidate?.get("sdpMid") == "audio")
    }

    @Test fun advancesCreateThenRegisterAndEmitsRegistered() {
        val fixture = Fixture()
        try {
            val result = fixture.initializeResult()
            fixture.awaitState(ATNativeMediaCoordinator.State.connecting)
            fixture.awaitTransport()
            fixture.transport.listener.onSocketOpened("at-protocol")
            fixture.awaitState(ATNativeMediaCoordinator.State.creating)
            assertEquals("create", JSONObject(fixture.transport.frames.last()).getString("command"))
            fixture.transport.listener.onText("""{"response":"success","data":{"id":11}}""")
            fixture.awaitState(ATNativeMediaCoordinator.State.registering)
            val register = JSONObject(fixture.transport.frames.last())
            assertEquals("message", register.getString("command"))
            assertEquals("register", register.getJSONObject("body").getString("request"))
            fixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"registered"}}}""")
            fixture.awaitState(ATNativeMediaCoordinator.State.registered)
            assertEquals(fixture.coordinator.currentSnapshot().sessionId, result.get(2, TimeUnit.SECONDS).getOrNull())
            assertTrue(fixture.events.any { it["phase"] == "at" && it["result"] == "registered" })
        } finally { fixture.close() }
    }

    @Test fun timeoutFailsWithSanitizedError() {
        val fixture = Fixture(timeoutScale = 0.001)
        try {
            val result = fixture.initializeResult()
            fixture.awaitState(ATNativeMediaCoordinator.State.failed)
            assertTrue(result.get()!!.exceptionOrNull()!!.message!!.contains("timeout"))
            assertFalse(result.get()!!.exceptionOrNull()!!.message!!.contains(TOKEN))
        } finally { fixture.close() }
    }

    @Test fun registerTimeoutAndGatewayRejectionFailSanitized() {
        val timeoutFixture = Fixture(timeoutScale = 0.001)
        try {
            val result = timeoutFixture.initializeResult()
            timeoutFixture.awaitState(ATNativeMediaCoordinator.State.connecting)
            timeoutFixture.awaitTransport()
            timeoutFixture.transport.listener.onSocketOpened("at-protocol")
            timeoutFixture.awaitState(ATNativeMediaCoordinator.State.creating)
            timeoutFixture.transport.listener.onText("""{"response":"success"}""")
            timeoutFixture.awaitState(ATNativeMediaCoordinator.State.registering)
            timeoutFixture.awaitState(ATNativeMediaCoordinator.State.failed)
            assertTrue(result.get(2, TimeUnit.SECONDS)!!.exceptionOrNull()!!.message!!.contains("timeout"))
            assertFalse(timeoutFixture.events.toString().contains(TOKEN))
        } finally { timeoutFixture.close() }

        val rejectedFixture = Fixture()
        try {
            val result = rejectedFixture.initializeResult()
            rejectedFixture.awaitState(ATNativeMediaCoordinator.State.connecting)
            rejectedFixture.awaitTransport()
            rejectedFixture.transport.listener.onSocketOpened("at-protocol")
            rejectedFixture.awaitState(ATNativeMediaCoordinator.State.creating)
            rejectedFixture.transport.listener.onText("""{"response":"success"}""")
            rejectedFixture.awaitState(ATNativeMediaCoordinator.State.registering)
            rejectedFixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"registration_failed","reason":"bad token"}}}""")
            rejectedFixture.awaitState(ATNativeMediaCoordinator.State.failed)
            assertTrue(result.get(2, TimeUnit.SECONDS)!!.isFailure)
            assertFalse(rejectedFixture.events.toString().contains(TOKEN))
        } finally { rejectedFixture.close() }
    }

    @Test fun staleGenerationCallbacksCannotAdvanceReplacement() {
        val fixture = Fixture()
        try {
            fixture.initialize()
            val stale = fixture.transport.listener
            fixture.dispose().get(2, TimeUnit.SECONDS)
            fixture.initialize()
            stale.onSocketOpened("at-protocol")
            Thread.sleep(30)
            assertEquals(ATNativeMediaCoordinator.State.connecting, fixture.coordinator.currentSnapshot().state)
            assertTrue(fixture.transport.frames.isEmpty())
        } finally { fixture.close() }
    }

    @Test fun duplicateInitializeSharesOneTransportAndCompletion() {
        val fixture = Fixture()
        try {
            fixture.initializeResult()
            fixture.initializeResult()
            fixture.awaitState(ATNativeMediaCoordinator.State.connecting)
            fixture.awaitTransport()
            assertEquals(1, fixture.createdTransports)
            fixture.transport.listener.onSocketOpened("at-protocol")
            fixture.awaitState(ATNativeMediaCoordinator.State.creating)
            fixture.transport.listener.onText("""{"response":"success"}""")
            fixture.awaitState(ATNativeMediaCoordinator.State.registering)
            fixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"registered"}}}""")
            fixture.awaitState(ATNativeMediaCoordinator.State.registered)
            assertEquals(2, fixture.results.size)
            assertTrue(fixture.results.all { it.get()!!.isSuccess })
        } finally { fixture.close() }
    }

    @Test fun disposeIsIdempotentAndStaleCallbacksDoNotResurrect() {
        val fixture = Fixture()
        try {
            fixture.initialize()
            val old = fixture.transport
            fixture.dispose().get(2, TimeUnit.SECONDS)
            fixture.dispose().get(2, TimeUnit.SECONDS)
            old.listener.onSocketOpened("at-protocol")
            Thread.sleep(30)
            assertEquals(ATNativeMediaCoordinator.State.disposed, fixture.coordinator.currentSnapshot().state)
            assertEquals(1, old.disposeCount)
        } finally { fixture.close() }
    }

    @Test fun tokenNeverAppearsInDiagnosticsOrFailures() {
        val fixture = Fixture()
        try {
            val result = fixture.initializeResult()
            fixture.awaitState(ATNativeMediaCoordinator.State.connecting)
            fixture.awaitTransport()
            fixture.transport.listener.onFailure()
            fixture.awaitState(ATNativeMediaCoordinator.State.failed)
            val rendered = fixture.logs.toString() + fixture.events.toString() + result.get().toString()
            assertFalse(rendered.contains(TOKEN))
        } finally { fixture.close() }
    }

    @Test fun outboundOfferUsesAtMessageAndWaitsForBothProviderAndPeerConnection() {
        val fixture = Fixture()
        try {
            fixture.register()
            val result = java.util.concurrent.CompletableFuture<Result<String>>()
            fixture.coordinator.dial("call-sid", "+254700000001") { result.complete(it) }
            assertEquals(fixture.coordinator.currentSnapshot().sessionId, result.get(2, TimeUnit.SECONDS).getOrNull())
            val frames = fixture.transport.frames.map(::JSONObject)
            val call = frames.first { it.optJSONObject("body")?.optString("request") == "call" }
            assertEquals("+254700000001", call.getJSONObject("body").getString("to"))
            assertEquals("v=0\\r\\na=offer\\r\\n", call.getJSONObject("jsep").getString("sdp"))
            assertTrue(frames.any { it.optString("command") == "trickle" && it.getJSONObject("candidate").optString("candidate") == "candidate:1" })
            assertTrue(frames.any { it.optString("command") == "trickle" && it.getJSONObject("candidate").optBoolean("completed") })

            fixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"accepted"}}}""")
            Thread.sleep(20)
            assertFalse(fixture.events.any { it["event"] == "connected" })
            fixture.peer.emitState("connected")
            fixture.peer.emitIce("connected")
            val connectedDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (!fixture.events.any { it["event"] == "connected" } && System.nanoTime() < connectedDeadline) {
                Thread.sleep(5)
            }
            assertTrue(fixture.events.any { it["event"] == "connected" })
            fixture.peer.emitState("connected")
            Thread.sleep(20)
            assertEquals(1, fixture.events.count { it["event"] == "connected" })
        } finally { fixture.close() }
    }

    @Test fun inboundOfferIsCorrelatedAndOnlyExplicitAnswerSendsUnmodifiedAccept() {
        val fixture = Fixture()
        try {
            fixture.register(incomingCallId = "backend-call-1")
            fixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"incomingcall"}},"jsep":{"type":"offer","sdp":"v=0\\r\\na=offer-original\\r\\n"}}""")
            fixture.awaitEvent("incoming")
            val incoming = fixture.events.first { it["event"] == "incoming" }
            assertEquals("backend-call-1", incoming["callSid"])
            assertFalse(fixture.transport.frames.map(::JSONObject).any { it.optJSONObject("body")?.optString("request") == "accept" })
            val answer = java.util.concurrent.CompletableFuture<Result<Unit>>()
            fixture.coordinator.answerIncoming("wrong-call") { answer.complete(it) }
            assertTrue(answer.get(2, TimeUnit.SECONDS).isFailure)
            val accepted = java.util.concurrent.CompletableFuture<Result<Unit>>()
            fixture.coordinator.answerIncoming("backend-call-1") { accepted.complete(it) }
            assertTrue(accepted.get(2, TimeUnit.SECONDS).isSuccess)
            val frames = fixture.transport.frames.map(::JSONObject)
            val accept = frames.first { it.optJSONObject("body")?.optString("request") == "accept" }
            assertEquals("v=0\\r\\na=answer-original\\r\\n", accept.getJSONObject("jsep").getString("sdp"))
            assertEquals("answer", accept.getJSONObject("jsep").getString("type"))
            assertEquals(listOf("v=0\\r\\na=offer-original\\r\\n"), fixture.peer.remoteOffers)
            fixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"accepted"}}}""")
            fixture.peer.emitState("connected")
            Thread.sleep(20)
            assertFalse(fixture.events.any { it["event"] == "connected" })
            fixture.peer.emitIce("completed")
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (!fixture.events.any { it["event"] == "connected" } && System.nanoTime() < deadline) Thread.sleep(5)
            assertTrue(fixture.events.any { it["event"] == "connected" })
        } finally { fixture.close() }
    }

    @Test fun inboundPeerSetupFailureSurfacesSanitizedRootCauseInsteadOfGenericCancellation() {
        val fixture = Fixture()
        try {
            fixture.register(incomingCallId = "backend-call-audio-failure")
            fixture.peer.answerFailureCode = "audio_focus_denied"
            fixture.transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"incomingcall"}},"jsep":{"type":"offer","sdp":"private-sdp-must-not-be-logged"}}""")
            fixture.awaitEvent("incoming")
            val answer = java.util.concurrent.CompletableFuture<Result<Unit>>()
            fixture.coordinator.answerIncoming("backend-call-audio-failure") { answer.complete(it) }
            val outcome = answer.get(2, TimeUnit.SECONDS)
            assertTrue(outcome.isFailure)
            assertEquals(
                "Android denied audio focus while preparing the call. Please try again.",
                outcome.exceptionOrNull()?.message,
            )
            assertTrue(fixture.logs.any { it.contains("phase=answer_setup result=failed_audio_focus_denied") })
            assertFalse(fixture.logs.toString().contains("private-sdp-must-not-be-logged"))
            assertFalse(fixture.events.toString().contains("private-sdp-must-not-be-logged"))
            assertFalse(fixture.events.toString().contains("Inbound call ended before media answer completed."))
            assertFalse(fixture.transport.frames.map(::JSONObject).any {
                it.optJSONObject("body")?.optString("request") == "accept"
            })
        } finally { fixture.close() }
    }

    @Test fun flutterEngineDetachAndReattachPreservesServiceRegistration() {
        val runtime = FakeRuntimeBridge()
        val plugin = AndroidNativeCallMediaPlugin(runtime, { action -> action() })
        runtime.registered = true
        plugin.attachRuntime(null)
        plugin.detachRuntime()
        assertTrue(runtime.registered)
        assertEquals(0, runtime.disposeCalls)
        plugin.attachRuntime(null)
        assertTrue(runtime.registered)
        assertEquals(2, runtime.attachCalls)
        assertEquals(1, runtime.detachCalls)
        assertEquals(6L, (plugin.latestSnapshotForTests()["sequence"] as Number).toLong())
    }

    @Test fun pluginForwardsSystemAudioPreparationToServiceRuntime() {
        val runtime = FakeRuntimeBridge()
        val plugin = AndroidNativeCallMediaPlugin(runtime, { action -> action() })
        var succeeded = false
        var errorCode: String? = null
        plugin.onMethodCall(
            io.flutter.plugin.common.MethodCall(
                "prepareSystemAudio",
                mapOf("systemCallId" to "call-42", "incoming" to true),
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) { succeeded = true }
                override fun error(code: String, message: String?, details: Any?) { errorCode = code }
                override fun notImplemented() { errorCode = "not_implemented" }
            },
        )
        assertEquals("call-42:true", runtime.systemAudioPreparation)
        assertTrue(succeeded)
        assertNull(errorCode)
    }

    private class Fixture(timeoutScale: Double = 1.0) {
        private val executor = Executors.newSingleThreadScheduledExecutor()
        val events = CopyOnWriteArrayList<Map<String, Any?>>()
        val logs = CopyOnWriteArrayList<String>()
        val results = CopyOnWriteArrayList<java.util.concurrent.CompletableFuture<Result<String>>>()
        lateinit var transport: FakeTransport
        var createdTransports = 0
        val peer = FakePeer()
        val coordinator = ATNativeMediaCoordinator(executor, events::add, { listener ->
            createdTransports++
            FakeTransport(listener).also { transport = it }
        }, timeoutScale, { logs += it }, peer)

        fun register(incomingCallId: String? = null) {
            val result = initializeResult(incomingCallId)
            awaitState(ATNativeMediaCoordinator.State.connecting)
            awaitTransport()
            transport.listener.onSocketOpened("at-protocol")
            awaitState(ATNativeMediaCoordinator.State.creating)
            transport.listener.onText("""{"response":"success"}""")
            awaitState(ATNativeMediaCoordinator.State.registering)
            transport.listener.onText("""{"response":"event","eventdata":{"result":{"event":"registered"}}}""")
            awaitState(ATNativeMediaCoordinator.State.registered)
            assertTrue(result.get(2, TimeUnit.SECONDS).isSuccess)
        }

        fun dispose(): java.util.concurrent.CompletableFuture<Unit> {
            val f = java.util.concurrent.CompletableFuture<Unit>()
            coordinator.dispose { f.complete(Unit) }
            return f
        }
        fun initialize() {
            initializeResult()
            awaitState(ATNativeMediaCoordinator.State.connecting)
            awaitTransport()
        }
        fun initializeResult(incomingCallId: String? = null): java.util.concurrent.CompletableFuture<Result<String>> {
            val f = java.util.concurrent.CompletableFuture<Result<String>>()
            results += f
            coordinator.initialize("wss://gateway.example/connect", TOKEN, incomingCallId) { f.complete(it) }
            return f
        }
        fun awaitState(state: ATNativeMediaCoordinator.State) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (System.nanoTime() < deadline) {
                if (coordinator.currentSnapshot().state == state) return
                Thread.sleep(5)
            }
            fail("Expected $state, got ${coordinator.currentSnapshot().state}")
        }
        fun awaitTransport() {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (System.nanoTime() < deadline) {
                if (::transport.isInitialized) return
                Thread.sleep(5)
            }
            fail("Signaling transport was not created")
        }
        fun awaitEvent(type: String) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (System.nanoTime() < deadline) {
                if (events.any { it["event"] == type }) return
                Thread.sleep(5)
            }
            fail("Expected event $type, got $events")
        }
        fun close() { dispose().get(2, TimeUnit.SECONDS); executor.shutdownNow() }
    }

    private class FakeTransport(val listener: ATSignalingClient.Listener) : ATSignalingTransport {
        val frames = CopyOnWriteArrayList<String>()
        var disposeCount = 0
        override fun connect(gateway: String, capabilityToken: String) = Unit
        override fun send(text: String): Boolean { frames += text; return true }
        override fun dispose() { disposeCount++ }
    }

    private class FakePeer : ATPeerConnection {
        override var onLocalCandidate: ((Map<String, Any?>?) -> Unit)? = null
        override var onPeerState: ((String) -> Unit)? = null
        override var onIceState: ((String) -> Unit)? = null
        override var onDiagnostic: ((String, String) -> Unit)? = null
        override var onFailure: ((String) -> Unit)? = null
        val remoteOffers = CopyOnWriteArrayList<String>()
        var answerFailureCode: String? = null
        override fun createOffer(callback: (Result<Map<String, Any?>>) -> Unit) {
            onLocalCandidate?.invoke(mapOf("candidate" to "candidate:1", "sdpMid" to "audio", "sdpMLineIndex" to 0))
            onLocalCandidate?.invoke(null)
            callback(Result.success(mapOf("type" to "offer", "sdp" to "v=0\\r\\na=offer\\r\\n")))
        }
        override fun createAnswer(remoteOffer: Map<String, Any?>, callback: (Result<Map<String, Any?>>) -> Unit) {
            remoteOffers += remoteOffer["sdp"].toString()
            answerFailureCode?.let {
                callback(Result.failure(IllegalStateException(it)))
                return
            }
            onLocalCandidate?.invoke(mapOf("candidate" to "local-inbound", "sdpMid" to "audio", "sdpMLineIndex" to 0))
            callback(Result.success(mapOf("type" to "answer", "sdp" to "v=0\\r\\na=answer-original\\r\\n")))
        }
        override fun applyRemoteDescription(jsep: Map<String, Any?>, callback: (Result<Unit>) -> Unit) {
            if (jsep["type"] == "offer") remoteOffers += jsep["sdp"].toString()
            callback(Result.success(Unit))
        }
        override fun addRemoteCandidate(value: Map<String, Any?>) = Unit
        override fun setMuted(muted: Boolean) = Unit
        override fun closePeer() = Unit
        override fun dispose() = Unit
        fun emitState(state: String) { onPeerState?.invoke(state) }
        fun emitIce(state: String) { onIceState?.invoke(state) }
    }

    private class FakeRuntimeBridge : AndroidCallMediaRuntimeBridge {
        var registered = false
        var attachCalls = 0
        var detachCalls = 0
        var disposeCalls = 0
        var systemAudioPreparation: String? = null
        override fun attach(context: android.content.Context?, client: AndroidCallMediaRuntime.Client) {
            attachCalls++
            if (registered) client.onSnapshot(mapOf("type" to "snapshot", "state" to "registered", "sequence" to 6L))
        }
        override fun detach(client: AndroidCallMediaRuntime.Client) { detachCalls++ }
        override fun initialize(context: android.content.Context?, gateway: String, token: String, incomingCallId: String?, result: (Result<String>) -> Unit) = Unit
        override fun prepareForCall(context: android.content.Context?, result: (Result<Unit>) -> Unit) = Unit
        override fun prepareSystemAudio(context: android.content.Context?, callId: String, incoming: Boolean, result: (Result<Unit>) -> Unit) {
            systemAudioPreparation = "$callId:$incoming"
            result(Result.success(Unit))
        }
        override fun abandonCallPreparation(context: android.content.Context?, result: (Result<Unit>) -> Unit) = Unit
        override fun dial(callSid: String, number: String, result: (Result<String>) -> Unit) = Unit
        override fun answerIncoming(callSid: String, result: (Result<Unit>) -> Unit) = Unit
        override fun endMedia(sessionId: String, result: (Result<Unit>) -> Unit) = Unit
        override fun setMuted(muted: Boolean, result: (Result<Unit>) -> Unit) = Unit
        override fun setHeld(held: Boolean, result: (Result<Unit>) -> Unit) = Unit
        override fun sendDtmf(digit: String, result: (Result<Unit>) -> Unit) = Unit
        override fun dispose(result: () -> Unit) { disposeCalls++; registered = false; result() }
    }

    companion object { private const val TOKEN = "ATCAP_secret-never-log" }
}
