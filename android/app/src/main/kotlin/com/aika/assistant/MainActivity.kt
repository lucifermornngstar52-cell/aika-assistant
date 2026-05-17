package com.aika.assistant

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aika.assistant/overlay"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission"  -> result.success(hasOverlayPermission())
                    "requestPermission" -> { requestOverlayPermission(); result.success(null) }
                    // Flutter управляет аватаром сам — нативный сервис не нужен
                    "showOverlay"    -> result.success(null)
                    "updateOverlay"  -> result.success(null)
                    "hideOverlay"    -> result.success(null)
                    else             -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Принудительно останавливаем нативный overlay сервис если он был запущен ранее
        stopNativeOverlayService()
    }

    override fun onResume() {
        super.onResume()
        // НЕ запускаем нативный сервис — Flutter AikaAvatar управляет аватаром
    }

    private fun stopNativeOverlayService() {
        try {
            val intent = Intent(this, AikaOverlayService::class.java)
            stopService(intent)
        } catch (e: Exception) {
            // Сервис не был запущен — OK
        }
    }

    private fun hasOverlayPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            Settings.canDrawOverlays(this)
        else true

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            ))
        }
    }
}
