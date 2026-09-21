package com.bigbrainzsolutions.omnidesk

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Keeps the process important while Flutter's hidden WebView owns media. */
class OmniDeskCallForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        OmniDeskCallNotification.ensureChannels(this)
        val notification = NotificationCompat.Builder(this, OmniDeskCallNotification.ongoingChannel)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle("OmniDesk call")
            .setContentText("Call in progress")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
        startForeground(notificationId, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val notificationId = 41500
        fun start(context: Context, callId: String) {
            val intent = Intent(context, OmniDeskCallForegroundService::class.java).putExtra("callId", callId)
            ContextCompat.startForegroundService(context, intent)
        }
        fun stop(context: Context) = context.stopService(Intent(context, OmniDeskCallForegroundService::class.java))
    }
}
