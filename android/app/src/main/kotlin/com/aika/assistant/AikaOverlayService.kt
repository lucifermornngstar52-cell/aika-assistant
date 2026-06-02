package com.aika.assistant

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * AikaOverlayService — Live2D overlay через Android WebView.
 * Не использует второй FlutterEngine. Стабильно на всех Android 8+.
 */
class AikaOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "com.aika.SHOW"
        const val ACTION_UPDATE = "com.aika.UPDATE"
        const val ACTION_HIDE   = "com.aika.HIDE"
        const val ACTION_CONFIG = "com.aika.CONFIG"
        const val ACTION_MUSIC  = "com.aika.MUSIC"
        const val ACTION_ANIM   = "com.aika.ANIM"
        const val EXTRA_STATE   = "state"
        const val EXTRA_SIZE    = "size"
        const val EXTRA_SIDE    = "side"
        const val EXTRA_OPACITY = "opacity"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_ANIM    = "anim_name"
        // для совместимости с MainActivity
        const val ENGINE_ID     = "live2d_overlay_engine"

        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337
        private const val TAG        = "AikaOverlay"
        private const val BASE_URL   = "file:///android_asset/flutter_assets/assets/"

        var isRunning = false

        const val ACTION_SWITCH_MODEL  = "com.aika.SWITCH_MODEL"
        const val EXTRA_MODEL_PATH     = "model_path"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var rootFrame: FrameLayout? = null
    private var webView: WebView? = null
    private var params: WindowManager.LayoutParams? = null

    private var currentState = "idle"
    private var sizeDp       = 200f
    private var opacity      = 1f
    private var side         = "left"

    // Drag
    private var dragInitX = 0; private var dragInitY = 0
    private var dragTouchX = 0f; private var dragTouchY = 0f
    private var wasDragging = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        handler.post { setupWindow() }
        Log.d(TAG, "onCreate")
    }

    override fun onDestroy() {
        isRunning = false
        handler.post {
            try { rootFrame?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
            webView?.destroy()
            webView = null
            rootFrame = null
        }
        super.onDestroy()
        Log.d(TAG, "onDestroy")
    }

    @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
    private fun setupWindow() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp    = resources.displayMetrics.density
        val wPx   = (sizeDp * dp).roundToInt()
        val hPx   = (sizeDp * 1.55f * dp).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        params = WindowManager.LayoutParams(
            wPx, hPx, overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSPARENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (16 * dp).roundToInt()
            y = (120 * dp).roundToInt()
        }

        // ── WebView ──────────────────────────────────────────────────────────
        val wv = WebView(applicationContext)
        webView = wv

        wv.setBackgroundColor(Color.TRANSPARENT)
        wv.background?.alpha = 0

        wv.settings.apply {
            javaScriptEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            @Suppress("DEPRECATION")
            allowFileAccessFromFileURLs = true
            @Suppress("DEPRECATION")
            allowUniversalAccessFromFileURLs = true
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
            override fun shouldInterceptRequest(
                view: WebView?, request: WebResourceRequest?
            ): WebResourceResponse? = null

            override fun onPageFinished(view: WebView?, url: String?) {
                Log.d(TAG, "page loaded: $url")
                // Ждём инициализации JS
                handler.postDelayed({
                    view?.evaluateJavascript("window.setAikaState('$currentState')", null)
                }, 3000)
            }
        }

        // JS Interface для получения сигнала от Live2D
        wv.addJavascriptInterface(object {
            @JavascriptInterface
            fun onModelLoaded() {
                Log.d(TAG, "modelLoaded signal from JS")
                handler.post {
                    val wvRef = webView ?: return@post
                    wvRef.evaluateJavascript("window.setAikaState('$currentState')", null)
                    wvRef.alpha = 1f
                }
            }
            @JavascriptInterface
            fun onTap() {
                Log.d(TAG, "model tapped")
            }
        }, "AndroidBridge")

        // Загружаем HTML
        wv.alpha = 0f
        wv.loadUrl("${BASE_URL}live2d_viewer.html")

        // Показываем через 5 сек в любом случае (fallback)
        handler.postDelayed({
            webView?.let { if (it.alpha < 0.5f) it.alpha = 1f }
        }, 5000)

        // ── Touch: drag ──────────────────────────────────────────────────────
        val frame = FrameLayout(applicationContext)
        frame.setBackgroundColor(Color.TRANSPARENT)
        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        frame.addView(wv, lp)

        var downMs = 0L
        frame.setOnTouchListener { _, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    wasDragging = false
                    downMs = System.currentTimeMillis()
                    dragInitX = params!!.x; dragInitY = params!!.y
                    dragTouchX = ev.rawX;  dragTouchY = ev.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - dragTouchX
                    val dy = ev.rawY - dragTouchY
                    if (abs(dx) > 6 || abs(dy) > 6) wasDragging = true
                    if (wasDragging) {
                        params!!.x = (dragInitX + dx).roundToInt()
                        params!!.y = (dragInitY + dy).roundToInt()
                        try { windowManager?.updateViewLayout(frame, params) } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!wasDragging && System.currentTimeMillis() - downMs < 350) {
                        // tap — приветствие
                        webView?.evaluateJavascript("window.setAikaState('greeting')", null)
                        handler.postDelayed({
                            webView?.evaluateJavascript("window.setAikaState('idle')", null)
                        }, 2500)
                    }
                    true
                }
                else -> false
            }
        }

        rootFrame = frame
        try {
            windowManager?.addView(frame, params)
        } catch (e: Exception) {
            Log.e(TAG, "addView failed: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW, ACTION_UPDATE -> {
                val st = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                currentState = st
                handler.post {
                    if (rootFrame?.windowToken == null) setupWindow()
                    else webView?.evaluateJavascript("window.setAikaState('$st')", null)
                }
            }
            ACTION_HIDE -> handler.post {
                currentState = "idle"
                webView?.evaluateJavascript("window.setAikaState('idle')", null)
            }
            ACTION_CONFIG -> {
                val newSize    = intent.getFloatExtra(EXTRA_SIZE, 0f)
                val newOpacity = intent.getFloatExtra(EXTRA_OPACITY, 1f)
                val newSide    = intent.getStringExtra(EXTRA_SIDE) ?: side
                if (newSize > 0) sizeDp = newSize
                opacity = newOpacity
                side    = newSide
                handler.post { applyConfig() }
            }
            ACTION_MUSIC -> {
                val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
                handler.post {
                    val st = if (playing) "dance" else "idle"
                    webView?.evaluateJavascript("window.setAikaState('$st')", null)
                }
            }
            ACTION_ANIM -> {
                val anim = intent.getStringExtra(EXTRA_ANIM) ?: "idle"
                handler.post {
                    webView?.evaluateJavascript("window.setAikaState('$anim')", null)
                }
            }
            ACTION_SWITCH_MODEL -> {
                val path = intent.getStringExtra(EXTRA_MODEL_PATH) ?: return START_STICKY
                handler.post {
                    // Передаём путь относительно assets — JS сам добавит BASE
                    webView?.evaluateJavascript("window.switchBuiltinModel('$path')", null)
                }
            }
        }
        return START_STICKY
    }

    private fun applyConfig() {
        val dp  = resources.displayMetrics.density
        val wPx = (sizeDp * dp).roundToInt()
        val hPx = (sizeDp * 1.55f * dp).roundToInt()

        params?.width  = wPx
        params?.height = hPx

        // Позиция: лево или право
        if (side == "right") {
            val screenW = resources.displayMetrics.widthPixels
            params?.x = screenW - wPx - (16 * dp).roundToInt()
        } else {
            params?.x = (16 * dp).roundToInt()
        }

        webView?.alpha = opacity

        try {
            rootFrame?.let { windowManager?.updateViewLayout(it, params) }
        } catch (e: Exception) {
            Log.w(TAG, "updateViewLayout: ${e.message}")
        }
    }

    // ── Notification ─────────────────────────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "Айка оверлей", NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Айка активна")
            .setContentText("Live2D аватар поверх экрана")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
}
