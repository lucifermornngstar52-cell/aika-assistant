package com.aika.assistant

import android.util.Log

/**
 * AikaAudioBridge — мост между нативным AudioRecord (AikaMicrophoneService)
 * и Flutter (EventChannel).
 *
 * Когда VAD в AudioRecord detects речь → onSpeechDetected вызывается.
 * Flutter получает событие, запускает speech_to_text для распознавания,
 * затем отправляет ACTION_STT_DONE обратно в сервис → AudioRecord resume.
 */
object AikaAudioBridge {
    private const val TAG = "AikaAudioBridge"

    // Колбэк который Flutter регистрирует через EventChannel
    @Volatile
    var onSpeechDetected: (() -> Unit)? = null

    // Статистика для логирования
    @Volatile
    var detectionCount: Int = 0
        private set

    @Volatile
    var lastDetectionTime: Long = 0
        private set

    fun notifySpeechDetected() {
        detectionCount++
        lastDetectionTime = System.currentTimeMillis()
        Log.d(TAG, "Speech detected #$detectionCount at $lastDetectionTime")
        onSpeechDetected?.invoke()
    }
}
