package com.bigbrainzsolutions.omnidesk

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Engine-scoped bridge only; detaching it never tears down service-owned registration. */
class AndroidNativeCallMediaPlugin internal constructor(
    private val runtime: AndroidCallMediaRuntimeBridge,
    private val postToMain: (() -> Unit) -> Unit,
) : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, AndroidCallMediaRuntime.Client {
    constructor() : this(AndroidCallMediaRuntime, { action -> Handler(Looper.getMainLooper()).post(action) })
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    @Volatile private var latestSnapshot: Map<String, Any?> = mapOf("state" to "idle", "sequence" to 0L)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also { it.setStreamHandler(this) }
        attachRuntime(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sink = null
        detachRuntime()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        postToMain { eventSink.success(latestSnapshot) }
    }

    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> result.success(latestSnapshot)
            "externalOutboundSnapshot" -> result.success(runtime.externalOutboundSnapshot())
            "prepareForCall" -> runtime.prepareForCall(applicationContext) {
                completeUnit(result, it, "call_service_start_failed")
            }
            "prepareSystemAudio" -> {
                val args = call.arguments as? Map<*, *>
                val callId = args?.get("systemCallId") as? String
                val incoming = args?.get("incoming") as? Boolean ?: false
                if (callId.isNullOrBlank()) {
                    result.error("invalid_system_call", "System call identity is missing.", null)
                    return
                }
                runtime.prepareSystemAudio(applicationContext, callId, incoming) {
                    completeUnit(result, it, "system_audio_not_ready")
                }
            }
            "abandonCallPreparation" -> runtime.abandonCallPreparation(applicationContext) {
                completeUnit(result, it, "call_preparation_release_failed")
            }
            "initialize" -> {
                val args = call.arguments as? Map<*, *>
                val gateway = args?.get("gatewayUrl") as? String
                val token = args?.get("token") as? String
                val incomingCallId = args?.get("incomingCallId") as? String
                if (gateway.isNullOrBlank() || token.isNullOrBlank()) {
                    result.error("invalid_media_config", "AT media configuration is incomplete.", null)
                    return
                }
                runtime.initialize(
                    /* context is provided through the service-owned runtime binding */
                    context = requireNotNull(applicationContext), gateway = gateway, token = token, incomingCallId = incomingCallId,
                ) { outcome ->
                    postToMain {
                        outcome.fold(
                            onSuccess = { sessionId -> result.success(mapOf("sessionId" to sessionId)) },
                            onFailure = { error -> result.error("native_registration_failed", error.message ?: "AT registration failed.", null) },
                        )
                    }
                }
            }
            "dispose" -> runtime.dispose { postToMain { result.success(null) } }
            "dial" -> {
                val args = call.arguments as? Map<*, *>
                val callSid = args?.get("callSid") as? String
                val number = args?.get("phoneNumber") as? String
                if (callSid.isNullOrBlank() || number.isNullOrBlank()) {
                    result.error("invalid_call", "Outbound call details are incomplete.", null)
                    return
                }
                runtime.dial(callSid, number) { outcome ->
                    postToMain {
                        outcome.fold(
                            onSuccess = { sessionId -> result.success(mapOf("sessionId" to sessionId)) },
                            onFailure = { error -> result.error("native_dial_failed", error.message ?: "Native call setup failed.", null) },
                        )
                    }
                }
            }
            "end" -> {
                val sessionId = (call.arguments as? Map<*, *>)?.get("sessionId") as? String
                if (sessionId.isNullOrBlank()) {
                    result.error("invalid_media_session", "Native media session is missing.", null)
                    return
                }
                runtime.endMedia(sessionId) { completeUnit(result, it, "native_end_failed") }
            }
            "setMuted" -> {
                val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: false
                runtime.setMuted(enabled) { completeUnit(result, it, "native_mute_failed") }
            }
            "setHeld" -> {
                val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: false
                runtime.setHeld(enabled) { completeUnit(result, it, "native_hold_failed") }
            }
            "sendDtmf" -> {
                val digit = (call.arguments as? Map<*, *>)?.get("digit") as? String
                if (digit == null) {
                    result.error("invalid_dtmf", "DTMF digit is missing.", null)
                    return
                }
                runtime.sendDtmf(digit) { completeUnit(result, it, "native_dtmf_failed") }
            }
            "answer" -> {
                val callSid = (call.arguments as? Map<*, *>)?.get("callSid") as? String
                if (callSid.isNullOrBlank()) {
                    result.error("invalid_call", "Inbound call identity is missing.", null)
                    return
                }
                runtime.answerIncoming(callSid) { completeUnit(result, it, "native_answer_failed") }
            }
            else -> result.notImplemented()
        }
    }

    private fun completeUnit(result: MethodChannel.Result, outcome: Result<Unit>, code: String) {
        postToMain {
            outcome.fold(
                onSuccess = { result.success(null) },
                onFailure = { error -> result.error(code, error.message ?: "Native call operation failed.", null) },
            )
        }
    }

    private var applicationContext: android.content.Context? = null

    internal fun attachRuntime(context: android.content.Context?) = runtime.attach(context, this)
    internal fun detachRuntime() = runtime.detach(this)
    internal fun latestSnapshotForTests() = latestSnapshot

    override fun onSnapshot(value: Map<String, Any?>) {
        latestSnapshot = value
        onEvent(value)
    }

    override fun onEvent(value: Map<String, Any?>) {
        postToMain { sink?.success(value) }
    }

    companion object {
        const val METHOD_CHANNEL = "africa.omnidesk/media"
        const val EVENT_CHANNEL = "africa.omnidesk/media_events"
    }
}
