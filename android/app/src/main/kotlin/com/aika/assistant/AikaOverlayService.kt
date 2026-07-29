package com.aika.assistant

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.app.NotificationCompat
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * AivoraOverlayService — Live2D overlay через Android WebView.
 * Окно ровно по размеру модели, не перекрывает UI.
 * Перетаскивание работает нативно через WindowManager.updateViewLayout.
 */
class AikaOverlayService : Service() {

    companion object {
        const val ACTION_SHOW         = "com.aika.SHOW"
        const val ACTION_UPDATE       = "com.aika.UPDATE"
        const val ACTION_HIDE         = "com.aika.HIDE"
        const val ACTION_CONFIG       = "com.aika.CONFIG"
        const val ACTION_MUSIC        = "com.aika.MUSIC"
        const val ACTION_ANIM         = "com.aika.ANIM"
        const val ACTION_SWITCH_MODEL = "com.aika.SWITCH_MODEL"
        const val ACTION_DRAG_ENABLED = "com.aika.DRAG_ENABLED"
        const val ACTION_SET_MODE    = "com.aika.SET_MODE"   // "live2d" | "3d"
        const val EXTRA_MODE         = "mode"

        const val EXTRA_STATE       = "state"
        const val EXTRA_SIZE        = "size"
        const val EXTRA_SIDE        = "side"
        const val EXTRA_OPACITY     = "opacity"
        const val EXTRA_PLAYING     = "playing"
        const val EXTRA_ANIM        = "anim_name"
        const val EXTRA_MODEL_PATH  = "model_path"
        const val EXTRA_DRAG_ENABLED = "drag_enabled"
        const val EXTRA_SOUND_PATH   = "sound_path"
        const val ACTION_PLAY_SOUND  = "aika.overlay.PLAY_SOUND"
        const val ACTION_STOP_SOUND  = "aika.overlay.STOP_SOUND"
        const val ENGINE_ID          = "live2d_overlay_engine"

        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337
        private const val TAG        = "AikaOverlay"
        private const val BASE_URL   = "file:///android_asset/flutter_assets/assets/"

        var isRunning = false
    }

    private val handler = Handler(Looper.getMainLooper())
    private var wm: WindowManager? = null
    private var webView: WebView? = null
    private var params: WindowManager.LayoutParams? = null

    private var dragEnabled  = true
    private var currentState = "idle"
    private var currentMode  = "live2d"  // "live2d" | "3d"

    private fun getHtmlPath(): String =
        if (currentMode == "3d") "file:///android_asset/flutter_assets/assets/3d_viewer.html"
        else "file:///android_asset/flutter_assets/assets/live2d_viewer.html"
    private var sizeDp       = 200f
    private var opacity      = 1f
    private var side         = "left"

    // Drag state
    private var dragStartX  = 0
    private var dragStartY  = 0
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var isDragging  = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        handler.post { setupWindow() }
    }

    override fun onDestroy() {
        isRunning = false
        handler.post {
            try { webView?.let { wm?.removeView(it) } } catch (_: Exception) {}
            webView?.destroy()
            webView = null
        }
        super.onDestroy()
    }

    @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
    private fun setupWindow() {
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = resources.displayMetrics.density

        val wPx = (sizeDp * density).roundToInt()
        val hPx = (sizeDp * 1.6f * density).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        // FLAG_NOT_FOCUSABLE — не забирает фокус
        // FLAG_NOT_TOUCH_MODAL — касания вне окна проходят насквозь
        // УБИРАЕМ FLAG_LAYOUT_IN_SCREEN — он расширяет хит-зону
        params = WindowManager.LayoutParams(
            wPx, hPx,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSPARENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val screenW = resources.displayMetrics.widthPixels
            x = if (side == "right") screenW - wPx - (16 * density).roundToInt()
                else (16 * density).roundToInt()
            y = (120 * density).roundToInt()
        }

        val wv = WebView(applicationContext)
        webView = wv
        wv.alpha = opacity
        wv.setBackgroundColor(Color.TRANSPARENT)
        wv.background?.alpha = 0

        wv.settings.apply {
            javaScriptEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            @Suppress("DEPRECATION") allowFileAccessFromFileURLs = true
            @Suppress("DEPRECATION") allowUniversalAccessFromFileURLs = true
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            mediaPlaybackRequiresUserGesture = false
            domStorageEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
        }

        wv.webChromeClient = WebChromeClient()
        wv.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(v: WebView?, r: WebResourceRequest?): WebResourceResponse? = null
            override fun onPageFinished(v: WebView?, url: String?) {
                handler.postDelayed({
                    v?.evaluateJavascript("window.setAikaState('$currentState')", null)
                }, 2500)
            }
        }

        wv.addJavascriptInterface(object {
            @JavascriptInterface
            fun onModelLoaded() {
                handler.post {
                    webView?.evaluateJavascript("window.setAikaState('$currentState')", null)
                }
            }
            @JavascriptInterface
            fun onTap() { Log.d(TAG, "tap") }
        }, "AndroidBridge")

        // ── Touch handler — перетаскивание прямо на WebView ─────────────────
        wv.setOnTouchListener { _, ev ->
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    isDragging   = false
                    dragStartX   = params!!.x
                    dragStartY   = params!!.y
                    touchStartX  = ev.rawX
                    touchStartY  = ev.rawY
                    // Пропускаем касания в прозрачных краях (верх 20%, низ 10%)
                    val relY = ev.y / wv.height.toFloat()
                    if (relY < 0.18f) return@setOnTouchListener false
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - touchStartX
                    val dy = ev.rawY - touchStartY
                    if (!isDragging && (abs(dx) > 8 || abs(dy) > 8)) {
                        isDragging = true
                    }
                    if (isDragging && dragEnabled) {
                        params!!.x = (dragStartX + dx).roundToInt()
                        params!!.y = (dragStartY + dy).roundToInt()
                        try { wm?.updateViewLayout(wv, params) } catch (_: Exception) {}
                        return@setOnTouchListener true
                    }
                    false
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        // тап — приветствие
                        wv.evaluateJavascript("window.setAikaState('greeting')", null)
                        handler.postDelayed({
                            webView?.evaluateJavascript("window.setAikaState('idle')", null)
                        }, 2500)
                    }
                    isDragging = false
                    false
                }
                else -> false
            }
        }

        wv.loadUrl("${BASE_URL}live2d_viewer.html")

        // Fallback — показываем через 5 сек если JS не ответил
        handler.postDelayed({ webView?.let { if (it.alpha < 0.5f) it.alpha = opacity } }, 5000)

        try {
            wm?.addView(wv, params)
        } catch (e: Exception) {
            Log.e(TAG, "addView failed: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val density = resources.displayMetrics.density

        when (intent?.action) {
            ACTION_SHOW, ACTION_UPDATE -> {
                val st = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                currentState = st
                handler.post {
                    if (webView == null) setupWindow()
                    else webView?.evaluateJavascript("window.setAikaState('$st')", null)
                }
            }
            ACTION_HIDE -> handler.post {
                currentState = "idle"
                webView?.evaluateJavascript("window.setAikaState('idle')", null)
            }
            ACTION_CONFIG -> {
                val newSize    = intent.getFloatExtra(EXTRA_SIZE, 0f)
                val newOpacity = intent.getFloatExtra(EXTRA_OPACITY, -1f)
                val newSide    = intent.getStringExtra(EXTRA_SIDE)
                handler.post {
                    val p = params ?: return@post
                    val wv = webView ?: return@post
                    var changed = false
                    if (newSize > 0f) {
                        sizeDp = newSize
                        p.width  = (sizeDp * density).roundToInt()
                        p.height = (sizeDp * 1.6f * density).roundToInt()
                        changed = true
                    }
                    if (newOpacity >= 0f) {
                        opacity = newOpacity
                        wv.alpha = opacity
                    }
                    if (newSide != null) {
                        side = newSide
                        val screenW = resources.displayMetrics.widthPixels
                        p.x = if (side == "right") screenW - p.width - (16 * density).roundToInt()
                              else (16 * density).roundToInt()
                        changed = true
                    }
                    if (changed) try { wm?.updateViewLayout(wv, p) } catch (_: Exception) {}
                }
            }
            ACTION_SWITCH_MODEL -> {
                val path = intent.getStringExtra(EXTRA_MODEL_PATH) ?: return START_STICKY
                Log.d("AikaOverlay", "switchModel to: $path")
                handler.post {
                    if (webView != null) {
                        // Сначала пробуем обычное переключение
                        webView?.evaluateJavascript("window.switchModel('$path')") { result ->
                            Log.d("AikaOverlay", "switchModel result: $result")
                        }
                        // Резерв: если через 10 сек модель не загрузилась — перезагружаем WebView
                        handler.postDelayed({
                            webView?.evaluateJavascript("(typeof model !== 'undefined' && model) ? 'ok' : 'null'") { check ->
                                if (check == "null" || check == "undefined") {
                                    Log.w("AikaOverlay", "Model stuck, reloading WebView...")
                                    webView?.reload()
                                    handler.postDelayed({
                                        webView?.evaluateJavascript("window.switchModel('$path')", null)
                                    }, 3000)
                                }
                            }
                        }, 10000)
                    } else {
                        Log.e("AikaOverlay", "webView is null!")
                        setupWindow()
                    }
                }
            }
            ACTION_SET_MODE -> {
                val mode = intent.getStringExtra(EXTRA_MODE) ?: "live2d"
                currentMode = mode
                handler.post {
                    webView?.loadUrl(getHtmlPath())
                }
            }
            ACTION_DRAG_ENABLED -> {
                dragEnabled = intent.getBooleanExtra(EXTRA_DRAG_ENABLED, true)
            }
            ACTION_ANIM -> {
                val anim = intent.getStringExtra(EXTRA_ANIM) ?: return START_STICKY
                handler.post {
                    webView?.evaluateJavascript("window.setAikaState('$anim')", null)
                }
            }
            ACTION_PLAY_SOUND -> {
                val path = intent.getStringExtra(EXTRA_SOUND_PATH) ?: return START_STICKY
                handler.post {
                    // Передаём путь в JS — экранируем одинарные кавычки
                    val safePath = path.replace("'", "\'")
                    webView?.evaluateJavascript("window.externalPlaySound('$safePath')", null)
                }
            }
            ACTION_STOP_SOUND -> {
                handler.post {
                    webView?.evaluateJavascript("window.externalStopSound()", null)
                }
            }
            ACTION_MUSIC -> {
                val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
                currentState = if (playing) "listening" else "idle"
                handler.post {
                    webView?.evaluateJavascript("window.setAikaState('$currentState')", null)
                }
            }
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Aivora Overlay", NotificationManager.IMPORTANCE_MIN)
            ch.setShowBadge(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Aivora активна")
            .setContentText("Нажми чтобы открыть")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
}

