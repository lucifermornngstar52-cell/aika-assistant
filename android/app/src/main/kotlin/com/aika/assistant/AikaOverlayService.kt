package com.aika.assistant

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
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

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
        const val ENGINE_ID     = "live2d_overlay_engine"

        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337
        private const val FL_CHANNEL = "com.aika.assistant/live2d_overlay"

        var isRunning = false
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: DraggableFrame? = null
    private var flutterView: FlutterView? = null
    private var params: WindowManager.LayoutParams? = null
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var currentState = "idle"

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        initFlutterEngine()
        setupOverlay()
    }

    // ── Flutter Engine ────────────────────────────────────────────────────────

    private fun initFlutterEngine() {
        val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (cached != null && cached.dartExecutor.isExecutingDart) {
            flutterEngine = cached
            methodChannel = MethodChannel(cached.dartExecutor.binaryMessenger, FL_CHANNEL)
            return
        }
        val engine = FlutterEngine(this)
        val loader = FlutterInjector.instance().flutterLoader()
        val bundlePath = loader.findAppBundlePath()
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(bundlePath, "overlayMain")
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        flutterEngine = engine
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, FL_CHANNEL)
    }

    // ── Overlay ───────────────────────────────────────────────────────────────

    private fun setupOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density
        val w  = (280 * dp).roundToInt()
        val h  = (420 * dp).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        params = WindowManager.LayoutParams(
            w, h, overlayType,
            // ⚡ Убираем FLAG_NOT_TOUCH_MODAL — он поглощал все touch события
            // FLAG_NOT_FOCUSABLE оставляем — не перехватываем клавиатуру
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSPARENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (16 * dp).roundToInt()
            y = (100 * dp).roundToInt()
        }

        val engine = flutterEngine ?: return
        val surfaceView = FlutterSurfaceView(this, true)
        val fv = FlutterView(this, surfaceView)
        fv.setBackgroundColor(Color.TRANSPARENT)
        fv.attachToFlutterEngine(engine)

        val frame = DraggableFrame(this)
        frame.setBackgroundColor(Color.TRANSPARENT)
        frame.addView(fv, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
        frame.onTap = { methodChannel?.invokeMethod("onTap", null) }
        frame.getParamsAndWm = { Pair(params, windowManager) }

        overlayRoot = frame
        flutterView = fv

        try {
            windowManager?.addView(frame, params)
            // Отправляем начальное состояние после инициализации WebView (3 сек)
            handler.postDelayed({
                methodChannel?.invokeMethod("setState", currentState)
            }, 3000)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ── Commands ──────────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW, ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                handler.post {
                    currentState = state
                    methodChannel?.invokeMethod("setState", state)
                }
            }
            ACTION_HIDE -> handler.post {
                currentState = "idle"
                methodChannel?.invokeMethod("setState", "idle")
            }
            ACTION_CONFIG -> {
                val size    = intent.getFloatExtra(EXTRA_SIZE, 0f)
                val opacity = intent.getFloatExtra(EXTRA_OPACITY, 1f)
                val side    = intent.getStringExtra(EXTRA_SIDE) ?: "left"
                handler.post {
                    applyWindowConfig(size, opacity, side)
                    methodChannel?.invokeMethod("setConfig", mapOf(
                        "size" to size.toDouble(),
                        "opacity" to opacity.toDouble()
                    ))
                }
            }
            ACTION_MUSIC -> {
                val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
                handler.post { methodChannel?.invokeMethod("setMusicPlaying", playing) }
            }
            ACTION_ANIM -> {
                val anim = intent.getStringExtra(EXTRA_ANIM) ?: "idle"
                handler.post { methodChannel?.invokeMethod("playAnimation", anim) }
            }
        }
        return START_STICKY
    }

    private fun applyWindowConfig(sizeDp: Float, opacity: Float, side: String) {
        if (sizeDp <= 0f) return
        val dp = resources.displayMetrics.density
        val w  = (sizeDp * dp).toInt()
        val h  = (sizeDp * 1.5f * dp).toInt()
        params?.let { p ->
            p.width  = w
            p.height = h
            val screenW = resources.displayMetrics.widthPixels
            p.x = if (side == "right") screenW - w - (16 * dp).toInt() else (16 * dp).toInt()
            try { overlayRoot?.let { windowManager?.updateViewLayout(it, p) } }
            catch (_: Exception) {}
        }
        flutterView?.alpha = opacity
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "Aika Overlay", NotificationManager.IMPORTANCE_LOW
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
            .setContentText("Нажми чтобы открыть")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true).setSilent(true).build()
    }

    override fun onDestroy() {
        isRunning = false
        try {
            flutterView?.detachFromFlutterEngine()
            overlayRoot?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        super.onDestroy()
    }

    // ── DraggableFrame ────────────────────────────────────────────────────────

    /**
     * Собственный FrameLayout с правильной обработкой drag/tap.
     * Ключевое: onInterceptTouchEvent перехватывает события ТОЛЬКО когда
     * пользователь реально двигает пальцем (drag threshold 10px).
     * Это позволяет WebView внутри получать tap события напрямую.
     */
    inner class DraggableFrame(context: Context) : FrameLayout(context) {
        var onTap: (() -> Unit)? = null
        var getParamsAndWm: (() -> Pair<WindowManager.LayoutParams?, WindowManager?>)? = null

        private val DRAG_THRESHOLD = 10f * context.resources.displayMetrics.density

        private var downX = 0f
        private var downY = 0f
        private var startParamX = 0
        private var startParamY = 0
        private var isDragging = false

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            return when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = ev.rawX
                    downY = ev.rawY
                    val (p, _) = getParamsAndWm?.invoke() ?: return false
                    startParamX = p?.x ?: 0
                    startParamY = p?.y ?: 0
                    isDragging = false
                    false // не перехватываем — пусть дочерние views получат DOWN
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!isDragging) {
                        val dx = abs(ev.rawX - downX)
                        val dy = abs(ev.rawY - downY)
                        if (dx > DRAG_THRESHOLD || dy > DRAG_THRESHOLD) {
                            isDragging = true
                        }
                    }
                    isDragging // перехватываем только когда точно drag
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isDragging = false
                    false
                }
                else -> false
            }
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            val (p, wm) = getParamsAndWm?.invoke() ?: return false
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = ev.rawX
                    downY = ev.rawY
                    startParamX = p?.x ?: 0
                    startParamY = p?.y ?: 0
                    isDragging = false
                    animate().scaleX(0.92f).scaleY(0.92f).setDuration(80).start()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - downX
                    val dy = ev.rawY - downY
                    if (!isDragging && (abs(dx) > DRAG_THRESHOLD || abs(dy) > DRAG_THRESHOLD)) {
                        isDragging = true
                    }
                    if (isDragging && p != null) {
                        p.x = (startParamX + dx).roundToInt()
                        p.y = (startParamY + dy).roundToInt()
                        try { wm?.updateViewLayout(this, p) } catch (_: Exception) {}
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    animate().scaleX(1f).scaleY(1f).setDuration(200)
                        .setInterpolator(OvershootInterpolator()).start()
                    if (!isDragging) {
                        onTap?.invoke()
                    }
                    isDragging = false
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    isDragging = false
                    return true
                }
            }
            return false
        }
    }
}
