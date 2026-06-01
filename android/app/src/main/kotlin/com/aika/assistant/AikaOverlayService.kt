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
        val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (cached != null && cached.dartExecutor.isExecutingDart) {
            flutterEngine = cached
            methodChannel = MethodChannel(cached.dartExecutor.binaryMessenger, FL_CHANNEL)
            return
        }

        val engine = FlutterEngine(this)

        // ⚡ КРИТИЧНО: регистрируем все плагины в overlay engine
        // Без этого flutter_inappwebview не работает — WebView пустой
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
            windowManager?.addView(frame, params)
            // Даём WebView время инициализироваться (3 сек) перед отправкой команд
            handler.postDelayed({
                methodChannel?.invokeMethod("setState", currentState)
            }, 3000)
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
        try {
            flutterView?.detachFromFlutterEngine()
            overlayRoot?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DraggableFrame — drag/tap без FLAG_NOT_TOUCH_MODAL
    // ─────────────────────────────────────────────────────────────────────────

    inner class DraggableFrame(context: Context) : FrameLayout(context) {
        var onTap: (() -> Unit)? = null
        var getParamsAndWm: (() -> Pair<WindowManager.LayoutParams?, WindowManager?>)? = null

        // Порог в пикселях — меньше этого считается тапом, больше — drag
        private val DRAG_PX = (10 * context.resources.displayMetrics.density)

        private var downX = 0f
        private var downY = 0f
        private var startParamX = 0
        private var startParamY = 0
        private var isDragging = false

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
                    return false // не перехватываем DOWN — WebView должен его получить
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
                    downX = ev.rawX
                    downY = ev.rawY
                    startParamX = p.x
                    startParamY = p.y
                    isDragging = false
                    animate().scaleX(0.93f).scaleY(0.93f).setDuration(80).start()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - downX
                    val dy = ev.rawY - downY
                    if (!isDragging && (abs(dx) > DRAG_PX || abs(dy) > DRAG_PX)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        p.x = (startParamX + dx).roundToInt()
                        p.y = (startParamY + dy).roundToInt()
                        try { wm.updateViewLayout(this, p) } catch (_: Exception) {}
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    animate().scaleX(1f).scaleY(1f).setDuration(200)
                        .setInterpolator(OvershootInterpolator()).start()
                    if (!isDragging) onTap?.invoke()
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
