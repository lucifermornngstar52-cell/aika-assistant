package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log

/**
 * AikaMicrophoneService — Foreground Service с типом microphone.
 *
 * 1. foregroundServiceType="microphone" → Android НЕ глушит микрофон в фоне
 * 2. WakeLock (PARTIAL_WAKE_LOCK) → CPU не спит когда экран выключен
 * 3. PhoneStateListener → глушит ТОЛЬКО при звонках
 *
 * НЕ запрашивает AudioFocus — это конфликтовало с speech_to_text.
 * Музыка НЕ глушит микрофон.
 */
class AikaMicrophoneService : Service() {

    companion object {
        private const val TAG = "AikaMic"
        private const val CHANNEL_ID = "aika_microphone_channel"
        private const val NOTIF_ID = 7771
        const val ACTION_START = "com.aika.MIC_START"
        const val ACTION_STOP = "com.aika.MIC_STOP"
        const val ACTION_PAUSE = "com.aika.MIC_PAUSE"
        const val ACTION_RESUME = "com.aika.MIC_RESUME"

        var isActive = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var telephonyManager: TelephonyManager? = null
    private var isPaused = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                Log.d(TAG, "START")
                if (!hasMicPermission()) {
                    Log.e(TAG, "RECORD_AUDIO not granted")
                    stopSelf()
                    return START_NOT_STICKY
                }
                try {
                    startForegroundWithMicrophoneType()
                    acquireWakeLock()
                    setupPhoneStateListener()
                    isActive = true
                    isPaused = false
                } catch (e: Exception) {
                    Log.e(TAG, "Failed: ${e.message}")
                    try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
            ACTION_STOP -> {
                Log.d(TAG, "STOP")
                releaseAll()
                try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
                stopSelf()
            }
            ACTION_PAUSE -> {
                Log.d(TAG, "PAUSE — call/voice recording")
                isPaused = true
            }
            ACTION_RESUME -> {
                Log.d(TAG, "RESUME")
                isPaused = false
            }
        }
        return START_STICKY
    }

    private fun hasMicPermission(): Boolean {
        return checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun startForegroundWithMicrophoneType() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed: ${e.message}")
            try { startForeground(NOTIF_ID, notification) } catch (e2: Exception) { throw e2 }
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aika:MicrophoneWakeLock")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) { Log.e(TAG, "WakeLock error: ${e.message}") }
    }

    private fun releaseWakeLock() {
        try { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null } catch (_: Exception) {}
    }

    private fun setupPhoneStateListener() {
        try {
            telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            telephonyManager?.listen(object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    when (state) {
                        TelephonyManager.CALL_STATE_IDLE -> {
                            if (isPaused) {
                                isPaused = false
                                Log.d(TAG, "Call ended — resume")
                            }
                        }
                        TelephonyManager.CALL_STATE_RINGING, TelephonyManager.CALL_STATE_OFFHOOK -> {
                            isPaused = true
                            Log.d(TAG, "Call active — pause")
                        }
                    }
                }
            }, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (e: Exception) { Log.e(TAG, "PhoneState error: ${e.message}") }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Aika Microphone", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Микрофон активен"; setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val iconRes = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_silent_mode_off
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Aika слушает")
            .setContentText("Микрофон активен")
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    private fun releaseAll() {
        releaseWakeLock()
        try { telephonyManager?.listen(null, PhoneStateListener.LISTEN_CALL_STATE) } catch (_: Exception) {}
        isActive = false; isPaused = false
    }

    override fun onDestroy() { releaseAll(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
