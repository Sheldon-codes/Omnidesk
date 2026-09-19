package com.bigbrainzsolutions.omnidesk

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val callsChannel = "africa.omnidesk/calls"
    private lateinit var channel: MethodChannel
    private lateinit var media: BaresipMediaCoordinator

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callsChannel)
        media = BaresipMediaCoordinator(applicationContext) { event ->
            runOnUiThread { channel.invokeMethod(event.type, event.arguments) }
        }
        channel.setMethodCallHandler(::handleCallMethod)
    }

    private fun handleCallMethod(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        when (call.method) {
            "ensureRegistered" -> media.ensureRegistered(
                MediaConfig.from(args), args.string("callId"),
                onReady = result::success,
                onFailure = { error -> result.error(error.code, error.message, null) },
            )
            "startOutgoingMedia" -> media.startOutgoing(
                callSid = args.requiredString("callSid"),
                targetSipUri = args.requiredString("targetSipUri"),
                onReady = result::success,
                onFailure = { error -> result.error(error.code, error.message, null) },
            )
            "endMedia" -> media.end(args.requiredString("mediaSessionId"), result)
            "setMuted" -> media.setMuted(args["enabled"] == true, result)
            "setSpeaker" -> media.setSpeaker(args["enabled"] == true, result)
            "setHeld" -> media.setHeld(args["enabled"] == true, result)
            "sendDtmf" -> media.sendDtmf(args.requiredString("digit"), result)
            else -> result.notImplemented()
        }
    }
}

private fun Map<*, *>.string(name: String): String? = this[name]?.toString()?.takeIf { it.isNotBlank() }
