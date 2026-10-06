package com.bigbrainzsolutions.omnidesk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Application-context binding facade. It never owns or disposes the service runtime. */
internal object AndroidCallMediaRuntime : AndroidCallMediaRuntimeBridge {
    interface Client { fun onSnapshot(value: Map<String, Any?>); fun onEvent(value: Map<String, Any?>) }
    private val clients = CopyOnWriteArraySet<Client>()
    @Volatile private var service: OmniDeskCallForegroundService.LocalBinder? = null
    @Volatile private var appContext: Context? = null
    @Volatile private var binding = false
    @Volatile private var callPreparationActive = false
    private val audioGeneration = AtomicLong()
    private val activeAudioRequests = ConcurrentHashMap<String, Long>()
    private val cancelledManagedOutbound = ConcurrentHashMap.newKeySet<String>()
    private val pendingManagedOutbound = ConcurrentHashMap.newKeySet<String>()
    private val runtimeListener: (Map<String, Any?>) -> Unit = ::broadcast

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val local = binder as? OmniDeskCallForegroundService.LocalBinder ?: return
            service = local
            local.addListener(runtimeListener)
            clients.forEach {
                it.onSnapshot(local.snapshot())
                it.onEvent(local.externalOutboundSnapshot())
            }
            synchronized(this@AndroidCallMediaRuntime) {
                pending.toList().also { pending.clear() }.forEach { it(local) }
            }
        }
        override fun onServiceDisconnected(name: ComponentName?) { service = null }
        override fun onBindingDied(name: ComponentName?) { service = null; binding = false }
        override fun onNullBinding(name: ComponentName?) { service = null; binding = false }
    }

    override fun attach(context: Context?, client: Client) {
        context?.applicationContext?.let { appContext = it }
        clients.add(client)
        bindIfNeeded(start = false)
        service?.let {
            client.onSnapshot(it.snapshot())
            client.onEvent(it.externalOutboundSnapshot())
        }
    }

    override fun detach(client: Client) {
        clients.remove(client)
        // Deliberately do not dispose registration or stop the started service.
        if (clients.isEmpty() && !hasRuntimeOwner()) {
            service?.removeListener(runtimeListener)
            appContext?.unbindService(connection)
            service = null
            binding = false
        }
    }

    override fun initialize(context: Context?, gateway: String, token: String, incomingCallId: String?, result: (Result<String>) -> Unit) {
        val app = context?.applicationContext ?: appContext
            ?: run { result(Result.failure(IllegalStateException("Native media runtime is unavailable."))); return }
        appContext = app
        val current = synchronized(this) {
            service ?: run {
                pending += { binder -> binder.initialize(gateway, token, incomingCallId, result) }
                null
            }
        }
        if (current != null) current.initialize(gateway, token, incomingCallId, result)
        else {
            if (callPreparationActive) OmniDeskCallForegroundService.startCallPreparation(app)
            else OmniDeskCallForegroundService.startMedia(app)
            bindIfNeeded(start = true)
        }
    }

    fun startManagedInbound(context: Context, callId: String) {
        val app = context.applicationContext
        appContext = app
        try {
            OmniDeskCallForegroundService.startCallPreparation(app)
            bindIfNeeded(start = true)
            val current = synchronized(this) {
                service ?: run { pending += { binder -> binder.answerManagedInbound(callId) }; null }
            }
            current?.answerManagedInbound(callId)
        } catch (error: Throwable) {
            OmniDeskTelecomManager.markFailed(app, callId, "call_service_start_failed")
        }
    }

    fun managedCallDisconnected(callId: String) {
        service?.let { binder ->
            // Forward cleanup to the service-owned orchestration instance.
            binder.managedCallDisconnected(callId)
        }
    }

    fun startManagedOutbound(context: Context, localId: String, number: String) {
        val app = context.applicationContext
        appContext = app
        cancelledManagedOutbound.remove(localId)
        pendingManagedOutbound.add(localId)
        try {
            OmniDeskCallForegroundService.start(app, localId, useMicrophone = true)
            val launch: (OmniDeskCallForegroundService.LocalBinder) -> Unit = { binder ->
                pendingManagedOutbound.remove(localId)
                if (!cancelledManagedOutbound.remove(localId)) binder.beginManagedOutbound(localId, number)
            }
            val current = synchronized(this) { service ?: run { pending += launch; null } }
            if (current != null) launch(current) else bindIfNeeded(start = true)
        } catch (_: Throwable) {
            pendingManagedOutbound.remove(localId)
            cancelledManagedOutbound.remove(localId)
            OmniDeskTelecomManager.finishExternalCall(app, localId,
                android.telecom.DisconnectCause.ERROR, "call_service_start_failed")
        }
    }

    fun managedOutboundDisconnected(context: Context, localId: String) {
        if (pendingManagedOutbound.contains(localId)) cancelledManagedOutbound.add(localId)
        val current = service
        if (current != null) current.managedOutboundDisconnected(localId)
        else OmniDeskTelecomManager.finishExternalCall(context, localId,
            android.telecom.DisconnectCause.LOCAL, "local_disconnect")
    }

    fun hasPendingManagedOutbound(): Boolean = pendingManagedOutbound.isNotEmpty()

    fun managedCallDeclined(context: Context, callId: String, reason: String) {
        val app = context.applicationContext
        appContext = app
        try {
            OmniDeskCallForegroundService.startCallPreparation(app)
            bindIfNeeded(start = true)
            val current = synchronized(this) {
                service ?: run { pending += { binder -> binder.managedCallDeclined(callId, reason) }; null }
            }
            current?.managedCallDeclined(callId, reason)
        } catch (_: Throwable) {
            Log.w("OmniDeskManagedCall", "Could not start managed decline handler callId=$callId")
        }
    }

    fun setMuted(value: Boolean) { service?.setMuted(value) { } }
    fun setHeld(value: Boolean) { service?.setHeld(value) { } }
    fun sendDtmf(value: String) { service?.sendDtmf(value) { } }

    override fun answerIncoming(callSid: String, result: (Result<Unit>) -> Unit) {
        val current = service
        if (current == null) result(Result.failure(IllegalStateException("Native media service is unavailable.")))
        else current.answerIncoming(callSid, result)
    }

    override fun prepareForCall(context: Context?, result: (Result<Unit>) -> Unit) {
        val app = context?.applicationContext ?: appContext
            ?: run { result(Result.failure(IllegalStateException("Native media runtime is unavailable."))); return }
        appContext = app
        try {
            callPreparationActive = true
            OmniDeskCallForegroundService.startCallPreparation(app)
            bindIfNeeded(start = true)
            result(Result.success(Unit))
        } catch (_: Throwable) {
            result(Result.failure(IllegalStateException("Call foreground service could not start.")))
        }
    }

    override fun prepareSystemAudio(context: Context?, callId: String, incoming: Boolean, result: (Result<Unit>) -> Unit) {
        val app = context?.applicationContext ?: appContext
            ?: run { result(Result.failure(IllegalStateException("Native media runtime is unavailable."))); return }
        appContext = app
        activeAudioRequests.computeIfAbsent(callId) { audioGeneration.incrementAndGet() }
        OmniDeskTelecomManager.prepareSystemAudio(app, callId, incoming, result)
    }

    override fun abandonCallPreparation(context: Context?, result: (Result<Unit>) -> Unit) {
        val app = context?.applicationContext ?: appContext
        if (app == null) {
            result(Result.success(Unit))
            return
        }
        appContext = app
        if (service?.hasActiveMediaCall() == true) {
            callPreparationActive = false
            result(Result.success(Unit))
            return
        }
        try {
            callPreparationActive = false
            OmniDeskCallForegroundService.startMedia(app)
            result(Result.success(Unit))
        } catch (_: Throwable) {
            result(Result.failure(IllegalStateException("Call preparation could not be released.")))
        }
    }

    override fun dial(callSid: String, number: String, result: (Result<String>) -> Unit) {
        val current = service
        if (current == null) result(Result.failure(IllegalStateException("Native media service is unavailable.")))
        else current.dial(callSid, number, result)
    }

    override fun endMedia(sessionId: String, result: (Result<Unit>) -> Unit) {
        val current = service
        if (current == null) result(Result.failure(IllegalStateException("Native media service is unavailable.")))
        else current.endMedia(sessionId, result)
    }

    override fun setMuted(muted: Boolean, result: (Result<Unit>) -> Unit) {
        val current = service
        if (current == null) result(Result.failure(IllegalStateException("Native media service is unavailable.")))
        else current.setMuted(muted, result)
    }

    override fun setHeld(held: Boolean, result: (Result<Unit>) -> Unit) {
        val current = service
        if (current == null) result(Result.failure(IllegalStateException("Native media service is unavailable.")))
        else current.setHeld(held, result)
    }

    override fun sendDtmf(digit: String, result: (Result<Unit>) -> Unit) {
        val current = service
        if (current == null) result(Result.failure(IllegalStateException("Native media service is unavailable.")))
        else current.sendDtmf(digit, result)
    }

    override fun dispose(result: () -> Unit) {
        val current = service
        if (current != null) current.dispose(result)
        else result()
    }

    override fun externalOutboundSnapshot(): Map<String, Any?> =
        service?.externalOutboundSnapshot() ?: mapOf("type" to "external_outbound_snapshot", "state" to "idle")

    fun setSpeaker(context: Context, enabled: Boolean) {
        setSpeaker(context, enabled) { }
    }

    fun setSpeaker(context: Context, enabled: Boolean, callback: (Result<Unit>) -> Unit) {
        appContext = context.applicationContext
        withService { it.setSpeaker(enabled, callback) }
    }

    fun endSystemAudio(context: Context, callId: String) {
        appContext = context.applicationContext
        activeAudioRequests.remove(callId)
        withService { binder -> binder.endAudioSession(callId) { releaseBindingIfIdle() } }
    }

    fun onTelecomFocusChanged(context: Context, callId: String, gained: Boolean, released: () -> Unit = {}) {
        appContext = context.applicationContext
        withService { it.telecomFocusChanged(callId, gained, released) }
    }

    fun onTelecomConnectionState(context: Context, callId: String, state: Int, audioStateObserved: Boolean) {
        appContext = context.applicationContext
        val eligible = state == android.telecom.Connection.STATE_ACTIVE || state == android.telecom.Connection.STATE_DIALING
        withService { it.telecomConnectionState(callId, eligible, audioStateObserved) }
    }

    fun awaitSystemAudioReadiness(context: Context, callId: String, incoming: Boolean, callback: (Result<Unit>) -> Unit) {
        appContext = context.applicationContext
        val requestGeneration = activeAudioRequests.computeIfAbsent(callId) { audioGeneration.incrementAndGet() }
        withService { binder ->
            if (activeAudioRequests[callId] != requestGeneration) {
                callback(Result.failure(IllegalStateException("system_audio_request_cancelled")))
                return@withService
            }
            binder.beginAudioReadiness(callId, incoming) { outcome ->
                if (activeAudioRequests[callId] == requestGeneration) callback(outcome.map { Unit })
                else callback(Result.failure(IllegalStateException("system_audio_request_cancelled")))
            }
        }
    }

    fun releaseAudio(context: Context) {
        appContext = context.applicationContext
        bindIfNeeded(start = false)
        service?.releaseAudio()
    }

    private val pending = mutableListOf<(OmniDeskCallForegroundService.LocalBinder) -> Unit>()
    private fun hasRuntimeOwner(): Boolean = activeAudioRequests.isNotEmpty() || service?.hasActiveMediaCall() == true

    private fun releaseBindingIfIdle() {
        synchronized(this) {
            if (clients.isNotEmpty() || hasRuntimeOwner() || service == null || binding) return
            service?.removeListener(runtimeListener)
            appContext?.unbindService(connection)
            service = null
            binding = false
        }
    }
    private fun withService(action: (OmniDeskCallForegroundService.LocalBinder) -> Unit) {
        val current = synchronized(this) {
            service ?: run { pending += action; null }
        }
        if (current != null) action(current) else bindIfNeeded(start = false)
    }
    private fun bindIfNeeded(start: Boolean) {
        val ctx = appContext ?: return
        synchronized(this) {
            if (binding || service != null) {
                service?.let { binder -> pending.toList().also { pending.clear() }.forEach { it(binder) } }
                return
            }
            binding = ctx.bindService(Intent(ctx, OmniDeskCallForegroundService::class.java), connection, Context.BIND_AUTO_CREATE)
        }
    }

    private fun broadcast(value: Map<String, Any?>) {
        if (value["type"] == "snapshot") clients.forEach { it.onSnapshot(value) }
        else clients.forEach { it.onEvent(value) }
    }
}

/** Minimal plugin boundary to make engine detach/reattach behavior testable without Android service ownership. */
internal interface AndroidCallMediaRuntimeBridge {
    fun externalOutboundSnapshot(): Map<String, Any?> = mapOf("type" to "external_outbound_snapshot", "state" to "idle")
    fun attach(context: Context?, client: AndroidCallMediaRuntime.Client)
    fun detach(client: AndroidCallMediaRuntime.Client)
    fun initialize(context: Context?, gateway: String, token: String, incomingCallId: String?, result: (Result<String>) -> Unit)
    fun prepareForCall(context: Context?, result: (Result<Unit>) -> Unit)
    fun prepareSystemAudio(context: Context?, callId: String, incoming: Boolean, result: (Result<Unit>) -> Unit)
    fun abandonCallPreparation(context: Context?, result: (Result<Unit>) -> Unit)
    fun dial(callSid: String, number: String, result: (Result<String>) -> Unit)
    fun answerIncoming(callSid: String, result: (Result<Unit>) -> Unit)
    fun endMedia(sessionId: String, result: (Result<Unit>) -> Unit)
    fun setMuted(muted: Boolean, result: (Result<Unit>) -> Unit)
    fun setHeld(held: Boolean, result: (Result<Unit>) -> Unit)
    fun sendDtmf(digit: String, result: (Result<Unit>) -> Unit)
    fun dispose(result: () -> Unit)
}
