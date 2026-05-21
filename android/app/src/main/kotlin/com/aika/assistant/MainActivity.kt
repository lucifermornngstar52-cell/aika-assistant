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
import android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val OVERLAY_CHANNEL  = "com.aika.assistant/overlay"
    private val AUDIO_CHANNEL    = "aika/audio"
    private val SCREEN_CHANNEL   = "com.aika.assistant/screen"
    private val NOTIF_CHANNEL    = "com.aika.assistant/notifications"
    private val NOTIF_EVENTS     = "com.aika.assistant/notification_events"
    private val SCREEN_EVENTS    = "com.aika.assistant/screen_events"
    private val MESSENGER_CHANNEL = "com.aika.assistant/messenger"
    private val URL_CHANNEL      = "com.aika.assistant/url"
    private val MEDIA_CHANNEL    = "com.aika.assistant/media"
    private val SCREEN_READER_CHANNEL = "com.aika.assistant/screen_reader"
    private val APPS_CHANNEL     = "com.aika.assistant/apps"

    private var screenEventSink: EventChannel.EventSink? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var notifEventSink: EventChannel.EventSink? = null
    private var notifReceiver: BroadcastReceiver? = null

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

        
        // ── Screen Reader channel (read content via Accessibility) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_READER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getScreenText" -> {
                        val svc = AikaAccessibilityService.instance
                        if (svc != null) result.success(svc.getAllScreenText())
                        else result.success(null)
                    }
                    "clickElement" -> {
                        val text = call.argument<String>("text") ?: ""
                        val svc = AikaAccessibilityService.instance
                        if (svc != null) result.success(svc.clickByText(text))
                        else result.success(false)
                    }
                    "scroll" -> {
                        val direction = call.argument<String>("direction") ?: "down"
                        val svc = AikaAccessibilityService.instance
                        svc?.scroll(direction)
                        result.success(null)
                    }
                    "performBack" -> {
                        val svc = AikaAccessibilityService.instance
                        svc?.performBack()
                        result.success(null)
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
                    // Start music player in background without opening UI (stays in game)
                    "startMusicBackground" -> {
                        val packageName = call.argument<String>("package") ?: "com.spotify.music"
                        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                        // 1. Request audio focus so player knows to start
                        am.requestAudioFocus(
                            null,
                            android.media.AudioManager.STREAM_MUSIC,
                            android.media.AudioManager.AUDIOFOCUS_GAIN
                        )
                        // 2. Send PLAY media key - this resumes the last session of any player
                        val down = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PLAY)
                        val up   = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP,   android.view.KeyEvent.KEYCODE_MEDIA_PLAY)
                        am.dispatchMediaKeyEvent(down)
                        am.dispatchMediaKeyEvent(up)
                        // 3. If no active player, try to start the specific app as a service
                        //    (won't bring to foreground if FLAG_ACTIVITY_NEW_TASK is NOT set)
                        if (!am.isMusicActive) {
                            try {
                                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                                if (launchIntent != null) {
                                    // Remove CATEGORY_LAUNCHER so it starts in background context
                                    launchIntent.addFlags(
                                        Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_FROM_BACKGROUND
                                    )
                                    startActivity(launchIntent)
                                }
                            } catch (_: Exception) {}
                        }
                        result.success(am.isMusicActive)
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

        // ── Notification method channel ──────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> {
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            "enabled_notification_listeners"
                        ) ?: ""
                        result.success(enabled.contains(packageName))
                    }
                    "openPermissionSettings" -> {
                        startActivity(Intent(ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        })
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Notification event channel ─────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    notifEventSink = sink
                    notifReceiver = object : BroadcastReceiver() {
                        override fun onReceive(ctx: Context?, intent: Intent?) {
                            if (intent?.action == AikaNotificationListenerService.ACTION_NOTIF) {
                                sink?.success(mapOf(
                                    "pkg"   to (intent.getStringExtra(AikaNotificationListenerService.EXTRA_PKG)   ?: ""),
                                    "title" to (intent.getStringExtra(AikaNotificationListenerService.EXTRA_TITLE) ?: ""),
                                    "text"  to (intent.getStringExtra(AikaNotificationListenerService.EXTRA_TEXT)  ?: ""),
                                    "time"  to intent.getLongExtra(AikaNotificationListenerService.EXTRA_TIME, 0L).toString()
                                ))
                            }
                        }
                    }
                    val filter = IntentFilter(AikaNotificationListenerService.ACTION_NOTIF)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(notifReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(notifReceiver, filter)
                    }
                }
                override fun onCancel(args: Any?) {
                    notifReceiver?.let { unregisterReceiver(it) }
                    notifEventSink = null
                    notifReceiver = null
                }
            })

        // ── Apps channel (list installed apps) ─────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        val pm = packageManager
                        val intent = Intent(Intent.ACTION_MAIN, null).apply {
                            addCategory(Intent.CATEGORY_LAUNCHER)
                        }
                        val apps = pm.queryIntentActivities(intent, 0).map { ri ->
                            mapOf(
                                "package" to ri.activityInfo.packageName,
                                "label"   to ri.loadLabel(pm).toString()
                            )
                        }.distinctBy { it["package"] }
                        result.success(apps)
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

