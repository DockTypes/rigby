package com.rigby.app

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

// This service exists solely to show a foreground notification while Rigby listens.
// It keeps the process alive and maintains microphone access in background so that
// Flutter's speech_to_text plugin (running in the Activity's FlutterEngine) can
// continue to receive audio even when the app is not visible.
//
// SpeechRecognizer is NOT used here — on Android 14+ it silently drops all
// callbacks when called from a Service context (no window token). Flutter's
// speech_to_text runs through the FlutterEngine which has the Activity context
// and window token, so its callbacks fire correctly even in background.
class RigbyListeningService : Service() {

    companion object {
        const val CHANNEL_ID = "rigby_wake_word_channel"
        const val NOTIFICATION_ID = 1001
        const val TAG = "RigbyService"
    }

    // Partial WakeLock keeps the CPU active when the screen is turned off to prevent Doze mode from freezing STT.
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    @SuppressLint("WakelockTimeout")
    override fun onCreate() {
        super.onCreate()
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "RigbyApp::WakeLockSTT"
            ).also {
                // Acquired without timeout; cleanly released in onDestroy when the service stops.
                it.acquire()
                Log.d(TAG, "✅ WakeLock acquired (no timeout)")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                createNotificationChannel()
            }
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                    )
                } catch (se: SecurityException) {
                    Log.w(TAG, "RECORD_AUDIO not granted yet, fallback to standard foreground: ${se.message}")
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "✅ RigbyListeningService started")
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed: ${e.message}")
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_NOT_STICKY

    override fun onDestroy() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
            Log.d(TAG, "WakeLock released")
        } catch (_: Exception) {}
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
        super.onDestroy()
        Log.d(TAG, "RigbyListeningService destroyed")
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Rigby Wake Word",
            // IMPORTANCE_LOW ensures a silent notification without sound or vibration
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Rigby ascultă în fundal"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): android.app.Notification {
        val tapIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val pendingIntent = tapIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Rigby ascultă")
            .setContentText("Spune «Rigby» pentru a activa")
            // Use local drawable resource for reliable rendering across OEM ROMs
            .setSmallIcon(R.drawable.ic_notification_mic)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
        pendingIntent?.let { builder.setContentIntent(it) }
        return builder.build()
    }
}
