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

                    "showOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        startOverlayService(AikaOverlayService.ACTION_SHOW, state)
                        result.success(null)
                    }

                    "updateOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        startOverlayService(AikaOverlayService.ACTION_UPDATE, state)
                        result.success(null)
                    }

                    "hideOverlay" -> {
                        startOverlayService(AikaOverlayService.ACTION_HIDE, "idle")
                        result.success(null)
                    }

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

    private fun startOverlayService(action: String, state: String) {
        if (!hasOverlayPermission()) return
        val intent = Intent(this, AikaOverlayService::class.java).apply {
            this.action = action
            putExtra(AikaOverlayService.EXTRA_STATE, state)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onResume() {
        super.onResume()
        // Auto-start overlay when app opens (if permission granted)
        if (hasOverlayPermission() && !AikaOverlayService.isRunning) {
            startOverlayService(AikaOverlayService.ACTION_SHOW, "idle")
        }
    }
}
