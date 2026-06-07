package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * AikaVoiceService — фоновое прослушивание wake word как у Gemini / Google Assistant.
 *
 * Работает как Foreground Service → не убивается системой.
 * Использует нативный Android SpeechRecognizer — не конфликтует с Flutter STT.
 * Когда слышит wake word → шлёт событие во Flutter через EventChannel.
 *
 * Архитектура:
 *   Flutter → MethodChannel("aika/voice_bg") → startService / stopService
 *   Service → EventChannel("aika/voice_events") → onWakeWord / onPartial / onError
 */
class AikaVoiceService : Service() {

    companion object {
        const val ACTION_START    = "aika.voice.START"
        const val ACTION_STOP     = "aika.voice.STOP"
        const val ACTION_TRIGGERS = "aika.voice.SET_TRIGGERS"
        const val EXTRA_TRIGGERS  = "triggers"

        private const val CHANNEL_ID  = "aika_voice_bg"
        private const val NOTIF_ID    = 4242
        private const val TAG         = "AikaVoice"

        @Volatile var isRunning = false
        @Volatile var eventSink: EventChannel.EventSink? = null
        @Volatile var instance: AikaVoiceService? = null

        // Триггеры, которые слушаем в фоне
        var triggers: List<String> = listOf("айка", "aika", "aivora", "эй айка")
    }

    private var recognizer: SpeechRecognizer? = null
    private var restartHandler: android.os.Handler? = null
    private var restartRunnable: Runnable? = null
    private var paused = false
    private var consecutiveErrors = 0

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        AikaVoiceService.instance = this
        super.onCreate()
        restartHandler = android.os.Handler(mainLooper)
        Log.d(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val newTriggers = intent.getStringArrayListExtra(EXTRA_TRIGGERS)
                if (!newTriggers.isNullOrEmpty()) {
                    triggers = newTriggers
                }
                startForegroundCompat()
                if (!isRunning) {
                    isRunning = true
                    startRecognition()
                }
                Log.d(TAG, "▶ started, triggers=$triggers")
            }
            ACTION_STOP -> {
                stopSelf()
            }
            ACTION_TRIGGERS -> {
                val newTriggers = intent.getStringArrayListExtra(EXTRA_TRIGGERS)
                if (!newTriggers.isNullOrEmpty()) {
                    triggers = newTriggers
                    Log.d(TAG, "triggers updated: $triggers")
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        AikaVoiceService.instance = null
        isRunning = false
        paused = false
        restartHandler?.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        Log.d(TAG, "■ destroyed")
        super.onDestroy()
    }

    // ── Foreground notification ───────────────────────────────────────────────

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Айка слушает",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Фоновое прослушивание wake word"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Айка активна")
            .setContentText("Скажите «Айка» чтобы активировать")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pi)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    // ── SpeechRecognizer setup ────────────────────────────────────────────────

    private fun startRecognition() {
        if (!isRunning) return
        if (paused) {
            scheduleRestart(2000)
            return
        }

        // Уничтожаем старый распознаватель
        recognizer?.destroy()
        recognizer = null

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(TAG, "SpeechRecognizer не доступен")
            sendEvent("error", "STT unavailable")
            scheduleRestart(5000)
            return
        }

        recognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(createListener())
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_ALSO_RECOGNIZE_SPEECH_IN_LANGUAGES, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 300L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1000L)
        }

        try {
            recognizer?.startListening(intent)
            consecutiveErrors = 0
            Log.d(TAG, "🎤 startListening")
        } catch (e: Exception) {
            Log.e(TAG, "startListening exception: ${e.message}")
            scheduleRestart(2000)
        }
    }

    private fun createListener() = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "onReadyForSpeech")
            sendEvent("ready", "")
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val partial = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull() ?: return
            val text = partial.lowercase(Locale.getDefault()).trim()
            if (text.isNotEmpty()) {
                sendEvent("partial", text)
                checkForWakeWord(text)
            }
        }

        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return
            for (match in matches) {
                val text = match.lowercase(Locale.getDefault()).trim()
                Log.d(TAG, "onResults: $text")
                sendEvent("partial", text)
                if (checkForWakeWord(text)) return
            }
            // Не обнаружили — перезапускаем
            scheduleRestart(300)
        }

        override fun onError(error: Int) {
            val msg = errorMessage(error)
            Log.w(TAG, "onError: $msg ($error)")
            consecutiveErrors++
            val delay = when {
                error == SpeechRecognizer.ERROR_NO_MATCH    -> 300L
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 200L
                error == SpeechRecognizer.ERROR_AUDIO       -> 1000L
                consecutiveErrors > 5                        -> 3000L
                else -> 500L
            }
            scheduleRestart(delay)
        }

        override fun onBeginningOfSpeech() { sendEvent("speech_start", "") }
        override fun onEndOfSpeech()       { /* будет onResults или onError */ }
        override fun onRmsChanged(rmsdB: Float) { sendEvent("rms", rmsdB.toString()) }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    // ── Wake word detection ───────────────────────────────────────────────────

    /** Возвращает true если wake word обнаружен → останавливает цикл */
    private fun checkForWakeWord(text: String): Boolean {
        val normalized = text.lowercase().trim()
        for (trigger in triggers) {
            if (containsFuzzy(normalized, trigger)) {
                Log.d(TAG, "✅ Wake word: '$trigger' in '$normalized'")
                sendEvent("wake_word", trigger)
                // Пауза — Flutter STT возьмёт управление
                pauseListening()
                return true
            }
        }
        return false
    }

    /** Нечёткий поиск — обрабатывает опечатки / акценты */
    private fun containsFuzzy(text: String, trigger: String): Boolean {
        if (text.contains(trigger)) return true
        // Замены STT-артефактов
        val sttFixes = mapOf(
            "айка" to listOf("аика", "ais", "auca", "айко", "айки", "айке", "aiка"),
            "aika" to listOf("eika", "ayка", "ейка"),
            "aivora" to listOf("авора", "aivora", "aivorra")
        )
        val aliases = sttFixes[trigger] ?: emptyList()
        for (alias in aliases) {
            if (text.contains(alias)) return true
        }
        return false
    }

    // ── Pause/Resume (вызывается через MethodChannel) ─────────────────────────

    fun pauseListening() {
        paused = true
        restartHandler?.removeCallbacksAndMessages(null)
        try {
            recognizer?.stopListening()
        } catch (_: Exception) {}
        Log.d(TAG, "⏸ paused")
    }

    fun resumeListening() {
        if (!isRunning) return
        paused = false
        scheduleRestart(500)
        Log.d(TAG, "▶ resumed")
    }

    // ── Restart loop ──────────────────────────────────────────────────────────

    private fun scheduleRestart(delayMs: Long) {
        if (!isRunning) return
        restartHandler?.removeCallbacksAndMessages(null)
        restartRunnable = Runnable {
            if (isRunning && !paused) startRecognition()
        }
        restartHandler?.postDelayed(restartRunnable!!, delayMs)
    }

    // ── Event → Flutter ───────────────────────────────────────────────────────

    private fun sendEvent(type: String, data: String) {
        val sink = eventSink ?: return
        mainLooper.let { looper ->
            android.os.Handler(looper).post {
                try {
                    sink.success(mapOf("type" to type, "data" to data))
                } catch (e: Exception) {
                    Log.w(TAG, "sendEvent failed: ${e.message}")
                }
            }
        }
    }

    private fun errorMessage(error: Int) = when (error) {
        SpeechRecognizer.ERROR_AUDIO                  -> "audio"
        SpeechRecognizer.ERROR_CLIENT                 -> "client"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "no_perms"
        SpeechRecognizer.ERROR_NETWORK                -> "network"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT        -> "network_timeout"
        SpeechRecognizer.ERROR_NO_MATCH               -> "no_match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY        -> "busy"
        SpeechRecognizer.ERROR_SERVER                 -> "server"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT         -> "timeout"
        else -> "unknown_$error"
    }
}
