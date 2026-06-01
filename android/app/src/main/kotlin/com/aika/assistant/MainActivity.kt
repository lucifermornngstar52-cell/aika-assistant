package com.aika.assistant

import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val OVERLAY_CHANNEL      = "com.aika.assistant/overlay"
        private const val SCREEN_READER_CHANNEL = "com.aika.assistant/screen_reader"
        private const val AUDIO_CHANNEL        = "aika/audio"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 1. Overlay channel ────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "hasPermission" -> {
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this) else true
                        result.success(ok)
                    }

                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            startActivity(Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ))
                        }
                        result.success(null)
                    }

                    "showOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        startOverlay(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_SHOW
                            putExtra(AikaOverlayService.EXTRA_STATE, state)
                        })
                        result.success(null)
                    }

                    "updateOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_UPDATE
                            putExtra(AikaOverlayService.EXTRA_STATE, state)
                        })
                        result.success(null)
                    }

                    "hideOverlay" -> {
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_HIDE
                        })
                        result.success(null)
                    }

                    "configOverlay" -> {
                        val size    = (call.argument<Double>("size")    ?: 170.0).toFloat()
                        val side    = call.argument<String>("side")     ?: "left"
                        val opacity = (call.argument<Double>("opacity") ?: 1.0).toFloat()
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_CONFIG
                            putExtra(AikaOverlayService.EXTRA_SIZE,    size)
                            putExtra(AikaOverlayService.EXTRA_SIDE,    side)
                            putExtra(AikaOverlayService.EXTRA_OPACITY, opacity)
                        })
                        result.success(null)
                    }

                    "musicOverlay" -> {
                        val playing = call.argument<Boolean>("playing") ?: false
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_MUSIC
                            putExtra(AikaOverlayService.EXTRA_PLAYING, playing)
                        })
                        result.success(null)
                    }

                    "animOverlay" -> {
                        val animName = call.argument<String>("anim") ?: "idle"
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_ANIM
                            putExtra(AikaOverlayService.EXTRA_ANIM, animName)
                        })
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── 2. Screen reader channel ──────────────────────────────────────────
        // Все вызовы делегируются в AikaAccessibilityService.instance
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_READER_CHANNEL)
            .setMethodCallHandler { call, result ->
                val svc = AikaAccessibilityService.instance
                if (svc == null) {
                    result.error("NO_SERVICE", "AccessibilityService не запущен", null)
                    return@setMethodCallHandler
                }
                when (call.method) {

                    "getScreenText" -> {
                        result.success(svc.getAllScreenText())
                    }

                    "getClickableElements" -> {
                        val list = svc.getClickableElements()
                        result.success(list)
                    }

                    "getFocusedElement" -> {
                        result.success(svc.getFocusedElement())
                    }

                    "clickElement" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(svc.clickByText(text))
                    }

                    "clickElementExact" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(svc.clickByExactText(text))
                    }

                    "clickByDescription" -> {
                        val desc = call.argument<String>("desc") ?: ""
                        result.success(svc.clickByDescription(desc))
                    }

                    "typeInField" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(svc.typeText(text))
                    }

                    "clearField" -> {
                        result.success(svc.clearText())
                    }

                    "pressEnter" -> {
                        result.success(svc.pressEnter())
                    }

                    "performBack" -> {
                        svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
                        result.success(true)
                    }

                    "pressHome" -> {
                        svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME)
                        result.success(true)
                    }

                    "pressRecents" -> {
                        svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS)
                        result.success(true)
                    }

                    "openNotifications" -> {
                        svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
                        result.success(true)
                    }

                    "openQuickSettings" -> {
                        svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)
                        result.success(true)
                    }

                    "lockScreen" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            svc.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                            result.success(true)
                        } else {
                            result.error("UNSUPPORTED", "lockScreen требует Android 9+", null)
                        }
                    }

                    "scroll" -> {
                        val direction = call.argument<String>("direction") ?: "down"
                        svc.scrollScreen(direction)
                        result.success(true)
                    }

                    "swipe" -> {
                        val x1 = (call.argument<Double>("x1") ?: 540.0).toFloat()
                        val y1 = (call.argument<Double>("y1") ?: 800.0).toFloat()
                        val x2 = (call.argument<Double>("x2") ?: 540.0).toFloat()
                        val y2 = (call.argument<Double>("y2") ?: 400.0).toFloat()
                        val dur = (call.argument<Int>("duration") ?: 300).toLong()
                        svc.swipe(x1, y1, x2, y2, dur)
                        result.success(true)
                    }

                    "tapAt" -> {
                        val x = (call.argument<Double>("x") ?: 540.0).toFloat()
                        val y = (call.argument<Double>("y") ?: 1000.0).toFloat()
                        svc.tapAt(x, y)
                        result.success(true)
                    }

                    "getScreenSize" -> {
                        result.success(svc.getScreenSize())
                    }

                    else -> result.notImplemented()
                }
            }

        // ── 3. Audio channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isMusicPlaying" -> {
                        val am = getSystemService(AUDIO_SERVICE) as AudioManager
                        result.success(am.isMusicActive)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startOverlay(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
