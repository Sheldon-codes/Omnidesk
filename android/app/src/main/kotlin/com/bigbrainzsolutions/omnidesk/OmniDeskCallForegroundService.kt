package com.bigbrainzsolutions.omnidesk

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Keeps the process important while Flutter's hidden WebView owns media. */
class OmniDeskCallForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        OmniDeskCallNotification.ensureChannels(this)
        val microphoneAllowed = intent?.getBooleanExtra(extraUseMicrophone, false) == true &&
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val notification = NotificationCompat.Builder(this, OmniDeskCallNotification.ongoingChannel)
            .setSmallIcon(android.R.drawable.sym_action_call)
            .setContentTitle("OmniDesk call")
            .setContentText("Call in progress")
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
        } catch (error: SecurityException) {
            // A service exception is process-fatal when uncaught. Media setup
            // can still surface its normal permission error in Flutter; do
            // not crash the incoming-call process merely for FGS protection.
            Log.e(logTag, "Call FGS denied microphone=$microphoneAllowed", error)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val notificationId = 41500
        private const val extraUseMicrophone = "useMicrophone"
        private const val logTag = "OmniDeskTelecom"

        fun start(context: Context, callId: String, useMicrophone: Boolean) {
            val intent = Intent(context, OmniDeskCallForegroundService::class.java)
                .putExtra("callId", callId)
                .putExtra(extraUseMicrophone, useMicrophone)
            ContextCompat.startForegroundService(context, intent)
        }
        fun stop(context: Context) = context.stopService(Intent(context, OmniDeskCallForegroundService::class.java))
    }
}
