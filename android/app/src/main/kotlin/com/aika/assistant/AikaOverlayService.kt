package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt
import kotlin.math.abs

class AikaOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "com.aika.SHOW"
        const val ACTION_UPDATE = "com.aika.UPDATE"
        const val ACTION_HIDE   = "com.aika.HIDE"
        const val ACTION_CONFIG = "com.aika.CONFIG"
        const val EXTRA_STATE   = "state"
        const val EXTRA_SIZE    = "size"
        const val EXTRA_SIDE    = "side"
        const val EXTRA_OPACITY = "opacity"
        const val ENGINE_ID     = "live2d_overlay_engine"

        private const val CHANNEL_ID  = "aika_overlay_channel"
        private const val NOTIF_ID    = 1337
        private const val FL_CHANNEL  = "com.aika.assistant/live2d_overlay"

        // entry-point name должен совпадать с @pragma('vm:entry-point') в main_overlay.dart
        private const val DART_ENTRYPOINT = "overlayMain"

        var isRunning = false
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
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
        // ⚡ Вызываем overlayMain — entry-point из main_overlay.dart
        val bundlePath = DartExecutor.DartEntrypoint.createDefault().appBundlePath ?: ""
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(bundlePath, DART_ENTRYPOINT)
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        flutterEngine = engine
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, FL_CHANNEL)
    }

    // ── Overlay ───────────────────────────────────────────────────────────────

    private fun setupOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density
        val w  = (170 * dp).roundToInt()
        val h  = (255 * dp).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        // ⚡ Убираем FLAG_NOT_TOUCH_MODAL — он перехватывал тач раньше View
        params = WindowManager.LayoutParams(
            w, h,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (20 * dp).roundToInt()
            y = (120 * dp).roundToInt()
        }

        val engine = flutterEngine ?: return

        val fv = FlutterView(this)
        fv.attachToFlutterEngine(engine)
        fv.alpha = 0f

        // ⚡ Собственный FrameLayout с правильным touch-обработчиком
        val frame = object : FrameLayout(this) {
            private var startX = 0f
            private var startY = 0f
            private var startParamX = 0
            private var startParamY = 0
            private var isDragging = false
            private val DRAG_THRESHOLD = 8f  // px

            override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
                // Перехватываем только MOVE после порога
                return when (ev.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = ev.rawX; startY = ev.rawY
                        startParamX = params!!.x; startParamY = params!!.y
                        isDragging = false
                        false  // не перехватываем пока не убедились что это drag
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (!isDragging) {
                            val dx = abs(ev.rawX - startX)
                            val dy = abs(ev.rawY - startY)
                            isDragging = dx > DRAG_THRESHOLD || dy > DRAG_THRESHOLD
                        }
                        isDragging
                    }
                    else -> false
                }
            }

            override fun onTouchEvent(ev: MotionEvent): Boolean {
                when (ev.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = ev.rawX; startY = ev.rawY
                        startParamX = params!!.x; startParamY = params!!.y
                        isDragging = false
                        animate().scaleX(0.9f).scaleY(0.9f).setDuration(80).start()
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = ev.rawX - startX
                        val dy = ev.rawY - startY
                        if (!isDragging && (abs(dx) > DRAG_THRESHOLD || abs(dy) > DRAG_THRESHOLD)) {
                            isDragging = true
                        }
                        if (isDragging) {
                            params!!.x = (startParamX + dx).roundToInt()
                            params!!.y = (startParamY + dy).roundToInt()
                            try {
                                windowManager?.updateViewLayout(this, params)
                            } catch (_: Exception) {}
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        animate().scaleX(1f).scaleY(1f).setDuration(200)
                            .setInterpolator(OvershootInterpolator()).start()
                        if (!isDragging) {
                            // Это тап — сообщаем Flutter
                            methodChannel?.invokeMethod("onTap", null)
                        }
                        isDragging = false
                        return true
                    }
                }
                return false
            }
        }

        frame.addView(fv, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        overlayRoot = frame
        flutterView = fv

        try {
            windowManager?.addView(frame, params)
            // Плавное появление через 1с (модель должна успеть загрузиться)
            handler.postDelayed({
                fv.animate().alpha(1f).setDuration(600).start()
                methodChannel?.invokeMethod("setState", currentState)
            }, 1200)
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
                val size  = intent.getFloatExtra(EXTRA_SIZE, 170f)
                val side  = intent.getStringExtra(EXTRA_SIDE) ?: "left"
                val alpha = intent.getFloatExtra(EXTRA_OPACITY, 1f)
                handler.post { applyWindowConfig(size, side, alpha) }
            }
        }
        return START_STICKY
    }

    fun applyWindowConfig(sizeDp: Float, side: String, alpha: Float) {
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
        flutterView?.alpha = alpha
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
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        super.onDestroy()
    }
}
