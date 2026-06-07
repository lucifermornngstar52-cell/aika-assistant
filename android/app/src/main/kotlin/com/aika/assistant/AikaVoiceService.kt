package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors

/**
 * AikaVoiceService — фоновое прослушивание wake word (Gemini-style).
 *
 * Ключевые особенности:
 * 1. Foreground Service — не убивается системой даже с заблокированным экраном
 * 2. Нативный SpeechRecognizer — не конфликтует с Flutter speech_to_text
 * 3. PREFER_OFFLINE — Android 13+ on-device recognition, работает без интернета
 * 4. Fuzzy matching — "аика","аико","айки","eika" → все распознаются
 * 5. Auto-restart — бесконечный цикл с умной задержкой при ошибках
 * 6. Pause/Resume — Flutter STT берёт микрофон пока сервис ждёт
 */
class AikaVoiceService : Service() {

    companion object {
        const val ACTION_START    = "aika.voice.START"
        const val ACTION_STOP     = "aika.voice.STOP"
        const val ACTION_TRIGGERS = "aika.voice.SET_TRIGGERS"
        const val EXTRA_TRIGGERS  = "triggers"

        private const val CHANNEL_ID = "aika_voice_bg"
        private const val NOTIF_ID   = 4242
        private const val TAG        = "AikaVoice"

        @Volatile var isRunning  = false
        @Volatile var instance: AikaVoiceService? = null
        @Volatile var eventSink: EventChannel.EventSink? = null

        var triggers: List<String> = listOf("айка", "aika", "aivora", "эй айка", "окей айка")
    }

    private var recognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var restartRunnable: Runnable? = null
    private var paused = false
    private var consecutiveErrors = 0
    private var useOnDevice = false  // включается если устройство поддерживает

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        checkOnDeviceSupport()
        Log.d(TAG, "onCreate, onDevice=$useOnDevice")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val newTriggers = intent.getStringArrayListExtra(EXTRA_TRIGGERS)
                if (!newTriggers.isNullOrEmpty()) triggers = newTriggers
                startForegroundCompat()
                if (!isRunning) {
                    isRunning = true
                    startRecognition()
                }
                Log.d(TAG, "▶ started, triggers=$triggers, onDevice=$useOnDevice")
            }
            ACTION_STOP -> stopSelf()
            ACTION_TRIGGERS -> {
                val newTriggers = intent.getStringArrayListExtra(EXTRA_TRIGGERS)
                if (!newTriggers.isNullOrEmpty()) triggers = newTriggers
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        mainHandler.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        Log.d(TAG, "■ destroyed")
        super.onDestroy()
    }

    // ── On-device support check ───────────────────────────────────────────────

    private fun checkOnDeviceSupport() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val executor = Executors.newSingleThreadExecutor()
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)?.also { sr ->
                    sr.checkRecognitionSupport(
                        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH),
                        executor,
                        object : RecognitionSupportCallback {
                            override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                                useOnDevice = recognitionSupport.installedOnDeviceLanguages
                                    .any { it.startsWith("ru") || it.startsWith("en") }
                                Log.d(TAG, "On-device support: $useOnDevice, langs=${recognitionSupport.installedOnDeviceLanguages}")
                                sr.destroy()
                            }
                            override fun onError(error: Int) {
                                Log.d(TAG, "On-device check error: $error")
                                sr.destroy()
                            }
                        }
                    )
                }
            } catch (e: Exception) {
                Log.d(TAG, "On-device check exception: ${e.message}")
            }
        }
    }

    // ── Foreground notification ───────────────────────────────────────────────

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Айка слушает",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Фоновое прослушивание wake word"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val pi = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val offlineTag = if (useOnDevice) " • офлайн" else ""
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Айка активна$offlineTag")
            .setContentText("Скажите «Айка» чтобы активировать")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pi)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    // ── SpeechRecognizer ─────────────────────────────────────────────────────

    private fun startRecognition() {
        if (!isRunning || paused) {
            if (paused) scheduleRestart(2000)
            return
        }

        mainHandler.post {
            try {
                recognizer?.destroy()
                recognizer = createRecognizer()
                recognizer?.setRecognitionListener(buildListener())

                val intent = buildRecognitionIntent()
                recognizer?.startListening(intent)
                consecutiveErrors = 0
                Log.d(TAG, "🎤 startListening")
            } catch (e: Exception) {
                Log.e(TAG, "startListening failed: ${e.message}")
                scheduleRestart(2000)
            }
        }
    }

    private fun createRecognizer(): SpeechRecognizer {
        // Prefer on-device recognizer for offline support (Android 13+)
        return if (useOnDevice && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                    ?: SpeechRecognizer.createSpeechRecognizer(this)
            } catch (_: Exception) {
                SpeechRecognizer.createSpeechRecognizer(this)
            }
        } else {
            SpeechRecognizer.createSpeechRecognizer(this)
        }
    }

    private fun buildRecognitionIntent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
        // Мультиязычность — ru + en одновременно
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_SWITCH_INITIAL_ACTIVE_DURATION_TIME_MILLIS, 1000)
        }
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
        // Предпочитать офлайн (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, useOnDevice)
        }
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 300L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1000L)
    }

    private fun buildListener() = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            sendEvent("ready", "")
            Log.v(TAG, "ready")
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val texts = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return
            for (text in texts) {
                val t = text.lowercase().trim()
                if (t.isNotEmpty()) {
                    sendEvent("partial", t)
                    if (checkWakeWord(t)) return
                }
            }
        }

        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: run {
                scheduleRestart(300)
                return
            }
            for (match in matches) {
                val t = match.lowercase().trim()
                Log.d(TAG, "result: $t")
                if (checkWakeWord(t)) return
            }
            scheduleRestart(300)
        }

        override fun onError(error: Int) {
            consecutiveErrors++
            val delay = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH       -> 200L
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> 200L
                SpeechRecognizer.ERROR_AUDIO          -> 800L
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 1000L
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> if (useOnDevice) 500L else 3000L
                else -> if (consecutiveErrors > 5) 3000L else 500L
            }
            Log.v(TAG, "error #$consecutiveErrors: $error delay=${delay}ms")
            scheduleRestart(delay)
        }

        override fun onBeginningOfSpeech() { sendEvent("speech_start", "") }
        override fun onEndOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) { sendEvent("rms", rmsdB.toString()) }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    // ── Wake word detection ───────────────────────────────────────────────────

    private fun checkWakeWord(text: String): Boolean {
        for (trigger in triggers) {
            if (fuzzyContains(text, trigger)) {
                Log.d(TAG, "✅ wake word '$trigger' в '$text'")
                sendEvent("wake_word", trigger)
                pauseListening()
                return true
            }
        }
        return false
    }

    /**
     * Нечёткое сравнение — обрабатывает STT-артефакты и опечатки.
     * Расстояние Левенштейна для коротких слов.
     */
    private fun fuzzyContains(text: String, trigger: String): Boolean {
        if (text.contains(trigger)) return true

        // Словарь STT-вариантов
        val variants = mapOf(
            "айка"   to listOf("аика", "айка", "айко", "айки", "айке", "aika", "auca", "эйка"),
            "aika"   to listOf("eika", "auca", "айка", "ейка", "ayка"),
            "aivora" to listOf("авора", "айвора", "aivorra", "аивора"),
        )
        val aliases = variants[trigger] ?: emptyList()
        if (aliases.any { text.contains(it) }) return true

        // Левенштейн для слов (если trigger короткий)
        if (trigger.length <= 6) {
            val words = text.split(" ", ",", ".", "!")
            for (word in words) {
                if (word.length >= trigger.length - 1 &&
                    levenshtein(word, trigger) <= 1) return true
            }
        }
        return false
    }

    private fun levenshtein(a: String, b: String): Int {
        val m = a.length; val n = b.length
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in 0..m) dp[i][0] = i
        for (j in 0..n) dp[0][j] = j
        for (i in 1..m) for (j in 1..n) {
            dp[i][j] = if (a[i-1] == b[j-1]) dp[i-1][j-1]
            else 1 + minOf(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
        }
        return dp[m][n]
    }

    // ── Pause / Resume ────────────────────────────────────────────────────────

    fun pauseListening() {
        paused = true
        mainHandler.removeCallbacksAndMessages(null)
        mainHandler.post {
            try { recognizer?.stopListening() } catch (_: Exception) {}
        }
        Log.d(TAG, "⏸ paused")
    }

    fun resumeListening() {
        if (!isRunning) return
        paused = false
        scheduleRestart(600)
        Log.d(TAG, "▶ resumed")
    }

    // ── Restart ───────────────────────────────────────────────────────────────

    private fun scheduleRestart(delayMs: Long) {
        if (!isRunning) return
        mainHandler.removeCallbacksAndMessages(null)
        restartRunnable = Runnable {
            if (isRunning && !paused) startRecognition()
        }
        mainHandler.postDelayed(restartRunnable!!, delayMs)
    }

    // ── Events → Flutter ─────────────────────────────────────────────────────

    private fun sendEvent(type: String, data: String) {
        val sink = eventSink ?: return
        mainHandler.post {
            try { sink.success(mapOf("type" to type, "data" to data)) }
            catch (e: Exception) { Log.w(TAG, "sendEvent: ${e.message}") }
        }
    }
}
