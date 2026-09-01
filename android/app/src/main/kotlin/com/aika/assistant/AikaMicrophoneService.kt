package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log

class AikaMicrophoneService : Service() {

    companion object {
        private const val TAG = "AikaMic"
        private const val CHANNEL_ID = "aika_microphone_channel"
        private const val NOTIF_ID = 7771
        const val ACTION_START = "com.aika.MIC_START"
        const val ACTION_STOP = "com.aika.MIC_STOP"

        var isActive = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
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
                    Log.e(TAG, "RECORD_AUDIO not granted — cannot start")
                    stopSelf()
                    return START_NOT_STICKY
                }
                try {
                    startForegroundWithMicrophoneType()
                    acquireWakeLock()
                    acquireAudioFocus()
                    setupPhoneStateListener()
                    isActive = true
                    isPaused = false
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start: ${e.message}")
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
        try { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null } catch (e: Exception) {}
    }

    private fun acquireAudioFocus() {
        try {
            audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener { focusChange ->
                        when (focusChange) {
                            AudioManager.AUDIOFOCUS_LOSS -> {
                                Log.w(TAG, "AudioFocus LOST — retrying")
                                handler.postDelayed({ reAcquireAudioFocus() }, 1000)
                            }
                            AudioManager.AUDIOFOCUS_GAIN -> Log.d(TAG, "AudioFocus GAINED")
                        }
                    }
                    .build()
                audioManager?.requestAudioFocus(focusRequest!!)
            }
        } catch (e: Exception) { Log.e(TAG, "AudioFocus error: ${e.message}") }
    }

    private fun reAcquireAudioFocus() {
        if (isPaused) return
        try { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) { focusRequest?.let { audioManager?.requestAudioFocus(it) } } } catch (_: Exception) {}
    }

    private fun abandonAudioFocus() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) { focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) } }
            else { audioManager?.abandonAudioFocus(null) }
        } catch (_: Exception) {}
    }

    private fun setupPhoneStateListener() {
        try {
            telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            telephonyManager?.listen(object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    when (state) {
                        TelephonyManager.CALL_STATE_IDLE -> { if (isPaused) { isPaused = false; reAcquireAudioFocus() } }
                        TelephonyManager.CALL_STATE_RINGING, TelephonyManager.CALL_STATE_OFFHOOK -> { isPaused = true; abandonAudioFocus() }
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
        abandonAudioFocus()
        releaseWakeLock()
        try { telephonyManager?.listen(null, PhoneStateListener.LISTEN_CALL_STATE) } catch (_: Exception) {}
        isActive = false; isPaused = false
    }

    override fun onDestroy() { releaseAll(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
