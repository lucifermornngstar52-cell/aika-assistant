package com.aika.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import kotlin.math.roundToInt
import kotlin.math.abs

/**
 * AikaOverlayService — нативный Android overlay.
 * Отображает PNG-спрайт аватара поверх всех приложений.
 * НЕ использует второй FlutterEngine — работает стабильно.
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
        const val ENGINE_ID     = "live2d_overlay_engine"  // оставляем для совместимости

        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337
        private const val TAG        = "AikaOverlay"

        var isRunning = false
    }

    private val handler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var avatarView: ImageView? = null
    private var params: WindowManager.LayoutParams? = null

    private var currentState = "idle"
    private var sizeDp = 160f
    private var opacity = 1f
    private var side = "left"

    // Анимация спрайтов
    private var frameRunnable: Runnable? = null
    private var frames: List<Bitmap> = emptyList()
    private var frameIndex = 0
    private var frameDelay = 80L

    // Drag
    private var dragInitX = 0; private var dragInitY = 0
    private var dragTouchX = 0f; private var dragTouchY = 0f
    private var isDragging = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        setupOverlayWindow()
        Log.d(TAG, "Service created")
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        stopAnimation()
        try { overlayView?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        overlayView = null
        Log.d(TAG, "Service destroyed")
    }

    private fun setupOverlayWindow() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density
        val sizePx = (sizeDp * dp).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        params = WindowManager.LayoutParams(
            sizePx, (sizePx * 1.5f).roundToInt(),
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSPARENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (16 * dp).roundToInt()
            y = (120 * dp).roundToInt()
        }

        // ImageView для спрайта
        val iv = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            alpha = opacity
        }
        avatarView = iv

        val frame = FrameLayout(this)
        frame.setBackgroundColor(Color.TRANSPARENT)
        frame.addView(iv, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Drag + tap
        var downTime = 0L
        frame.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isDragging = false
                    downTime = System.currentTimeMillis()
                    dragInitX = params?.x ?: 0
                    dragInitY = params?.y ?: 0
                    dragTouchX = event.rawX
                    dragTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - dragTouchX
                    val dy = event.rawY - dragTouchY
                    if (abs(dx) > 8 || abs(dy) > 8) isDragging = true
                    if (isDragging) {
                        params?.x = (dragInitX + dx).roundToInt()
                        params?.y = (dragInitY + dy).roundToInt()
                        try { overlayView?.let { windowManager?.updateViewLayout(it, params) } }
                        catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging && System.currentTimeMillis() - downTime < 300) {
                        onTapped()
                    }
                    true
                }
                else -> false
            }
        }

        overlayView = frame
        try {
            windowManager?.addView(frame, params)
            loadAndPlayState("idle")
        } catch (e: Exception) {
            Log.e(TAG, "addView failed: ${e.message}")
        }
    }

    private fun onTapped() {
        loadAndPlayState("greeting")
        handler.postDelayed({ loadAndPlayState("idle") }, 2500)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW, ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                currentState = state
                handler.post {
                    if (overlayView == null || overlayView?.windowToken == null) {
                        setupOverlayWindow()
                    }
                    loadAndPlayState(state)
                }
            }
            ACTION_HIDE -> handler.post {
                // Не прячем окно — просто возвращаем idle
                currentState = "idle"
                loadAndPlayState("idle")
            }
            ACTION_CONFIG -> {
                val newSize    = intent.getFloatExtra(EXTRA_SIZE, 0f)
                val newOpacity = intent.getFloatExtra(EXTRA_OPACITY, 1f)
                val newSide    = intent.getStringExtra(EXTRA_SIDE) ?: side
                handler.post { applyConfig(newSize, newOpacity, newSide) }
            }
            ACTION_MUSIC -> {
                val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
                handler.post { loadAndPlayState(if (playing) "dance" else "idle") }
            }
            ACTION_ANIM -> {
                val anim = intent.getStringExtra(EXTRA_ANIM) ?: "idle"
                handler.post { loadAndPlayState(anim) }
            }
        }
        return START_STICKY
    }

    // ─── Спрайт-анимация ─────────────────────────────────────────────────────

    private fun loadAndPlayState(state: String) {
        stopAnimation()
        val bitmaps = loadSpritesForState(state)
        if (bitmaps.isEmpty()) {
            Log.w(TAG, "No sprites for state=$state, trying idle")
            val idle = loadSpritesForState("idle")
            if (idle.isNotEmpty()) {
                frames = idle
                avatarView?.setImageBitmap(idle.first())
            }
            return
        }
        frames = bitmaps
        frameIndex = 0
        frameDelay = when (state) {
            "dance", "greeting" -> 60L
            "thinking"          -> 100L
            else                -> 80L
        }
        playFrames()
    }

    private fun loadSpritesForState(state: String): List<Bitmap> {
        // Маппинг состояний → имя спрайта в assets/images/
        val prefix = when (state) {
            "idle"      -> "aika_idle"
            "listening" -> "aika_listen"
            "thinking"  -> "aika_think"
            "talking"   -> "aika_idle"
            "greeting"  -> "aika_idle"
            "dance"     -> "aika_dance"
            "sad"       -> "aika_idle"
            else        -> "aika_idle"
        }

        val result = mutableListOf<Bitmap>()
        val am = assets

        // Пробуем multi-frame (1..15)
        for (i in 1..15) {
            try {
                val bm = am.open("images/${prefix}${i}.png").use { BitmapFactory.decodeStream(it) }
                if (bm != null) result.add(bm)
            } catch (_: Exception) { break }
        }

        // Если нет multi-frame — пробуем single файл
        if (result.isEmpty()) {
            try {
                val bm = am.open("images/${prefix}.png").use { BitmapFactory.decodeStream(it) }
                if (bm != null) result.add(bm)
            } catch (_: Exception) {}
        }

        Log.d(TAG, "Loaded ${result.size} frames for state=$state (prefix=$prefix)")
        return result
    }

    private fun playFrames() {
        if (frames.isEmpty()) return
        val runnable = object : Runnable {
            override fun run() {
                if (frames.isEmpty()) return
                avatarView?.setImageBitmap(frames[frameIndex % frames.size])
                frameIndex = (frameIndex + 1) % frames.size
                handler.postDelayed(this, frameDelay)
            }
        }
        frameRunnable = runnable
        handler.post(runnable)
    }

    private fun stopAnimation() {
        frameRunnable?.let { handler.removeCallbacks(it) }
        frameRunnable = null
    }

    private fun applyConfig(newSizeDp: Float, newOpacity: Float, newSide: String) {
        if (newSizeDp > 0) sizeDp = newSizeDp
        opacity = newOpacity
        side = newSide

        val dp = resources.displayMetrics.density
        val sizePx = (sizeDp * dp).roundToInt()
        params?.let { p ->
            p.width = sizePx
            p.height = (sizePx * 1.5f).roundToInt()
            val screenW = resources.displayMetrics.widthPixels
            p.x = if (side == "right") screenW - sizePx - (16 * dp).roundToInt()
                  else (16 * dp).roundToInt()
            try { overlayView?.let { windowManager?.updateViewLayout(it, p) } }
            catch (_: Exception) {}
        }
        avatarView?.alpha = opacity
    }

    // ─── Notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Aika Overlay",
                NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false)
                setSound(null, null)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Aika активна")
            .setContentText("Нажми чтобы открыть")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }
}
