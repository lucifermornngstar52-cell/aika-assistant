package com.aika.assistant

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Непрерывный VAD (Voice Activity Detector) на базе AudioRecord.
 * Микрофон открыт ПОСТОЯННО — нет никаких циклов или перезапусков.
 *
 * Принцип:
 *  1. Читаем PCM 16-bit 16kHz в фоновом потоке
 *  2. Считаем RMS каждых 20ms чанка
 *  3. Если RMS > порог — речь активна
 *  4. После определённого количества активных чанков — fire onSpeechStart
 *  5. После тишины — fire onSpeechEnd (с буфером последних слов)
 *
 * Flutter получает события через EventChannel.
 */
class ContinuousVadService(private val eventSink: EventChannel.EventSink?) {

    companion object {
        private const val TAG = "ContinuousVAD"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        private const val FORMAT = AudioFormat.ENCODING_PCM_16BIT
        // 20ms чанк = 320 сэмплов
        private const val CHUNK_SIZE = 320
        private const val BUFFER_SIZE_CHUNKS = 50 // буфер 1 секунда

        // Порог RMS — речь vs тишина (0..32768)
        // ~300 = тихая речь, ~600 = нормальный разговор, ~1200 = громко
        private const val RMS_THRESHOLD = 400.0

        // Сколько активных чанков подряд = начало речи (3 * 20ms = 60ms)
        private const val SPEECH_START_CHUNKS = 3
        // Сколько тихих чанков подряд = конец речи (25 * 20ms = 500ms)
        private const val SPEECH_END_CHUNKS = 25
    }

    private var audioRecord: AudioRecord? = null
    private val isRunning = AtomicBoolean(false)
    private val isPaused = AtomicBoolean(false)
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var speechActive = false
    private var activeChunks = 0
    private var silenceChunks = 0

    @SuppressLint("MissingPermission")
    fun start() {
        if (isRunning.get()) return
        Log.d(TAG, "▶ Запуск непрерывного VAD")

        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, FORMAT)
        val bufSize = maxOf(minBuf, CHUNK_SIZE * BUFFER_SIZE_CHUNKS * 2)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            CHANNEL,
            FORMAT,
            bufSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord не инициализирован!")
            sendEvent("error", "AudioRecord init failed")
            return
        }

        audioRecord?.startRecording()
        isRunning.set(true)
        speechActive = false
        activeChunks = 0
        silenceChunks = 0

        job = scope.launch {
            val buffer = ShortArray(CHUNK_SIZE)
            sendEvent("status", "started")
            Log.d(TAG, "Микрофон открыт — непрерывное прослушивание")

            while (isRunning.get() && isActive) {
                val read = audioRecord?.read(buffer, 0, CHUNK_SIZE) ?: break
                if (read <= 0) continue

                // Если на паузе — читаем буфер но не обрабатываем (микрофон остаётся открытым!)
                // НЕ сбрасываем счётчики — это вызывало ложные события при возобновлении
                if (isPaused.get()) continue

                val rms = calculateRms(buffer, read)

                if (rms > RMS_THRESHOLD) {
                    silenceChunks = 0
                    activeChunks++

                    if (!speechActive && activeChunks >= SPEECH_START_CHUNKS) {
                        speechActive = true
                        Log.d(TAG, "🎤 Речь началась (RMS=${"%.0f".format(rms)})")
                        sendEvent("speech_start", rms.toString())
                    }
                } else {
                    activeChunks = 0
                    if (speechActive) {
                        silenceChunks++
                        if (silenceChunks >= SPEECH_END_CHUNKS) {
                            speechActive = false
                            silenceChunks = 0
                            Log.d(TAG, "🔇 Речь закончилась")
                            sendEvent("speech_end", "")
                        }
                    }
                }
            }
        }
    }

    // pauseType:
    //   "command"  — пауза на время ответа Айки (микрофон остаётся открытым)
    //   "media"    — играет музыка/видео (микрофон полностью закрывается)
    private var pauseType: String = "command"

    fun pause(type: String = "command") {
        pauseType = type
        isPaused.set(true)
        speechActive = false
        activeChunks = 0
        silenceChunks = 0

        if (type == "media") {
            // Полностью закрываем микрофон — экономим батарею и не реагируем на фон
            Log.d(TAG, "⏸ VAD ОСТАНОВЛЕН (медиа) — микрофон закрыт")
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            isRunning.set(false)
            sendEvent("status", "mic_off")
        } else {
            // Просто игнорируем результаты — микрофон открыт
            Log.d(TAG, "⏸ VAD пауза (команда) — микрофон открыт")
            sendEvent("status", "paused")
        }
    }

    fun resume() {
        val wasMedia = pauseType == "media"
        pauseType = "command"
        isPaused.set(false)

        if (wasMedia) {
            // Нужно заново открыть микрофон
            Log.d(TAG, "▶ VAD возобновление после медиа — перезапускаем микрофон")
            sendEvent("status", "mic_on")
            start() // полный перезапуск AudioRecord
        } else {
            Log.d(TAG, "▶ VAD возобновление после команды")
            sendEvent("status", "resumed")
        }
    }

    fun stop() {
        Log.d(TAG, "⏹ VAD остановлен")
        isRunning.set(false)
        isPaused.set(false)
        job?.cancel()
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        sendEvent("status", "stopped")
    }

    fun setThreshold(value: Double) {
        // Можно расширить — пока порог захардкожен
        Log.d(TAG, "Порог обновлён: $value")
    }

    private fun calculateRms(buffer: ShortArray, size: Int): Double {
        var sum = 0.0
        for (i in 0 until size) {
            val sample = buffer[i].toDouble()
            sum += sample * sample
        }
        return Math.sqrt(sum / size)
    }

    private fun sendEvent(type: String, data: String) {
        // EventSink должен вызываться на main thread
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }
}
