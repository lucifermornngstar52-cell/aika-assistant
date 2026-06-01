package com.aika.assistant

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val OVERLAY_CHANNEL = "com.aika.assistant/overlay"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OVERLAY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "hasPermission" -> {
                    val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                        Settings.canDrawOverlays(this) else true
                    result.success(ok)
                }

                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(null)
                }

                "showOverlay" -> {
                    val state = call.argument<String>("state") ?: "idle"
                    val i = Intent(this, AikaOverlayService::class.java).apply {
                        action = AikaOverlayService.ACTION_SHOW
                        putExtra(AikaOverlayService.EXTRA_STATE, state)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(i)
                    } else {
                        startService(i)
                    }
                    result.success(null)
                }

                "updateOverlay" -> {
                    val state = call.argument<String>("state") ?: "idle"
                    val i = Intent(this, AikaOverlayService::class.java).apply {
                        action = AikaOverlayService.ACTION_UPDATE
                        putExtra(AikaOverlayService.EXTRA_STATE, state)
                    }
                    startService(i)
                    result.success(null)
                }

                "hideOverlay" -> {
                    val i = Intent(this, AikaOverlayService::class.java).apply {
                        action = AikaOverlayService.ACTION_HIDE
                    }
                    startService(i)
                    result.success(null)
                }

                "configOverlay" -> {
                    val size    = (call.argument<Double>("size") ?: 170.0).toFloat()
                    val side    = call.argument<String>("side") ?: "left"
                    val opacity = (call.argument<Double>("opacity") ?: 1.0).toFloat()
                    val i = Intent(this, AikaOverlayService::class.java).apply {
                        action = AikaOverlayService.ACTION_CONFIG
                        putExtra(AikaOverlayService.EXTRA_SIZE, size)
                        putExtra(AikaOverlayService.EXTRA_SIDE, side)
                        putExtra(AikaOverlayService.EXTRA_OPACITY, opacity)
                    }
                    startService(i)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
