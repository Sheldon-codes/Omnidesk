package com.bigbrainzsolutions.omnidesk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
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
        val fullScreen = PendingIntent.getActivity(context, requestCode(callId), OmniDeskIncomingCallActivity.intent(context, values), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val answer = action(context, callId, OmniDeskIncomingCallActivity.answerAction)
        val decline = action(context, callId, OmniDeskIncomingCallActivity.declineAction)
        val notification = NotificationCompat.Builder(context, incomingChannel)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle(name)
            .setContentText("Incoming OmniDesk call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setFullScreenIntent(fullScreen, true)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(
                Person.Builder().setName(name).build(), decline, answer
            ))
            .build()
        NotificationManagerCompat.from(context).notify(notificationId(callId), notification)
    }

    fun dismissIncoming(context: Context, callId: String) {
        NotificationManagerCompat.from(context).cancel(notificationId(callId))
    }

    private fun action(context: Context, callId: String, action: String): PendingIntent =
        PendingIntent.getActivity(context, requestCode("$callId:$action"), OmniDeskIncomingCallActivity.intent(context, mapOf("callId" to callId), action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun notificationId(callId: String) = 41000 + (callId.hashCode() and 0x0fff)
    private fun requestCode(value: String) = value.hashCode()
}

private object RingtoneManagerCompat {
    fun defaultRingtone(): Uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
}
