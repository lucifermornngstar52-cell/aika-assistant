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
import android.util.Log

class MainActivity : FlutterActivity() {

    companion object {
        private const val OVERLAY_CHANNEL       = "com.aika.assistant/overlay"
        private const val SCREEN_READER_CHANNEL = "com.aika.assistant/screen_reader"
        private const val LAUNCHER_CHANNEL      = "com.aika.assistant/launcher"
        private const val SCREEN_CHANNEL        = "com.aika.assistant/screen"
        private const val SCREEN_EVENTS_CHANNEL = "com.aika.assistant/screen_events"
        private const val AUDIO_CHANNEL         = "aika/audio"
        private const val MESSENGER_CHANNEL     = "com.aika.assistant/messenger"
        private const val MEDIA_CHANNEL             = "com.aika.assistant/media"
        private const val NOTIFICATION_EVENTS_CHANNEL  = "com.aika.assistant/notification_events"
        private const val NOTIFICATIONS_CHANNEL          = "com.aika.assistant/notifications"
    }

    // EventChannel sink для отправки событий смены приложений во Flutter
    private var screenEventSink: EventChannel.EventSink? = null

    // EventChannel sink для уведомлений
    private var notificationEventSink: EventChannel.EventSink? = null

    // BroadcastReceiver — получает события от AikaAccessibilityService
    private val screenEventReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AikaAccessibilityService.ACTION_SCREEN_EVENT) return
            val pkg   = intent.getStringExtra("package") ?: return
            val label = intent.getStringExtra("label")   ?: ""
            screenEventSink?.success(mapOf("package" to pkg, "label" to label))
        }
    }

    // BroadcastReceiver — уведомления от AikaNotificationListenerService
    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AikaNotificationListenerService.ACTION_NOTIF) return
            val pkg   = intent.getStringExtra(AikaNotificationListenerService.EXTRA_PKG)   ?: return
            val title = intent.getStringExtra(AikaNotificationListenerService.EXTRA_TITLE) ?: ""
            val text  = intent.getStringExtra(AikaNotificationListenerService.EXTRA_TEXT)  ?: ""
            val time  = intent.getLongExtra(AikaNotificationListenerService.EXTRA_TIME, 0).toString()
            notificationEventSink?.success(mapOf(
                "pkg" to pkg, "title" to title, "text" to text, "time" to time
            ))
        }
    }

    // ── Автостарт overlay при запуске приложения ─────────────────────────────
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        autoStartOverlay()
        // Регистрируем ресивер событий смены приложений
        val filter = IntentFilter(AikaAccessibilityService.ACTION_SCREEN_EVENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenEventReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenEventReceiver, filter)
        }

        // Регистрируем ресивер уведомлений
        val notifFilter = IntentFilter(AikaNotificationListenerService.ACTION_NOTIF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notificationReceiver, notifFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(notificationReceiver, notifFilter)
        }
    }

    private fun sendMediaKey(keyCode: Int) {
        val audio = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
        audio.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keyCode))
        audio.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keyCode))
    }

    private fun launchSpotifySearch(query: String) {
        try {
            // Пробуем открыть Spotify через deep link с поиском
            val spotifyPkg = "com.spotify.music"
            val intent = if (query.isNotEmpty()) {
                android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                    data = android.net.Uri.parse("spotify:search:${query}")
                    setPackage(spotifyPkg)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            } else {
                packageManager.getLaunchIntentForPackage(spotifyPkg)?.apply {
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }
            if (intent != null) startActivity(intent)
            // После запуска нажимаем Play через медиаключ
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PLAY)
            }, 2000)
        } catch (e: Exception) {
            Log.e("Aika", "launchSpotifySearch failed: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(screenEventReceiver)
        try { unregisterReceiver(notificationReceiver) } catch (_: Exception) {} } catch (_: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        // При возврате в приложение — если overlay не запущен, стартуем
        if (!AikaOverlayService.isRunning) {
            autoStartOverlay()
        }
    }

    private fun autoStartOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                Log.d("Aika", "Overlay permission not granted — skipping auto-start")
                return
            }
        }
        try {
            val intent = Intent(this, AikaOverlayService::class.java).apply {
                action = AikaOverlayService.ACTION_SHOW
                putExtra(AikaOverlayService.EXTRA_STATE, "idle")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d("Aika", "Overlay auto-started")
        } catch (e: Exception) {
            Log.e("Aika", "Failed to auto-start overlay: ${e.message}")
        }
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

                    "setModeOverlay" -> {
                    val mode = call.argument<String>("mode") ?: "live2d"
                    startService(Intent(this, AikaOverlayService::class.java).apply {
                        action = AikaOverlayService.ACTION_SET_MODE
                        putExtra(AikaOverlayService.EXTRA_MODE, mode)
                    })
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

                    "setDragEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_DRAG_ENABLED
                            putExtra(AikaOverlayService.EXTRA_DRAG_ENABLED, enabled)
                        })
                        result.success(null)
                    }

                    "switchModel" -> {
                        val path = call.argument<String>("path") ?: "models/Hiyori/Hiyori.model3.json"
                        startService(Intent(this, AikaOverlayService::class.java).apply {
                            action = AikaOverlayService.ACTION_SWITCH_MODEL
                            putExtra(AikaOverlayService.EXTRA_MODEL_PATH, path)
                        })
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── 3. App launcher channel ─────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCHER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchApp" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        if (pkg.isEmpty()) { result.success(false); return@setMethodCallHandler }
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(pkg)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            Log.e("Aika", "launchApp failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    "isInstalled" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val installed = try {
                            packageManager.getApplicationInfo(pkg, 0)
                            true
                        } catch (_: Exception) { false }
                        result.success(installed)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 4. Screen accessibility channel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        val enabled = AikaAccessibilityService.instance != null
                        result.success(enabled)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 5. Screen events EventChannel (app switch notifications) ──────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    screenEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    screenEventSink = null
                }
            })

        // ── 6. Notification events EventChannel ──────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    notificationEventSink = null
                }
            })

        // ── 7. Notifications permission channel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> {
                        val enabledListeners = android.provider.Settings.Secure.getString(
                            contentResolver, "enabled_notification_listeners"
                        )
                        val enabled = enabledListeners?.contains(packageName) == true
                        result.success(enabled)
                    }
                    "openPermissionSettings" -> {
                        startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
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

                    "getScreenStructure" -> {
                        result.success(svc.getScreenStructure())
                    }

                    "longClickByText" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(svc.longClickByText(text))
                    }

                    "longTapAt" -> {
                        val x = (call.argument<Double>("x") ?: 540.0).toFloat()
                        val y = (call.argument<Double>("y") ?: 1000.0).toFloat()
                        svc.longTapAt(x, y)
                        result.success(true)
                    }

                    "doubleTapAt" -> {
                        val x = (call.argument<Double>("x") ?: 540.0).toFloat()
                        val y = (call.argument<Double>("y") ?: 1000.0).toFloat()
                        svc.doubleTapAt(x, y)
                        result.success(true)
                    }

                    "takeScreenshot" -> {
                        result.success(svc.takeScreenshot())
                    }

                    "powerDialog" -> {
                        result.success(svc.powerDialog())
                    }

                    "toggleSplitScreen" -> {
                        result.success(svc.toggleSplitScreen())
                    }

                    "copySelectedText" -> {
                        result.success(svc.copySelectedText())
                    }

                    "pasteText" -> {
                        result.success(svc.pasteText())
                    }

                    "appendText" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(svc.appendText(text))
                    }

                    "clickByDescription" -> {
                        val desc = call.argument<String>("desc") ?: ""
                        result.success(svc.clickByDescription(desc))
                    }

                    "findByClass" -> {
                        val cls = call.argument<String>("className") ?: "EditText"
                        result.success(svc.findNodesByClass(cls))
                    }

                    "closeCurrentApp" -> {
                        svc.closeCurrentApp()
                        result.success(true)
                    }

                    "openAppSettings" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        result.success(svc.openAppSettings(pkg))
                    }

                    "uninstallApp" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        result.success(svc.uninstallApp(pkg))
                    }

                    "pressBack" -> {
                        svc.pressBack()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── 3. Audio channel ──────────────────────────────────────────────────
        // ── 6. Messenger channel — отправка сообщений через Accessibility ──────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MESSENGER_CHANNEL)
            .setMethodCallHandler { call, result ->
                val svc = AikaAccessibilityService.instance
                when (call.method) {
                    "sendMessage" -> {
                        val app     = call.argument<String>("app")     ?: ""
                        val contact = call.argument<String>("contact") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        if (svc == null) {
                            result.success("NO_ACCESSIBILITY: включи Accessibility в настройках")
                            return@setMethodCallHandler
                        }
                        if (app.isEmpty() || contact.isEmpty() || message.isEmpty()) {
                            result.success("ERROR: app/contact/message не указаны")
                            return@setMethodCallHandler
                        }
                        svc.startSendMessage(app, contact, message)
                        result.success("Отправляю сообщение для $contact...")
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 7. Media channel — управление музыкой ──────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playPause" -> {
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                        result.success(true)
                    }
                    "next" -> {
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_NEXT)
                        result.success(true)
                    }
                    "prev" -> {
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                        result.success(true)
                    }
                    "play" -> {
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PLAY)
                        result.success(true)
                    }
                    "pause" -> {
                        sendMediaKey(android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)
                        result.success(true)
                    }
                    "launchSpotifyAndPlay" -> {
                        val query = call.argument<String>("query") ?: ""
                        launchSpotifySearch(query)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

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
        // Если сервис уже запущен — просто шлём ему интент (не создаём новый)
        // Иначе каждый вызов создавал бы новый WebView поверх старого
        if (AikaOverlayService.isRunning) {
            startService(intent)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
