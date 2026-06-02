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
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.MethodChannel
import android.view.ScaleGestureDetector
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.max
import kotlin.math.min

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

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        initFlutterEngine()
        setupOverlay()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flutter Engine — ключевое: регистрируем все плагины (в т.ч. InAppWebView)
    // ─────────────────────────────────────────────────────────────────────────

    private fun initFlutterEngine() {
        // ВАЖНО: не переиспользуем engine из кэша если он уже attached к другому view.
        // Повторный attach → IllegalStateException → overlay пустой/чёрный.
        val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (cached != null) {
            if (cached.dartExecutor.isExecutingDart && flutterView == null) {
                flutterEngine = cached
                methodChannel = MethodChannel(cached.dartExecutor.binaryMessenger, FL_CHANNEL)
                return
            }
            try { cached.destroy() } catch (_: Exception) {}
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
        }

        val engine = FlutterEngine(this)
        GeneratedPluginRegister.registerGeneratedPlugins(engine)

        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
        }
        val bundlePath = loader.findAppBundlePath()

        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(bundlePath, "overlayMain")
        )

        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        flutterEngine = engine
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, FL_CHANNEL)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Overlay window
    // ─────────────────────────────────────────────────────────────────────────

    private fun setupOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density
        val w  = (280 * dp).roundToInt()
        val h  = (420 * dp).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        // FLAG_NOT_TOUCH_MODAL убран — он блокировал события до DraggableFrame
        params = WindowManager.LayoutParams(
            w, h, overlayType,
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

        // FlutterTextureView: единственный режим который работает в overlay
        // FlutterSurfaceView требует SurfaceHolder — в overlay окне не работает корректно
        val textureView = FlutterTextureView(this)
        val fv = FlutterView(this, textureView)
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
            if (overlayRoot?.windowToken != null) {
                try { windowManager?.removeView(overlayRoot) } catch (_: Exception) {}
            }
            windowManager?.addView(frame, params)
            handler.postDelayed({
                methodChannel?.invokeMethod("setState", currentState)
            }, 4000)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Commands
    // ─────────────────────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW, ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                handler.post {
                    currentState = state
                    // Если overlay окно пропало (например после перезагрузки) — пересоздаём
                    if (overlayRoot == null || overlayRoot?.windowToken == null) {
                        setupOverlay()
                    }
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
                        "size"    to size.toDouble(),
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

    // ─────────────────────────────────────────────────────────────────────────
    // Notification
    // ─────────────────────────────────────────────────────────────────────────

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
        handler.removeCallbacksAndMessages(null)
        try { flutterView?.detachFromFlutterEngine() } catch (_: Exception) {}
        try {
            overlayRoot?.let { v ->
                if (v.windowToken != null) windowManager?.removeView(v)
            }
        } catch (_: Exception) {}
        try {
            flutterEngine?.destroy()
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
        } catch (_: Exception) {}
        overlayRoot = null
        flutterView = null
        flutterEngine = null
        methodChannel = null
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DraggableFrame — drag/tap без FLAG_NOT_TOUCH_MODAL
    // ─────────────────────────────────────────────────────────────────────────

    inner class DraggableFrame(context: Context) : FrameLayout(context) {
        var onTap: (() -> Unit)? = null
        var getParamsAndWm: (() -> Pair<WindowManager.LayoutParams?, WindowManager?>)? = null

        private val DRAG_PX = (10 * context.resources.displayMetrics.density)
        private val dp = context.resources.displayMetrics.density

        private var downX = 0f
        private var downY = 0f
        private var startParamX = 0
        private var startParamY = 0
        private var isDragging = false
        private var baseW = 0
        private var baseH = 0

        // Scale gesture — pinch to resize overlay
        private val scaleDetector = ScaleGestureDetector(context,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScaleBegin(d: ScaleGestureDetector): Boolean {
                    val pair = getParamsAndWm?.invoke() ?: return false
                    baseW = pair.first?.width ?: return false
                    baseH = pair.first?.height ?: return false
                    return true
                }
                override fun onScale(d: ScaleGestureDetector): Boolean {
                    val pair = getParamsAndWm?.invoke() ?: return false
                    val p = pair.first ?: return false
                    val wm = pair.second ?: return false
                    val newW = (baseW * d.scaleFactor).toInt().coerceIn((80 * dp).toInt(), (400 * dp).toInt())
                    val newH = (newW * 1.5f).toInt()
                    p.width = newW
                    p.height = newH
                    try { wm.updateViewLayout(this@DraggableFrame, p) } catch (_: Exception) {}
                    return true
                }
            }
        )

        // Перехватываем touch только когда это точно drag (превышен порог)
        // Это позволяет WebView внутри получать tap/click события нормально
        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = ev.rawX
                    downY = ev.rawY
                    val pair = getParamsAndWm?.invoke()
                    startParamX = pair?.first?.x ?: 0
                    startParamY = pair?.first?.y ?: 0
                    isDragging = false
                    return false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!isDragging) {
                        val dx = abs(ev.rawX - downX)
                        val dy = abs(ev.rawY - downY)
                        isDragging = dx > DRAG_PX || dy > DRAG_PX
                    }
                    return isDragging // перехватываем только реальный drag
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val wasDragging = isDragging
                    isDragging = false
                    return wasDragging
                }
                else -> return false
            }
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            val pair = getParamsAndWm?.invoke() ?: return false
            val p = pair.first ?: return false
            val wm = pair.second ?: return false

            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    scaleDetector.onTouchEvent(ev)
                    downX = ev.rawX
                    downY = ev.rawY
                    startParamX = p.x
                    startParamY = p.y
                    isDragging = false
                    if (ev.pointerCount == 1) {
                        animate().scaleX(0.93f).scaleY(0.93f).setDuration(80).start()
                    }
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    scaleDetector.onTouchEvent(ev)
                    if (ev.pointerCount >= 2) {
                        // Pinch — только масштаб, не drag
                        return true
                    }
                    val dx = ev.rawX - downX
                    val dy = ev.rawY - downY
                    if (!isDragging && (abs(dx) > DRAG_PX || abs(dy) > DRAG_PX)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        // Ограничиваем позицию экраном
                        val screenW = resources.displayMetrics.widthPixels
                        val screenH = resources.displayMetrics.heightPixels
                        p.x = (startParamX + dx).roundToInt().coerceIn(0, screenW - p.width)
                        p.y = (startParamY + dy).roundToInt().coerceIn(0, screenH - p.height)
                        try { wm.updateViewLayout(this, p) } catch (_: Exception) {}
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    scaleDetector.onTouchEvent(ev)
                    animate().scaleX(1f).scaleY(1f).setDuration(200)
                        .setInterpolator(OvershootInterpolator()).start()
                    if (!isDragging) {
                        onTap?.invoke()
                    } else {
                        // Snap to nearest edge
                        val screenW = resources.displayMetrics.widthPixels
                        val midX = screenW / 2
                        val targetX = if (p.x + p.width / 2 < midX) (8 * dp).toInt()
                                      else screenW - p.width - (8 * dp).toInt()
                        // Плавная анимация к краю
                        val startX = p.x
                        val anim = android.animation.ValueAnimator.ofInt(startX, targetX)
                        anim.duration = 250
                        anim.interpolator = android.view.animation.DecelerateInterpolator()
                        anim.addUpdateListener { va ->
                            p.x = va.animatedValue as Int
                            try { wm.updateViewLayout(this, p) } catch (_: Exception) {}
                        }
                        anim.start()
                    }
                    isDragging = false
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    isDragging = false
                    return true
                }
                else -> return false
            }
        }
    }
}
