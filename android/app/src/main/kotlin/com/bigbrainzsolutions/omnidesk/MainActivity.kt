package com.bigbrainzsolutions.omnidesk

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val callsChannel = "africa.omnidesk/calls"
    private lateinit var channel: MethodChannel
    private var incomingLaunchCallId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyIncomingCallLaunch(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(AndroidNativeCallMediaPlugin::class.java)) {
            flutterEngine.plugins.add(AndroidNativeCallMediaPlugin())
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callsChannel)
        AndroidCallEventBridge.attach(channel)
        channel.setMethodCallHandler(::handleCallMethod)
        Log.i(logTag, "Call method channel configured")
        notifyIncomingIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyIncomingCallLaunch(intent)
        notifyIncomingIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        currentActivity = this
        isForeground = true
    }

    override fun onPause() {
        isForeground = false
        super.onPause()
    }

    private fun notifyIncomingIntent(intent: android.content.Intent?) {
        val callId = intent?.getStringExtra(OmniDeskTelecomManager.extraCallId).orEmpty()
        if (callId.isNotBlank()) {
            Log.i(logTag, "Flutter opened from incoming-call notification callId=$callId")
            OmniDeskTelecomManager.notifyIncomingOpened(callId)
        }
    }

    /**
     * Only a live, matching Telecom offer may wake the lock screen.  This is
     * deliberately not applied for ordinary app launches, otherwise a stale
     * notification intent could keep MainActivity visible over the keyguard.
     */
    private fun applyIncomingCallLaunch(intent: Intent?) {
        val callId = intent?.getStringExtra(OmniDeskTelecomManager.extraCallId).orEmpty()
        val offerId = intent?.getStringExtra(OmniDeskTelecomManager.extraOfferId).orEmpty()
        if (callId.isBlank() || offerId.isBlank()) return
        if (!IncomingCallStateStore.saveIncomingLaunch(applicationContext, callId, offerId)) {
            Log.w(logTag, "Ignoring stale incoming-call launch callId=$callId")
            return
        }
        incomingLaunchCallId = callId
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        Log.i(logTag, "Incoming-call launch prepared callId=$callId")
    }

    private fun handleCallMethod(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val callId = args["callId"]?.toString().orEmpty()
        val callSid = args["callSid"]?.toString().orEmpty()
        val systemCallId = callId.ifBlank { callSid }
        Log.i(logTag, "Flutter native call method=${call.method} callId=$callId callSid=$callSid")
        when (call.method) {
            // Native call identity/action bridge. Media remains owned by the
            // foreground service; Activity methods only forward Telecom work.
            "readNativePushToken" -> result.success(IncomingCallStateStore.readFcmToken(applicationContext))
            "peekPendingOffer" -> result.success(IncomingCallStateStore.peekOffer(applicationContext))
            "takePendingOffer" -> result.success(IncomingCallStateStore.takeOffer(applicationContext))
            "peekInitialIncomingLaunch" -> result.success(IncomingCallStateStore.peekIncomingLaunch(applicationContext))
            "takeInitialIncomingLaunch" -> result.success(IncomingCallStateStore.takeIncomingLaunch(applicationContext))
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
            "markSystemCallAnswering" -> { OmniDeskTelecomManager.markAnswering(applicationContext, systemCallId); result.success(null) }
            "markSystemCallActive" -> { OmniDeskTelecomManager.markActive(applicationContext, systemCallId); result.success(null) }
            "markSystemCallFailed" -> { OmniDeskTelecomManager.markFailed(applicationContext, systemCallId, args["reason"]?.toString()); result.success(null) }
            "dismissSystemCall" -> { OmniDeskTelecomManager.dismiss(applicationContext, systemCallId); result.success(null) }
            "setSystemSpeaker" -> OmniDeskTelecomManager.setSpeaker(applicationContext, args["enabled"] == true) { outcome ->
                runOnUiThread {
                    outcome.fold(
                        onSuccess = { result.success(null) },
                        onFailure = { result.error("system_audio_route_failed", it.message ?: "Telecom rejected the route.", null) },
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDestroy() {
        if (::channel.isInitialized) AndroidCallEventBridge.detach(channel)
        if (currentActivity === this) currentActivity = null
        super.onDestroy()
    }

    companion object {
        const val logTag = "OmniDeskCallPush"
        @Volatile var isForeground: Boolean = false

        @Volatile private var currentActivity: MainActivity? = null

        fun clearIncomingCallLaunchPresentation(callId: String) {
            val activity = currentActivity ?: return
            activity.runOnUiThread {
                if (activity.incomingLaunchCallId == callId) {
                    activity.setShowWhenLocked(false)
                    activity.setTurnScreenOn(false)
                    activity.incomingLaunchCallId = null
                    Log.i(logTag, "Incoming-call lock-screen flags cleared callId=$callId")
                }
            }
        }
    }
}
