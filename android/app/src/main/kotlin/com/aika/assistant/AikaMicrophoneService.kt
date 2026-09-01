package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log

/**
 * AikaMicrophoneService — Foreground Service с типом microphone.
 *
 * Что делает:
 * 1. foregroundServiceType="microphone" → Android НЕ глушит микрофон в фоне
 * 2. WakeLock (PARTIAL_WAKE_LOCK) → CPU не спит когда экран выключен
 * 3. AudioFocus (AUDIOFOCUS_GAIN) → музыка не может забрать микрофон
 * 4. PhoneStateListener → глушит микрофон ТОЛЬКО при звонках и записи ГС
 *
 * Музыка НЕ глушит микрофон — AudioFocus держится нами.
 * Звонки и запись голосовых сообщений — глушат (системно).
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
    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var telephonyManager: TelephonyManager? = null
    private var isPaused = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                Log.d(TAG, "START — foreground microphone service")
                startForegroundWithMicrophoneType()
                acquireWakeLock()
                acquireAudioFocus()
                setupPhoneStateListener()
                isActive = true
                isPaused = false
            }
            ACTION_STOP -> {
                Log.d(TAG, "STOP")
                releaseAll()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_PAUSE -> {
                Log.d(TAG, "PAUSE — phone call or voice recording")
                isPaused = true
                // Отдаём AudioFocus временно — система/мессенджер заберёт mic
                abandonAudioFocus()
            }
            ACTION_RESUME -> {
                Log.d(TAG, "RESUME — call/recording ended")
                isPaused = false
                reAcquireAudioFocus()
            }
        }
        return START_STICKY
    }

    // ── Foreground с типом microphone (Android 10+) ──────────────
    private fun startForegroundWithMicrophoneType() {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ — нужен точный тип
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10-13
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    // ── WakeLock — CPU не спит когда экран выключен ────────────────
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aika:MicrophoneWakeLock")
        wakeLock?.setReferenceCounted(false)
        wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24 часа max, обновляем при необходимости
        Log.d(TAG, "WakeLock acquired (PARTIAL_WAKE_LOCK)")
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            Log.d(TAG, "WakeLock released")
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock release error: ${e.message}")
        }
    }

    // ── AudioFocus — держим микрофон, музыка не перехватывает ─────
    private fun acquireAudioFocus() {
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
                            Log.w(TAG, "AudioFocus LOST — trying to regain")
                            // Пытаемся вернуть фокус
                            handler.postDelayed({ reAcquireAudioFocus() }, 1000)
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            Log.d(TAG, "AudioFocus transient loss")
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            Log.d(TAG, "AudioFocus loss can duck — ignoring (keep mic)")
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            Log.d(TAG, "AudioFocus GAINED — mic active")
                        }
                    }
                }
                .build()

            val result = audioManager?.requestAudioFocus(focusRequest!!)
            Log.d(TAG, "AudioFocus request result: $result")
        } else {
            // Pre-Oreo
            val result = audioManager?.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN
            )
            Log.d(TAG, "AudioFocus (legacy) result: $result")
        }
    }

    private fun reAcquireAudioFocus() {
        if (isPaused) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { req ->
                val result = audioManager?.requestAudioFocus(req)
                Log.d(TAG, "AudioFocus re-acquire result: $result")
            }
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { req ->
                audioManager?.abandonAudioFocusRequest(req)
                Log.d(TAG, "AudioFocus abandoned (pause)")
            }
        } else {
            audioManager?.abandonAudioFocus(null)
        }
    }

    // ── PhoneStateListener — глушим при звонках ───────────────────
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    private fun setupPhoneStateListener() {
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        telephonyManager?.listen(object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                when (state) {
                    TelephonyManager.CALL_STATE_IDLE -> {
                        Log.d(TAG, "Phone: IDLE — resume mic")
                        if (isPaused) {
                            isPaused = false
                            reAcquireAudioFocus()
                        }
                    }
                    TelephonyManager.CALL_STATE_RINGING -> {
                        Log.d(TAG, "Phone: RINGING — pause mic")
                        isPaused = true
                        abandonAudioFocus()
                    }
                    TelephonyManager.CALL_STATE_OFFHOOK -> {
                        Log.d(TAG, "Phone: OFFHOOK — pause mic")
                        isPaused = true
                        abandonAudioFocus()
                    }
                }
            }
        }, PhoneStateListener.LISTEN_CALL_STATE)
    }

    // ── Notification (обязательно для Foreground Service) ─────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Aika Microphone",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Микрофон активен для wake word"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Aika слушает")
            .setContentText("Микрофон активен — wake word работает")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    // ── Cleanup ───────────────────────────────────────────────────
    private fun releaseAll() {
        abandonAudioFocus()
        releaseWakeLock()
        telephonyManager?.listen(null, PhoneStateListener.LISTEN_CALL_STATE)
        isActive = false
        isPaused = false
    }

    override fun onDestroy() {
        releaseAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
