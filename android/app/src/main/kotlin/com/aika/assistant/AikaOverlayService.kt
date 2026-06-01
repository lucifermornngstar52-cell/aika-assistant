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

class AikaOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "com.aika.SHOW"
        const val ACTION_UPDATE = "com.aika.UPDATE"
        const val ACTION_HIDE   = "com.aika.HIDE"
        const val EXTRA_STATE   = "state"
        const val ENGINE_ID     = "live2d_overlay_engine"
        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337
        private const val FL_CHANNEL = "com.aika.assistant/live2d_overlay"

        var isRunning = false

        const val ACTION_CONFIG  = "com.aika.CONFIG"
        const val EXTRA_SIZE     = "size"
        const val EXTRA_SIDE     = "side"
        const val EXTRA_OPACITY  = "opacity"
        const val ACTION_MUSIC   = "com.aika.MUSIC"
        const val ACTION_ANIM    = "com.aika.ANIM"
        const val EXTRA_PLAYING  = "playing"
        const val EXTRA_ANIM     = "anim_name"
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var flutterView: FlutterView? = null
    private var params: WindowManager.LayoutParams? = null
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var currentState = "idle"

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        initFlutterEngine()
        setupOverlay()
    }

    // ── Flutter Engine — запускаем overlayMain() ──────────────────────────────
    private fun initFlutterEngine() {
        val cached = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (cached != null) {
            flutterEngine = cached
            methodChannel = MethodChannel(cached.dartExecutor.binaryMessenger, FL_CHANNEL)
            return
        }
        val engine = FlutterEngine(this)
        // Запускаем overlayMain() из lib/main_overlay.dart
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                applicationContext.assets,
                "lib/main_overlay.dart",
                "overlayMain"
            )
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        flutterEngine = engine
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, FL_CHANNEL)
    }

    // ── Overlay Window ────────────────────────────────────────────────────────
    private fun setupOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density
        val w = (170 * dp).roundToInt()
        val h = (255 * dp).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        params = WindowManager.LayoutParams(
            w, h, overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
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

        val frame = FrameLayout(this)
        frame.addView(fv, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        var ix = 0; var iy = 0; var tx = 0f; var ty = 0f; var dragDist = 0f
        frame.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    ix = params!!.x; iy = params!!.y
                    tx = event.rawX; ty = event.rawY; dragDist = 0f
                    v.animate().scaleX(0.88f).scaleY(0.88f).setDuration(100).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - tx; val dy = event.rawY - ty
                    dragDist = dx * dx + dy * dy
                    params!!.x = (ix + dx).roundToInt()
                    params!!.y = (iy + dy).roundToInt()
                    try { windowManager?.updateViewLayout(frame, params) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(200)
                        .setInterpolator(OvershootInterpolator()).start()
                    if (dragDist < 100f) methodChannel?.invokeMethod("onTap", null)
                    true
                }
                else -> false
            }
        }

        overlayRoot = frame
        flutterView = fv

        try {
            windowManager?.addView(frame, params)
            handler.postDelayed({
                fv.animate().alpha(1f).setDuration(600).start()
                methodChannel?.invokeMethod("setState", currentState)
            }, 1500)
        } catch (e: Exception) { e.printStackTrace() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW, ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                handler.post { currentState = state; methodChannel?.invokeMethod("setState", state) }
            }
            ACTION_HIDE -> handler.post { currentState = "idle"; methodChannel?.invokeMethod("setState", "idle") }
            ACTION_CONFIG -> {
                val size  = intent.getFloatExtra(EXTRA_SIZE, 170f)
                val side  = intent.getStringExtra(EXTRA_SIDE) ?: "left"
                val alpha = intent.getFloatExtra(EXTRA_OPACITY, 1f)
                handler.post { applyWindowConfig(size, side, alpha) }
            }
            ACTION_MUSIC -> {
                val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
                handler.post {
                    methodChannel?.invokeMethod("setMusicPlaying", playing)
                    if (playing) currentState = "dance" else if (currentState == "dance") currentState = "idle"
                }
            }
            ACTION_ANIM -> {
                val animName = intent.getStringExtra(EXTRA_ANIM) ?: "idle"
                handler.post { methodChannel?.invokeMethod("playAnimation", animName) }
            }
        }
        return START_STICKY
    }

    fun applyWindowConfig(sizeDp: Float, side: String, alpha: Float) {
        val dp = resources.displayMetrics.density
        val w = (sizeDp * dp).toInt(); val h = (sizeDp * 1.5f * dp).toInt()
        params?.let { p ->
            p.width = w; p.height = h
            val screenW = resources.displayMetrics.widthPixels
            p.x = if (side == "right") screenW - w - (16 * dp).toInt() else (16 * dp).toInt()
            try { overlayRoot?.let { windowManager?.updateViewLayout(it, p) } } catch (_: Exception) {}
        }
        flutterView?.alpha = alpha
        methodChannel?.invokeMethod("setConfig", mapOf("size" to sizeDp, "opacity" to alpha, "mirror" to (side == "right")))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Aika Overlay", NotificationManager.IMPORTANCE_LOW)
                .apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val pi = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Айка активна").setContentText("Нажми чтобы открыть")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi).setOngoing(true).setSilent(true).build()
    }

    override fun onDestroy() {
        isRunning = false
        try { flutterView?.detachFromFlutterEngine(); overlayRoot?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        super.onDestroy()
    }
}
