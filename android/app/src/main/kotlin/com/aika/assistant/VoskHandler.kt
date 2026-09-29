package com.aika.assistant

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.SpeechService
import org.vosk.android.RecognitionListener
import java.io.File
import java.io.FileInputStream
import java.util.zip.ZipInputStream

/// Нативный Vosk STT для Pro-версии: оффлайн распознавание русской речи.
class VoskHandler {
    companion object {
        private const val TAG = "AikaVosk"
    }

    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var speechService: SpeechService? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    private fun sendEvent(type: String, text: String) {
        val s = sink ?: return
        val payload = mapOf("type" to type, "text" to text)
        main.post {
            try {
                s.success(payload)
            } catch (e: Exception) {
                Log.w(TAG, "event sink closed: ${e.message}")
            }
        }
    }

    private fun extractZipIfNeeded(zipPath: String, modelsDir: String) {
        val zip = File(zipPath)
        if (!zip.exists()) throw IllegalArgumentException("zip not found: $zipPath")
        val base = File(modelsDir)
        if (!base.exists()) base.mkdirs()
        // Уже распаковано?
        if (findModelRoot(base) != null) return
        ZipInputStream(FileInputStream(zip)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val outFile = File(base, entry.name)
                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStreamSafe(outFile).use { zis.copyTo(it) }
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
    }

    private fun FileOutputStreamSafe(f: File) = java.io.FileOutputStream(f)

    private fun findModelRoot(dir: File): File? {
        val conf = File(dir, "conf/model.conf")
        if (conf.exists()) return dir
        val subs = dir.listFiles { f -> f.isDirectory } ?: return null
        for (f in subs) {
            findModelRoot(f)?.let { return it }
        }
        return null
    }

    fun init(zipPath: String, modelsDir: String, result: MethodChannel.Result) {
        Thread {
            try {
                extractZipIfNeeded(zipPath, modelsDir)
                val root = findModelRoot(File(modelsDir))
                    ?: throw IllegalArgumentException("model dir not found in $modelsDir")
                val old = model
                if (old != null) {
                    try { old.close() } catch (_: Exception) {}
                }
                model = Model(root.absolutePath)
                recognizer = null
                Log.d(TAG, "Vosk model loaded: ${root.absolutePath}")
                main.post { result.success(root.absolutePath) }
            } catch (e: Exception) {
                Log.e(TAG, "init failed: ${e.message}")
                main.post { result.error("init_failed", e.message, null) }
            }
        }.start()
    }

    fun start(sink: EventChannel.EventSink, result: MethodChannel.Result) {
        val m = model
        if (m == null) {
            result.error("no_model", "Vosk not initialized", null)
            return
        }
        try {
            stopInternal()
            val rec = Recognizer(m, 16000.0f)
            recognizer = rec
            this.sink = sink
            val ss = SpeechService(rec, 16000.0f)
            speechService = ss
            val listener = object : RecognitionListener {
                override fun onPartialResult(partial: String?) {
                    val text = parseText(partial) ?: return
                    sendEvent("partial", text)
                }

                override fun onResult(resultJson: String?) {
                    val text = parseText(resultJson) ?: return
                    sendEvent("result", text)
                }

                override fun onFinalResult(finalResult: String?) {
                    val text = parseText(finalResult) ?: ""
                    sendEvent("final", text)
                }

                override fun onError(exception: Exception?) {
                    sendEvent("error", exception?.message ?: "vosk error")
                }

                override fun onTimeout() {
                    sendEvent("timeout", "")
                }
            }
            ss.startListening(listener)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "start failed: ${e.message}")
            result.error("start_failed", e.message, null)
        }
    }

    private fun parseText(json: String?): String? {
        if (json == null) return null
        return try {
            JSONObject(json).optString("text", "")
        } catch (e: Exception) {
            json
        }
    }

    private fun stopInternal() {
        try { speechService?.stop() } catch (_: Exception) {}
        try { speechService?.shutdown() } catch (_: Exception) {}
        speechService = null
        try { recognizer?.close() } catch (_: Exception) {}
        recognizer = null
    }

    fun stop(result: MethodChannel.Result) {
        stopInternal()
        result.success(true)
    }

    fun unload(result: MethodChannel.Result) {
        stopInternal()
        try { model?.close() } catch (_: Exception) {}
        model = null
        sink = null
        result.success(true)
    }

    fun onSinkChanged(newSink: EventChannel.EventSink?) {
        sink = newSink ?: sink
    }
}
