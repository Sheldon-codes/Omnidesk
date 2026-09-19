package com.bigbrainzsolutions.omnidesk

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Serial Android implementation of the Flutter native-call boundary.
 *
 * SIP secrets remain inside [NativeBaresip] and are passed only to the JNI
 * registration request. They are never persisted, returned to Flutter, or
 * placed in exception messages. The JNI bridge emits state changes after the
 * Baresip event loop confirms them; it never fabricates a connected event.
 */
class BaresipMediaCoordinator(
    private val context: Context,
    private val emit: (NativeEvent) -> Unit,
) {
    private val logTag = "OmniDeskCalls"
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private var registration: PendingRegistration? = null
    private var activeSession: MediaSession? = null

    init {
        NativeBaresip.listener = ::onNativeEvent
        stageTlsTrust()
    }

    /**
     * Copies the bundled root-CA PEM (res/raw, mirrored from
     * assets/certs/ca_bundle.pem) into internal storage and points the
     * native TLS stack at it. Android has no OpenSSL default verify path,
     * so without this every SIP/TLS handshake fails validation.
     */
    private fun stageTlsTrust() {
        try {
            val out = java.io.File(context.filesDir, "ca_bundle.pem")
            if (!out.exists()) {
                context.resources.openRawResource(
                    context.resources.getIdentifier("ca_bundle", "raw", context.packageName)
                ).use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
            }
            NativeBaresip.setCaFile(out.absolutePath)
        } catch (error: Throwable) {
            Log.w(logTag, "TLS CA bundle staging failed; SIP/TLS verification will fail", error)
        }
    }

    fun ensureRegistered(
        config: MediaConfig,
        incomingCallId: String?,
        onReady: (String) -> Unit,
        onFailure: (NativeFailure) -> Unit,
    ) {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Log.w(logTag, "native registration blocked: microphone permission required")
            onFailure(NativeFailure("microphone_permission_required", "Allow microphone access to make and receive calls."))
            return
        }
        if (!config.isValid) {
            Log.e(logTag, "native registration blocked: invalid SIP media configuration")
            onFailure(NativeFailure("invalid_media_config", "The call service returned incomplete SIP settings."))
            return
        }
        registration?.let { pending ->
            if (pending.config.identity == config.identity) {
                pending.successes += onReady
                pending.failures += onFailure
                return
            }
            onFailure(NativeFailure("registration_in_progress", "Another call workspace is registering."))
            return
        }
        try {
            Log.i(logTag, "requesting SIP registration")
            val sessionId = NativeBaresip.ensureRegistered(
                config.uri, config.username, config.authUsername, config.password,
                config.registrar, config.domain, config.proxy, config.transport,
                config.port, incomingCallId,
            )
            registration = PendingRegistration(config, sessionId, incomingCallId, mutableListOf(onReady), mutableListOf(onFailure))
        } catch (error: Throwable) {
            Log.e(logTag, "native SIP registration invocation failed", error)
            onFailure(NativeFailure("native_media_unavailable", "Native SIP media is unavailable on this build."))
        }
    }

    fun startOutgoing(
        callSid: String,
        targetSipUri: String,
        onReady: (String) -> Unit,
        onFailure: (NativeFailure) -> Unit,
    ) {
        val registered = registration
        if (registered == null || !registered.confirmed) {
            Log.w(logTag, "outgoing media blocked: SIP registration is not confirmed")
            onFailure(NativeFailure("sip_not_registered", "The SIP account is not registered yet."))
            return
        }
        try {
            Log.i(logTag, "requesting outgoing SIP media")
            val sessionId = NativeBaresip.startOutgoing(callSid, targetSipUri)
            activeSession = MediaSession(sessionId, callSid = callSid, callId = null)
            onReady(sessionId)
        } catch (_: Throwable) {
            Log.e(logTag, "native outgoing SIP media invocation failed")
            onFailure(NativeFailure("outgoing_media_failed", "Unable to start the native SIP call."))
        }
    }

    fun end(mediaSessionId: String, result: MethodChannel.Result) = execute(result) {
        if (activeSession?.id == mediaSessionId || registration?.id == mediaSessionId) {
            NativeBaresip.end(mediaSessionId)
            activeSession = null
        }
    }

    fun setMuted(enabled: Boolean, result: MethodChannel.Result) = execute(result) {
        NativeBaresip.setMuted(enabled)
    }

    @Suppress("DEPRECATION")
    fun setSpeaker(enabled: Boolean, result: MethodChannel.Result) = execute(result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val speaker = audioManager.availableCommunicationDevices.firstOrNull {
                it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
            if (enabled && speaker != null) audioManager.setCommunicationDevice(speaker)
            if (!enabled) audioManager.clearCommunicationDevice()
        } else {
            audioManager.isSpeakerphoneOn = enabled
        }
    }

    fun setHeld(enabled: Boolean, result: MethodChannel.Result) = execute(result) {
        NativeBaresip.setHeld(enabled)
    }

    fun sendDtmf(digit: String, result: MethodChannel.Result) = execute(result) {
        NativeBaresip.sendDtmf(digit.single())
    }

    private fun execute(result: MethodChannel.Result, block: () -> Unit) {
        try {
            block()
            result.success(null)
        } catch (_: Throwable) {
            result.error("native_media_failed", "The native call action could not be completed.", null)
        }
    }

    private fun onNativeEvent(event: NativeEvent) {
        Log.i(logTag, "native event=${event.type}${event.reason?.let { " reason=$it" } ?: ""}")
        val pending = registration
        if (pending != null && event.type == "registered" && event.mediaSessionId == pending.id) {
            Log.i(logTag, "SIP registration confirmed")
            pending.confirmed = true
            activeSession = MediaSession(pending.id, callSid = null, callId = pending.incomingCallId)
            pending.successes.forEach { it(pending.id) }
            pending.successes.clear()
            pending.failures.clear()
        } else if (pending != null && event.type == "failed" && event.mediaSessionId == pending.id) {
            Log.e(logTag, "SIP registration failed: ${event.reason ?: "unknown native error"}")
            pending.failures.forEach { it(NativeFailure("sip_registration_failed", event.reason ?: "SIP registration failed.")) }
            registration = null
        }
        emit(event)
    }

    private data class PendingRegistration(
        val config: MediaConfig,
        val id: String,
        val incomingCallId: String?,
        val successes: MutableList<(String) -> Unit>,
        val failures: MutableList<(NativeFailure) -> Unit>,
        var confirmed: Boolean = false,
    )

    private data class MediaSession(val id: String, val callSid: String?, val callId: String?)
}

internal fun Map<*, *>.requiredString(name: String): String =
    this[name]?.toString()?.takeIf { it.isNotBlank() }
        ?: throw IllegalArgumentException("Missing media configuration field: $name")

data class MediaConfig(
    val uri: String,
    val username: String,
    val authUsername: String,
    val password: String,
    val registrar: String,
    val domain: String,
    val proxy: String,
    val transport: String,
    val port: Int,
) {
    val identity: String get() = "$uri@$registrar:$port/$transport"
    val isValid: Boolean get() = listOf(uri, username, authUsername, password, registrar, domain, proxy).all { it.isNotBlank() } && transport.equals("tls", true) && port > 0

    companion object {
        fun from(args: Map<*, *>) = MediaConfig(
            uri = args.requiredString("uri"), username = args.requiredString("username"),
            authUsername = args.requiredString("authUsername"), password = args.requiredString("password"),
            registrar = args.requiredString("registrar"), domain = args.requiredString("domain"),
            proxy = args.requiredString("proxy"), transport = args.requiredString("transport"),
            port = args["port"]?.toString()?.toIntOrNull() ?: 0,
        )
    }
}

data class NativeFailure(val code: String, val message: String)
data class NativeEvent(
    val type: String,
    val callId: String? = null,
    val callSid: String? = null,
    val mediaSessionId: String? = null,
    val reason: String? = null,
) {
    val arguments: Map<String, String> get() = buildMap {
        callId?.let { put("callId", it) }; callSid?.let { put("callSid", it) }
        mediaSessionId?.let { put("mediaSessionId", it) }; reason?.let { put("reason", it) }
    }
}

object NativeBaresip {
    var listener: ((NativeEvent) -> Unit)? = null
    private val loaded: Boolean by lazy { runCatching { System.loadLibrary("omnidesk_baresip") }.isSuccess }
    private fun requireLoaded() { check(loaded) { "Native Baresip libraries are not installed." } }

    fun ensureRegistered(
        uri: String, username: String, authUsername: String, password: String,
        registrar: String, domain: String, proxy: String, transport: String,
        port: Int, incomingCallId: String?,
    ): String { requireLoaded(); return nativeEnsureRegistered(uri, username, authUsername, password, registrar, domain, proxy, transport, port, incomingCallId) }
    fun startOutgoing(callSid: String, targetSipUri: String): String { requireLoaded(); return nativeStartOutgoing(callSid, targetSipUri) }
    fun end(mediaSessionId: String) { requireLoaded(); nativeEnd(mediaSessionId) }
    fun setMuted(enabled: Boolean) { requireLoaded(); nativeSetMuted(enabled) }
    fun setHeld(enabled: Boolean) { requireLoaded(); nativeSetHeld(enabled) }
    fun sendDtmf(digit: Char) { requireLoaded(); nativeSendDtmf(digit) }
    fun setCaFile(path: String) { requireLoaded(); nativeSetCaFile(path) }

    private external fun nativeEnsureRegistered(uri: String, username: String, authUsername: String, password: String, registrar: String, domain: String, proxy: String, transport: String, port: Int, incomingCallId: String?): String
    private external fun nativeStartOutgoing(callSid: String, targetSipUri: String): String
    private external fun nativeEnd(mediaSessionId: String)
    private external fun nativeSetMuted(enabled: Boolean)
    private external fun nativeSetHeld(enabled: Boolean)
    private external fun nativeSendDtmf(digit: Char)
    private external fun nativeSetCaFile(path: String)

    @JvmStatic fun emit(type: String, callId: String?, callSid: String?, mediaSessionId: String?, reason: String?) {
        listener?.invoke(NativeEvent(type, callId, callSid, mediaSessionId, reason))
    }
}
