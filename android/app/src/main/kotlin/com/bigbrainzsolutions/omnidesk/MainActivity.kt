package com.bigbrainzsolutions.omnidesk

import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val callsChannel = "africa.omnidesk/calls"
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callsChannel)
        AndroidCallEventBridge.attach(channel)
        channel.setMethodCallHandler(::handleCallMethod)
        Log.i(logTag, "Call method channel configured")
        notifyIncomingIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        notifyIncomingIntent(intent)
    }

    private fun notifyIncomingIntent(intent: android.content.Intent?) {
        val callId = intent?.getStringExtra(OmniDeskTelecomManager.extraCallId).orEmpty()
        if (callId.isNotBlank()) {
            Log.i(logTag, "Flutter opened from incoming-call notification callId=$callId")
            OmniDeskTelecomManager.notifyIncomingOpened(callId)
        }
    }

    private fun handleCallMethod(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val callId = args["callId"]?.toString() ?: "none"
        val callSid = args["callSid"]?.toString() ?: "none"
        Log.i(logTag, "Flutter native call method=${call.method} callId=$callId callSid=$callSid")
        when (call.method) {
            // Gate 1 system-call boundary. Android Telecom takes ownership in
            // Gate 3; these no-op acknowledgements keep the established
            // Flutter/WebRTC path functional while no SIP method is exposed
            // through NativeCallService any longer.
            "readNativePushToken" -> result.success(IncomingCallStateStore.readFcmToken(applicationContext))
            "takePendingOffer" -> result.success(IncomingCallStateStore.takeOffer(applicationContext))
            "takePendingAction" -> result.success(IncomingCallStateStore.takeAction(applicationContext))
            "presentIncoming" -> {
                try {
                    val receipt = OmniDeskTelecomManager.presentIncoming(applicationContext, args.mapNotNull { (key, value) -> value?.toString()?.let { key.toString() to it } }.toMap())
                    result.success(receipt.toMap())
                } catch (error: Throwable) { result.error("telecom_presentation_failed", error.message, null) }
            }
            "beginOutgoingSystemCall" -> {
                try { OmniDeskTelecomManager.beginOutgoing(applicationContext, args.mapNotNull { (key, value) -> value?.toString()?.let { key.toString() to it } }.toMap()); result.success(null) }
                catch (error: Throwable) { result.error("telecom_outgoing_failed", error.message, null) }
            }
            "markSystemCallActive" -> { OmniDeskTelecomManager.markActive(applicationContext, callId); result.success(null) }
            "markSystemCallFailed" -> { OmniDeskTelecomManager.markFailed(applicationContext, callId, args["reason"]?.toString()); result.success(null) }
            "dismissSystemCall" -> { OmniDeskTelecomManager.dismiss(applicationContext, callId); result.success(null) }
            "setSystemSpeaker" -> { OmniDeskTelecomManager.setSpeaker(applicationContext, args["enabled"] == true); result.success(null) }
            else -> result.notImplemented()
        }
    }

    override fun onDestroy() {
        if (::channel.isInitialized) AndroidCallEventBridge.detach(channel)
        super.onDestroy()
    }

    private companion object {
        const val logTag = "OmniDeskCallPush"
    }
}
