package com.aika.assistant

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log

/**
 * AikaMicrophoneService — нативный AudioRecord + VAD + wake word detection.
 *
 * Архитектура:
 *
 *   Foreground Service (type=microphone)
 *          │
 *          ▼
 *      AudioRecord
 *          │ PCM 16-bit, 16kHz, mono
 *          ▼
 *      read() в цикле
 *          │
 *          ├── read > 0 → VAD (energy threshold)
 *          │                ├── speech detected → EventChannel → Flutter STT
 *          │                └── silence → продолжаем
 *          │
 *          ├── read <= 0 / exception → release() → createRecorder() → startRecording()
 *          │
 *          └── 60сек таймер → профилактический recreate AudioRecord
 *
 * Логирование на каждом шаге для диагностики ~300сек проблемы.
 *
 * WakeLock — только как страховка для CPU, не как решение проблемы микрофона.
 * AudioFocus — НЕ используем (не решает проблему микрофона).
 */
class AikaMicrophoneService : Service() {

    companion object {
        private const val TAG = "AikaMic"
        private const val CHANNEL_ID = "aika_microphone_channel"
        private const val NOTIF_ID = 7771

        // AudioRecord параметры
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val CHUNK_SIZE = 1024  // сэмплов за read()

        // VAD параметры
        private const val VAD_ENERGY_THRESHOLD = 800.0  // RMS порог речи
        private const val VAD_SILENCE_FRAMES = 30       // ~2 сек тишины → конец речи
        private const val VAD_SPEECH_FRAMES = 5         // ~0.3 сек речи → начало речи
        private const val SESSION_MAX_MS = 60_000L      // 60 сек → recreate AudioRecord

        // Restart
        private const val RESTART_DELAY_MS = 1_000L
        private const val HEARTBEAT_INTERVAL_MS = 60_000L

        const val ACTION_START = "com.aika.MIC_START"
        const val ACTION_STOP = "com.aika.MIC_STOP"
        const val ACTION_PAUSE = "com.aika.MIC_PAUSE"
        const val ACTION_RESUME = "com.aika.MIC_RESUME"
        const val ACTION_HEARTBEAT = "com.aika.MIC_HEARTBEAT"
        const val ACTION_RESTART = "com.aika.MIC_RESTART"
        const val ACTION_STT_DONE = "com.aika.MIC_STT_DONE"  // Flutter закончил STT → возобновить AudioRecord

        var isActive = false
            private set

        // EventSink для EventChannel — статический, чтобы Flutter мог читать
        @Volatile
        var eventSink: android.os.Parcel? = null  // не используется напрямую
    }

    // ─── Состояние ───────────────────────────────────────────────────

    private var wakeLock: PowerManager.WakeLock? = null
    private var telephonyManager: TelephonyManager? = null
    private var isPaused = false
    private val handler = Handler(Looper.getMainLooper())

    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    @Volatile private var serviceRunning = false
    @Volatile private var listeningForWakeWord = true  // false когда Flutter делает STT

    // VAD state
    private var vadSpeechCounter = 0
    private var vadSilenceCounter = 0
    private var isInSpeech = false
    private var speechStartMs = 0L

    // Session timing
    private var sessionStartMs = 0L
    private var totalReads = 0L
    private var totalBytes = 0L
    private var recreateCount = 0

    // Статический колбэк для EventChannel
    companion object {
        // ... (остальные константы выше)
    }

    // ─── Lifecycle ───────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_RESTART, null -> {
                if (intent?.action == ACTION_RESTART) {
                    Log.d(TAG, "RESTART (from AlarmManager)")
                }
                if (intent?.action == ACTION_HEARTBEAT && isActive) {
                    Log.d(TAG, "Heartbeat — service alive ✓")
                    scheduleHeartbeat()
                    return START_STICKY
                }
                if (!hasMicPermission()) {
                    Log.e(TAG, "RECORD_AUDIO not granted")
                    scheduleRestart()
                    return START_STICKY
                }
                try {
                    startForegroundWithMicrophoneType()
                    acquireWakeLock()
                    setupPhoneStateListener()
                    scheduleHeartbeat()
                    isActive = true
                    isPaused = false
                    startAudioLoop()
                    Log.d(TAG, "✅ Started — AudioRecord loop launched")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start: ${e.message}")
                    scheduleRestart()
                    return START_STICKY
                }
            }
            ACTION_STOP -> {
                Log.d(TAG, "STOP (explicit)")
                stopAudioLoop()
                cancelHeartbeat()
                releaseAll()
                try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                Log.d(TAG, "PAUSE — call/voice recording")
                isPaused = true
                stopAudioLoop()
            }
            ACTION_RESUME -> {
                Log.d(TAG, "RESUME")
                isPaused = false
                startAudioLoop()
            }
            ACTION_STT_DONE -> {
                // Flutter закончил распознавание речи → возобновляем AudioRecord
                Log.d(TAG, "STT done — resuming AudioRecord")
                listeningForWakeWord = true
                // Пересоздаём AudioRecord (не переиспользуем старый)
                restartAudioRecord()
            }
            ACTION_HEARTBEAT -> {
                Log.d(TAG, "Heartbeat — service alive ✓")
                scheduleHeartbeat()
            }
        }
        return START_STICKY
    }

    // ─── AudioRecord — создание и lifecycle ──────────────────────────

    private fun createRecorder(): AudioRecord {
        val minBufSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        val bufferSize = (minBufSize * 2).coerceAtLeast(CHUNK_SIZE * 4)

        Log.d(TAG, "AudioRecord created — sampleRate=$SAMPLE_RATE bufSize=$bufferSize minBuf=$minBufSize")

        return AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize
        )
    }

    private fun startAudioLoop() {
        if (audioThread?.isAlive == true) {
            Log.d(TAG, "Audio loop already running")
            return
        }
        serviceRunning = true
        listeningForWakeWord = true

        audioThread = Thread { audioLoop() }.apply {
            name = "AikaAudioLoop"
            isDaemon = true
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun stopAudioLoop() {
        serviceRunning = false
        listeningForWakeWord = false
        try {
            audioThread?.join(1000)
        } catch (_: Exception) {}
        audioThread = null
        releaseAudioRecord()
    }

    private fun releaseAudioRecord() {
        try {
            audioRecord?.stop()
            Log.d(TAG, "AudioRecord stopped")
        } catch (e: Exception) {
            Log.d(TAG, "AudioRecord stop: ${e.message}")
        }
        try {
            audioRecord?.release()
            Log.d(TAG, "AudioRecord released")
        } catch (_: Exception) {}
        audioRecord = null
    }

    private fun restartAudioRecord() {
        Log.d(TAG, "🔄 restartAudioRecord — release + recreate (count=${++recreateCount})")
        releaseAudioRecord()
        // Пересоздаём в потоке
        if (serviceRunning && audioThread?.isAlive != true) {
            startAudioLoop()
        }
    }

    /**
     * Главный цикл AudioRecord.
     *
     * Ключевая логика:
     *   while (serviceRunning) {
     *     recorder = createRecorder()
     *     recorder.startRecording()
     *     while (serviceRunning) {
     *       read = recorder.read(buffer, 0, buffer.size)
     *       if (read > 0) → VAD
     *       else → break (release + recreate)
     *     }
     *     recorder.release()
     *     sleep(300)
     *   }
     */
    private fun audioLoop() {
        Log.d(TAG, "🎧 Audio loop thread started")
        val buffer = ShortArray(CHUNK_SIZE)
        sessionStartMs = SystemClock.elapsedRealtime()
        totalReads = 0
        totalBytes = 0

        while (serviceRunning) {
            if (isPaused || !listeningForWakeWord) {
                // Ждём пока не скажут resume
                try { Thread.sleep(100) } catch (_: Exception) {}
                continue
            }

            var recorder: AudioRecord? = null

            try {
                recorder = createRecorder()
                audioRecord = recorder

                if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                    Log.e(TAG, "AudioRecord NOT initialized — state=${recorder.state}")
                    recorder.release()
                    Thread.sleep(500)
                    continue
                }

                recorder.startRecording()
                Log.d(TAG, "Recording started — session #${recreateCount}")

                // Внутренний цикл чтения
                var lastRecreateCheck = SystemClock.elapsedRealtime()

                while (serviceRunning && listeningForWakeWord && !isPaused) {
                    val read = recorder.read(buffer, 0, CHUNK_SIZE)

                    if (read > 0) {
                        totalReads++
                        totalBytes += read

                        // VAD — вычисляем RMS
                        val rms = calculateRMS(buffer, read)

                        if (rms > VAD_ENERGY_THRESHOLD) {
                            vadSpeechCounter++
                            vadSilenceCounter = 0

                            if (!isInSpeech && vadSpeechCounter >= VAD_SPEECH_FRAMES) {
                                isInSpeech = true
                                speechStartMs = SystemClock.elapsedRealtime()
                                Log.d(TAG, "🎤 Speech detected — RMS=$rms (reads=$totalReads, session=${(SystemClock.elapsedRealtime() - sessionStartMs) / 1000}s)")
                            }
                        } else {
                            vadSilenceCounter++
                            vadSpeechCounter = 0

                            if (isInSpeech && vadSilenceCounter >= VAD_SILENCE_FRAMES) {
                                val speechDuration = SystemClock.elapsedRealtime() - speechStartMs
                                isInSpeech = false
                                Log.d(TAG, "🔇 Speech ended — duration=${speechDuration}ms (reads=$totalReads)")

                                // Уведомляем Flutter — есть речь, запускай STT
                                notifyFlutterSpeechDetected()
                            }
                        }

                        // Профилактический recreate каждые 60 секунд
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastRecreateCheck >= SESSION_MAX_MS) {
                            Log.d(TAG, "⏱ 60s reached — preventive recreate (reads=$totalReads, bytes=$totalBytes)")
                            break  // выходим из внутреннего цикла → release + recreate
                        }

                    } else {
                        // read <= 0 — AudioRecord сломался
                        Log.e(TAG, "🔴 read=$read — AudioRecord broken! (reads=$totalReads, session=${(SystemClock.elapsedRealtime() - sessionStartMs) / 1000}s)")
                        Log.e(TAG, "   ERROR_INVALID_OPERATION=-3, ERROR_BAD_VALUE=-2, ERROR_DEAD_OBJECT=-6")

                        // НЕ пытаемся оживить — break → release → recreate
                        break
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "🔴 AudioRecord exception: ${e.message}")
                Log.e(TAG, "   Stack: ${e.stackTrace.take(3).joinToString(" | ")}")

            } finally {
                try {
                    recorder?.stop()
                    Log.d(TAG, "AudioRecord stopped (finally)")
                } catch (e: Exception) {
                    Log.d(TAG, "AudioRecord stop exception: ${e.message}")
                }
                try {
                    recorder?.release()
                    Log.d(TAG, "AudioRecord released (finally)")
                } catch (_: Exception) {}
                audioRecord = null
            }

            // Пауза перед пересозданием
            if (serviceRunning && listeningForWakeWord && !isPaused) {
                try {
                    Thread.sleep(300)
                } catch (_: Exception) {}
                // Сбрасываем session timer
                sessionStartMs = SystemClock.elapsedRealtime()
                totalReads = 0
                totalBytes = 0
            }
        }

        Log.d(TAG, "🎧 Audio loop thread ended")
    }

    private fun calculateRMS(buffer: ShortArray, count: Int): Double {
        var sum = 0.0
        for (i in 0 until count) {
            val v = buffer[i].toDouble()
            sum += v * v
        }
        return Math.sqrt(sum / count)
    }

    // ─── Flutter communication ───────────────────────────────────────

    /**
     * Уведомить Flutter что обнаружена речь.
     * Flutter запускает speech_to_text для распознавания.
     * После распознавания Flutter вызывает ACTION_STT_DONE.
     */
    private fun notifyFlutterSpeechDetected() {
        listeningForWakeWord = false  // временно停止 AudioRecord VAD
        Log.d(TAG, "→ Notifying Flutter: speech detected, pausing VAD")

        // Отправляем broadcast через статический eventSink
        try {
            val intent = Intent("com.aika.SPEECH_DETECTED")
                .setPackage(packageName)
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Broadcast failed: ${e.message}")
        }

        // Также используем прямой колбэк если доступен
        try {
            handler.post {
                AikaAudioBridge.onSpeechDetected?.invoke()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Bridge callback failed: ${e.message}")
        }
    }

    // ─── onTaskRemoved ───────────────────────────────────────────────

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "🚨 onTaskRemoved — restarting service")
        val restartIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
            action = ACTION_RESTART
            setPackage(packageName)
        }
        val pendingIntent = PendingIntent.getService(
            this, 1, restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + RESTART_DELAY_MS,
            pendingIntent
        )
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.d(TAG, "🚨 onDestroy — scheduling restart")
        stopAudioLoop()
        releaseAll()
        scheduleRestart()
        super.onDestroy()
    }

    private fun scheduleRestart() {
        try {
            val restartIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
                action = ACTION_RESTART
                setPackage(packageName)
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext, 0, restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + RESTART_DELAY_MS,
                pendingIntent
            )
            Log.d(TAG, "Restart scheduled in ${RESTART_DELAY_MS}ms")
        } catch (e: Exception) {
            Log.e(TAG, "scheduleRestart failed: ${e.message}")
        }
    }

    private fun scheduleHeartbeat() {
        try {
            val heartbeatIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
                action = ACTION_HEARTBEAT
                setPackage(packageName)
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext, 2, heartbeatIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + HEARTBEAT_INTERVAL_MS,
                pendingIntent
            )
        } catch (_: Exception) {}
    }

    private fun cancelHeartbeat() {
        try {
            val heartbeatIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
                action = ACTION_HEARTBEAT
                setPackage(packageName)
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext, 2, heartbeatIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pendingIntent != null) {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                alarmManager.cancel(pendingIntent)
            }
        } catch (_: Exception) {}
    }

    // ─── WakeLock (страховка для CPU, не решение проблемы микрофона) ──

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
            Log.e(TAG, "startForeground with type failed: ${e.message}")
            try { startForeground(NOTIF_ID, notification) } catch (e2: Exception) { throw e2 }
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aika:WakeWord")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
            Log.d(TAG, "WakeLock acquired (CPU insurance)")
        } catch (e: Exception) { Log.e(TAG, "WakeLock error: ${e.message}") }
    }

    private fun releaseWakeLock() {
        try { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null } catch (_: Exception) {}
    }

    // ─── PhoneState — глушить ТОЛЬКО при звонках ─────────────────────

    private fun setupPhoneStateListener() {
        try {
            telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            telephonyManager?.listen(object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    when (state) {
                        TelephonyManager.CALL_STATE_IDLE -> {
                            if (isPaused) {
                                isPaused = false
                                startAudioLoop()
                                Log.d(TAG, "Call ended — resume AudioRecord")
                            }
                        }
                        TelephonyManager.CALL_STATE_RINGING, TelephonyManager.CALL_STATE_OFFHOOK -> {
                            isPaused = true
                            stopAudioLoop()
                            Log.d(TAG, "Call active — pause AudioRecord")
                        }
                    }
                }
            }, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (e: Exception) { Log.e(TAG, "PhoneState error: ${e.message}") }
    }

    // ─── Notification ────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Aika Microphone", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Микрофон активен — прослушивание wake word"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
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
            .setContentText("Wake word active")
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .setShowWhen(false)
            .build()
    }

    // ─── Cleanup ─────────────────────────────────────────────────────

    private fun releaseAll() {
        cancelHeartbeat()
        releaseWakeLock()
        try { telephonyManager?.listen(null, PhoneStateListener.LISTEN_CALL_STATE) } catch (_: Exception) {}
        isActive = false
        isPaused = false
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
