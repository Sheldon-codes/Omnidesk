package com.bigbrainzsolutions.omnidesk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Handles CallStyle actions without introducing a second ringing activity. */
class OmniDeskCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(OmniDeskTelecomManager.extraCallId).orEmpty()
        if (intent.action == openManagedAccountSettingsAction) {
            try { OmniDeskTelecomManager.openPhoneAccountSettings(context) }
            catch (_: Throwable) { Log.w(logTag, "Android call-account settings could not be opened") }
            return
        }
        if (callId.isBlank()) {
            Log.w(logTag, "Ignoring call action without call identity")
            return
        }
        when (intent.action) {
            answerAction -> OmniDeskTelecomManager.answer(context, callId)
            declineAction -> OmniDeskTelecomManager.decline(context, callId)
            else -> Log.w(logTag, "Ignoring unknown call action=${intent.action}")
        }
    }

    companion object {
        const val answerAction = "com.bigbrainzsolutions.omnidesk.ANSWER_CALL"
        const val declineAction = "com.bigbrainzsolutions.omnidesk.DECLINE_CALL"
        const val openManagedAccountSettingsAction = "com.bigbrainzsolutions.omnidesk.OPEN_MANAGED_ACCOUNT_SETTINGS"
        private const val logTag = "OmniDeskCallAction"
    }
}
