package com.bigbrainzsolutions.omnidesk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.Person
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object OmniDeskCallNotification {
    const val incomingChannel = "omnidesk_incoming_calls"
    const val ongoingChannel = "omnidesk_ongoing_calls"

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val ringtone = RingtoneManagerCompat.defaultRingtone()
        manager.createNotificationChannel(
            NotificationChannel(incomingChannel, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(ringtone, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(ongoingChannel, "Ongoing calls", NotificationManager.IMPORTANCE_LOW)
        )
    }

    fun showIncoming(context: Context, values: Map<String, String>) {
        ensureChannels(context)
        val callId = values["callId"].orEmpty()
        val name = values["callerName"].orEmpty().ifBlank { values["callerNumber"].orEmpty() }
        val flutterIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(OmniDeskTelecomManager.extraCallId, callId)
            putExtra(OmniDeskTelecomManager.extraOfferId, values["offerId"])
        }
        val contentIntent = PendingIntent.getActivity(
            context, requestCode("content:$callId"), flutterIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val answer = action(context, callId, OmniDeskCallActionReceiver.answerAction)
        val decline = action(context, callId, OmniDeskCallActionReceiver.declineAction)
        val builder = NotificationCompat.Builder(context, incomingChannel)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(name)
            .setContentText("Incoming OmniDesk call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(
                Person.Builder().setName(name).build(), decline, answer
            ))
        // Android 14 can revoke the ability to *launch* a full-screen
        // activity, but CallStyle still requires a non-null full-screen
        // intent unless its notification belongs to a foreground service.
        // Keep the intent attached in both cases: the OS will choose the
        // heads-up/lock-screen fallback when permission is denied.
        val fullScreenAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
        builder.setFullScreenIntent(contentIntent, true)
        Log.i(
            "OmniDeskTelecom",
            "Posting CallStyle notification callId=$callId " +
                "fullScreenIntentAttached=true fullScreenAllowed=$fullScreenAllowed",
        )
        val notification = builder.build()
        NotificationManagerCompat.from(context).notify(notificationId(callId), notification)
    }

    fun dismissIncoming(context: Context, callId: String) {
        NotificationManagerCompat.from(context).cancel(notificationId(callId))
    }

    private fun action(context: Context, callId: String, action: String): PendingIntent {
        val intent = Intent(context, OmniDeskCallActionReceiver::class.java).apply {
            this.action = action
            putExtra(OmniDeskTelecomManager.extraCallId, callId)
        }
        return PendingIntent.getBroadcast(
            context, requestCode("$callId:$action"), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun notificationId(callId: String) = 41000 + (callId.hashCode() and 0x0fff)
    private fun requestCode(value: String) = value.hashCode()
}

private object RingtoneManagerCompat {
    fun defaultRingtone(): Uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
}
