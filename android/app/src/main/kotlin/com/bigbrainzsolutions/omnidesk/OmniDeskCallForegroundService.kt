package com.bigbrainzsolutions.omnidesk

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Binder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Durable owner of native AT signaling and Android call audio resources. */
class OmniDeskCallForegroundService : Service() {
    private val serial = java.util.concurrent.Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "OmniDeskCallMedia").apply { isDaemon = true }
    }
    private val listeners = java.util.concurrent.CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()
    private val history = ArrayDeque<Map<String, Any?>>()
    private var sequence = 0L
    private var registrationOnly = false
    private lateinit var audio: AndroidCallAudioCoordinator
    private lateinit var peer: ATWebRTCSession
    private lateinit var media: ATNativeMediaCoordinator
    private lateinit var managedInbound: ManagedInboundCallOrchestrator
    private val localBinder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun snapshot(): Map<String, Any?> = this@OmniDeskCallForegroundService.snapshot()
        fun addListener(listener: (Map<String, Any?>) -> Unit) { listeners.add(listener) }
        fun removeListener(listener: (Map<String, Any?>) -> Unit) { listeners.remove(listener) }
        fun initialize(gateway: String, token: String, incomingCallId: String?, callback: (Result<String>) -> Unit) = media.initialize(gateway, token, incomingCallId, callback)
        fun answerIncoming(callSid: String, callback: (Result<Unit>) -> Unit) = media.answerIncoming(callSid, callback)
        fun dial(callSid: String, number: String, callback: (Result<String>) -> Unit) = media.dial(callSid, number, callback)
        fun endMedia(sessionId: String, callback: (Result<Unit>) -> Unit) = media.endCall(sessionId, callback)
        fun setMuted(muted: Boolean, callback: (Result<Unit>) -> Unit) = media.setMuted(muted, callback)
        fun setHeld(held: Boolean, callback: (Result<Unit>) -> Unit) = media.setHeld(held, callback)
        fun sendDtmf(digit: String, callback: (Result<Unit>) -> Unit) = media.sendDtmf(digit, callback)
        fun dispose(callback: () -> Unit) = media.dispose(callback)
        fun hasActiveMediaCall(): Boolean = media.hasActiveCall()
        internal fun beginAudioReadiness(callId: String, incoming: Boolean, callback: (Result<AndroidCallAudioCoordinator.Lease>) -> Unit) {
            serial.execute { audio.begin(callId, incoming, callback) }
        }
        fun telecomFocusChanged(callId: String, gained: Boolean, released: () -> Unit = {}) { serial.execute {
            audio.focusChanged(callId, gained)
            if (!gained) media.onSystemAudioFocusLost(released) else released()
        } }
        fun telecomConnectionState(callId: String, eligible: Boolean, audioState: Boolean = false) {
            serial.execute { audio.connectionState(callId, eligible, audioState) }
        }
        fun endAudioSession(callId: String, callback: () -> Unit = {}) { serial.execute { audio.end(callId); callback() } }
        fun setSpeaker(enabled: Boolean, callback: (Result<Unit>) -> Unit) {
            serial.execute { audio.requestSpeaker(enabled, callback) }
        }
        fun releaseAudio() { serial.execute { audio.releaseMediaLease() } }
        fun answerManagedInbound(callId: String) { managedInbound.answer(callId) }
        fun managedCallDisconnected(callId: String) { managedInbound.onDisconnected(callId) }
        fun managedCallDeclined(callId: String, reason: String) { managedInbound.decline(callId, reason) }
    }

    override fun onCreate() {
        super.onCreate()
        audio = AndroidCallAudioCoordinator(serial, OmniDeskTelecomManager::requestSpeakerRoute)
        peer = ATWebRTCSession(applicationContext, serial, audio)
        media = ATNativeMediaCoordinator(serial, ::publish, peerConnection = peer)
        managedInbound = ManagedInboundCallOrchestrator(applicationContext, serial, media)
        Log.i(logTag, "Native call runtime owner=foreground_service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        OmniDeskCallNotification.ensureChannels(this)
        registrationOnly = intent?.action == actionMedia
        val preparingCall = intent?.action == actionCallPreparation
        val microphoneAllowed = intent?.getBooleanExtra(extraUseMicrophone, false) == true &&
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val notification = NotificationCompat.Builder(this, OmniDeskCallNotification.ongoingChannel)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(if (registrationOnly) "OmniDesk call service" else "OmniDesk call")
            .setContentText(when {
                registrationOnly -> "Preparing AT call signaling"
                preparingCall -> "Preparing call media"
                else -> "Call in progress"
            })
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
        // Android 14+ validates the requested FGS types at runtime. An Answer
        // action may arrive while RECORD_AUDIO has not yet been granted (or
        // before Flutter can request it), so never claim microphone access at
        // that point. Phone-call protection is sufficient to keep the process
        // important through the hand-off to Flutter/WebRTC.
        val serviceTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
            if (microphoneAllowed) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(notificationId, notification, serviceTypes)
            } else {
                @Suppress("DEPRECATION")
                startForeground(notificationId, notification)
            }
            Log.i(logTag, "Call FGS started microphone=$microphoneAllowed")
            intent?.getStringExtra(OmniDeskTelecomManager.extraCallId)?.takeIf { it.isNotBlank() }?.let { callId ->
                serial.execute { audio.foregroundStarted(callId, true) }
            }
        } catch (error: SecurityException) {
            // A service exception is process-fatal when uncaught. Media setup
            // can still surface its normal permission error in Flutter; do
            // not crash the incoming-call process merely for FGS protection.
            Log.e(logTag, "Call FGS denied microphone=$microphoneAllowed", error)
            intent?.getStringExtra(OmniDeskTelecomManager.extraCallId)?.takeIf { it.isNotBlank() }?.let { callId ->
                serial.execute { audio.foregroundStarted(callId, false) }
            }
            stopSelf(startId)
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder = localBinder

    override fun onDestroy() {
        val disposed = java.util.concurrent.CountDownLatch(1)
        media.dispose { disposed.countDown() }
        try { disposed.await(2, java.util.concurrent.TimeUnit.SECONDS) } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        audio.release()
        managedInbound.dispose()
        serial.shutdownNow()
        super.onDestroy()
    }

    private fun publish(raw: Map<String, Any?>) {
        val event = raw + ("sequence" to (++sequence))
        history.addLast(event)
        while (history.size > 64) history.removeFirst()
        listeners.forEach { it(event) }
        if (raw["type"] == "media_event") managedInbound.onMediaEvent(raw)
        if (registrationOnly && event["type"] == "snapshot") {
            val state = event["state"]?.toString() ?: "connecting"
            val text = when (state) {
                "registered" -> "AT signaling registered"
                "failed" -> "AT signaling unavailable"
                else -> "Preparing AT call signaling"
            }
            showRegistrationNotification(text)
        } else if (event["type"] == "media_event" &&
            event["event"] in setOf("ended", "error", "processTerminated") &&
            !media.hasActiveCall()
        ) {
            registrationOnly = true
            showRegistrationNotification("AT signaling registered")
        }
    }

    private fun showRegistrationNotification(text: String) {
        val notification = NotificationCompat.Builder(this, OmniDeskCallNotification.ongoingChannel)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle("OmniDesk call service")
            .setContentText(text)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else {
            @Suppress("DEPRECATION")
            startForeground(notificationId, notification)
        }
    }

    private fun snapshot(): Map<String, Any?> {
        val current = media.currentSnapshot()
        return mapOf("type" to "snapshot", "state" to current.state.name, "sessionId" to current.sessionId,
            "generation" to current.generation, "sequence" to sequence)
    }

    companion object {
        private const val notificationId = 41500
        private const val extraUseMicrophone = "useMicrophone"
        private const val actionMedia = "com.bigbrainzsolutions.omnidesk.NATIVE_MEDIA"
        private const val actionCallPreparation = "com.bigbrainzsolutions.omnidesk.CALL_PREPARATION"
        private const val logTag = "OmniDeskTelecom"

        fun start(context: Context, callId: String, useMicrophone: Boolean) {
            val intent = Intent(context, OmniDeskCallForegroundService::class.java)
                .putExtra(OmniDeskTelecomManager.extraCallId, callId)
                .putExtra(extraUseMicrophone, useMicrophone)
            ContextCompat.startForegroundService(context, intent)
        }
        fun stop(context: Context) = context.stopService(Intent(context, OmniDeskCallForegroundService::class.java))
        fun startMedia(context: Context) {
            val intent = Intent(context, OmniDeskCallForegroundService::class.java).setAction(actionMedia)
            ContextCompat.startForegroundService(context, intent)
        }
        fun startCallPreparation(context: Context) {
            val intent = Intent(context, OmniDeskCallForegroundService::class.java)
                .setAction(actionCallPreparation)
                .putExtra(extraUseMicrophone, true)
            ContextCompat.startForegroundService(context, intent)
        }
    }
}
