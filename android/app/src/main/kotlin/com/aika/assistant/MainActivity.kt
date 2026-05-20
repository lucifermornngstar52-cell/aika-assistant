package com.aika.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val OVERLAY_CHANNEL  = "com.aika.assistant/overlay"
    private val AUDIO_CHANNEL    = "aika/audio"
    private val SCREEN_CHANNEL   = "com.aika.assistant/screen"
    private val SCREEN_EVENTS    = "com.aika.assistant/screen_events"
    private val MESSENGER_CHANNEL = "com.aika.assistant/messenger"
    private val URL_CHANNEL      = "com.aika.assistant/url"
    private val MEDIA_CHANNEL    = "com.aika.assistant/media"

    private var screenEventSink: EventChannel.EventSink? = null
    private var screenReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Overlay channel ──────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission"      -> result.success(hasOverlayPermission())
                    "requestPermission"  -> { requestOverlayPermission(); result.success(null) }
                    "showOverlay"        -> {
                        val state = call.argument<String>("state") ?: "idle"
                        startOverlayService(AikaOverlayService.ACTION_SHOW, state)
                        result.success(null)
                    }
                    "updateOverlay"      -> {
                        val state = call.argument<String>("state") ?: "idle"
                        startOverlayService(AikaOverlayService.ACTION_UPDATE, state)
                        result.success(null)
                    }
                    "hideOverlay"        -> {
                        startOverlayService(AikaOverlayService.ACTION_UPDATE, "idle")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Audio channel ────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isMusicPlaying" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        result.success(am.isMusicActive)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Screen method channel (accessibility status) ─────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        })
                        result.success(null)
                    }
                    "getCurrentApp" -> {
                        result.success(mapOf(
                            "package" to AikaAccessibilityService.currentPackage,
                            "label"   to AikaAccessibilityService.currentAppLabel
                        ))
                    }
                    else -> result.notImplemented()
                }
            }

        // ── URL channel ──────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, URL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        try {
                            val intent = android.content.Intent(
                                android.content.Intent.ACTION_VIEW,
                                android.net.Uri.parse(url)
                            ).apply {
                                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Media control channel ─────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mediaControl" -> {
                        val action = call.argument<String>("action") ?: ""
                        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                        val keyCode = when (action) {
                            "play"     -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY
                            "pause"    -> android.view.KeyEvent.KEYCODE_MEDIA_PAUSE
                            "next"     -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
                            "previous" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
                            "stop"     -> android.view.KeyEvent.KEYCODE_MEDIA_STOP
                            else       -> -1
                        }
                        if (keyCode != -1) {
                            val down = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode)
                            val up   = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode)
                            am.dispatchMediaKeyEvent(down)
                            am.dispatchMediaKeyEvent(up)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Messenger channel (отправка сообщений через Accessibility) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MESSENGER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendMessage" -> {
                        val app     = call.argument<String>("app")     ?: "whatsapp"
                        val contact = call.argument<String>("contact") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        val service = AikaAccessibilityService.instance
                        if (service == null) {
                            result.error("NO_SERVICE", "Включи Accessibility Service для Айки", null)
                        } else if (contact.isEmpty()) {
                            result.error("NO_CONTACT", "Имя контакта не указано", null)
                        } else {
                            service.startSendMessage(app, contact, message)
                            result.success("Ищу $contact в $app...")
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Screen event channel (поток событий смены приложения) ─
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    screenEventSink = sink
                    screenReceiver = object : BroadcastReceiver() {
                        override fun onReceive(ctx: Context?, intent: Intent?) {
                            if (intent?.action == AikaAccessibilityService.ACTION_SCREEN_EVENT) {
                                sink?.success(mapOf(
                                    "package" to (intent.getStringExtra(AikaAccessibilityService.EXTRA_PACKAGE) ?: ""),
                                    "label"   to (intent.getStringExtra(AikaAccessibilityService.EXTRA_LABEL) ?: ""),
                                    "event"   to (intent.getStringExtra(AikaAccessibilityService.EXTRA_EVENT_TYPE) ?: "")
                                ))
                            }
                        }
                    }
                    val filter = IntentFilter(AikaAccessibilityService.ACTION_SCREEN_EVENT)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(screenReceiver, filter)
                    }
                }

                override fun onCancel(args: Any?) {
                    screenReceiver?.let { unregisterReceiver(it) }
                    screenEventSink = null
                    screenReceiver = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (hasOverlayPermission() && !AikaOverlayService.isRunning) {
            startOverlayService(AikaOverlayService.ACTION_SHOW, "greeting")
        }
    }

    override fun onResume() {
        super.onResume()
        if (hasOverlayPermission()) {
            if (!AikaOverlayService.isRunning)
                startOverlayService(AikaOverlayService.ACTION_SHOW, "idle")
            else
                startOverlayService(AikaOverlayService.ACTION_UPDATE, "idle")
        }
    }

    private fun hasOverlayPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            Settings.canDrawOverlays(this) else true

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            startForegroundService(intent) else startService(intent)
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val serviceName = "$packageName/${AikaAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.split(":").any { it.equals(serviceName, ignoreCase = true) }
    }
}
