package com.aika.assistant

import android.content.Context
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
                    "hasPermission" -> result.success(hasOverlayPermission())

                    "requestPermission" -> {
                        requestOverlayPermission()
                        result.success(null)
                    }

                    // Эти вызовы теперь НЕ запускают нативный сервис —
                    // Flutter сам управляет аватаром через AikaAvatar виджет
                    "showOverlay"   -> result.success(null)
                    "updateOverlay" -> result.success(null)
                    "hideOverlay"   -> result.success(null)

                    else -> result.notImplemented()
                }
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

    // onResume — НЕ запускаем нативный оверлей сервис автоматически.
    // Аватар управляется только Flutter виджетом AikaAvatar(draggable: true).
    override fun onResume() {
        super.onResume()
        // Намеренно пусто — нативный AikaOverlayService больше не используется
        // для показа аватара внутри приложения
    }
}
