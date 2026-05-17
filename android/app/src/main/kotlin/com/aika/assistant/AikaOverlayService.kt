package com.aika.assistant

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.cos
import kotlin.math.abs

class AikaOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "com.aika.SHOW"
        const val ACTION_UPDATE = "com.aika.UPDATE"
        const val ACTION_HIDE   = "com.aika.HIDE"
        const val EXTRA_STATE   = "state"
        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337

        var isRunning = false
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var avatarView: ImageView? = null
    private var params: WindowManager.LayoutParams? = null

    private val handler = Handler(Looper.getMainLooper())
    private var currentState = "idle"
    private var animTick = 0L

    // Аниматоры
    private var floatAnimator: ValueAnimator? = null
    private var shakeAnimator: ValueAnimator? = null
    private var pulseAnimator: ObjectAnimator? = null
    private var autoReturnJob: Runnable? = null

    // Анимация покачивания — основная
    private val floatRunnable = object : Runnable {
        override fun run() {
            val view = overlayRoot ?: return
            when (currentState) {
                "idle" -> {
                    // Плавное парение: период ~2.4 сек
                    view.translationY = (sin(animTick * 0.025) * 9).toFloat()
                    // Лёгкий наклон
                    view.rotation = (sin(animTick * 0.018) * 2.5).toFloat()
                }
                "listening" -> {
                    // Быстрее пульсирует, сильнее наклон
                    view.translationY = (sin(animTick * 0.055) * 6).toFloat()
                    view.rotation = (sin(animTick * 0.055) * 5).toFloat()
                }
                "thinking" -> {
                    // Медленное покачивание влево-вправо
                    view.translationX = (sin(animTick * 0.020) * 8).toFloat()
                    view.translationY = (cos(animTick * 0.015) * 4).toFloat()
                    view.rotation = (sin(animTick * 0.020) * 3).toFloat()
                }
                "greeting" -> {
                    // Быстрое подпрыгивание
                    val bounce = abs(sin(animTick * 0.07)) * 14
                    view.translationY = -bounce.toFloat()
                    view.rotation = (sin(animTick * 0.07) * 8).toFloat()
                }
                else -> {
                    view.translationY = (sin(animTick * 0.025) * 9).toFloat()
                    view.rotation = 0f
                }
            }
            animTick++
            handler.postDelayed(this, 16) // 60fps
        }
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        setupOverlay()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW   -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                transitionToState(state)
            }
            ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                transitionToState(state)
            }
            ACTION_HIDE   -> transitionToState("idle")
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Setup ─────────────────────────────────────────────────────────────────

    private fun setupOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = resources.displayMetrics.density
        val sizePx = (110 * density).roundToInt()

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        params = WindowManager.LayoutParams(
            sizePx,
            (sizePx * 1.5).roundToInt(),
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (20 * density).roundToInt()
            y = (120 * density).roundToInt()
        }

        val frame = FrameLayout(this)
        val imageView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            alpha = 0f
        }
        frame.addView(imageView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Drag + tap support
        var ix = 0; var iy = 0; var tx = 0f; var ty = 0f
        var dragDist = 0f
        frame.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    ix = params!!.x; iy = params!!.y
                    tx = event.rawX; ty = event.rawY
                    dragDist = 0f
                    // Лёгкое сжатие при нажатии
                    v.animate().scaleX(0.88f).scaleY(0.88f).setDuration(120).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - tx
                    val dy = event.rawY - ty
                    dragDist = dx * dx + dy * dy
                    params!!.x = ix + dx.roundToInt()
                    params!!.y = iy + dy.roundToInt()
                    try { windowManager?.updateViewLayout(frame, params) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(200)
                        .setInterpolator(OvershootInterpolator()).start()
                    // Тап (без перетаскивания) — запускаем greeting
                    if (dragDist < 100f) {
                        playGreetingOnce()
                    }
                    true
                }
                else -> false
            }
        }

        overlayRoot = frame
        avatarView  = imageView

        loadAndSetBitmap("idle")

        try {
            windowManager?.addView(frame, params)
            // Появление с анимацией
            imageView.animate().alpha(1f).scaleX(1f).scaleY(1f)
                .setDuration(600).setInterpolator(OvershootInterpolator(1.2f)).start()
            handler.post(floatRunnable)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ── State machine ─────────────────────────────────────────────────────────

    private fun transitionToState(newState: String) {
        handler.post {
            // Отменяем авто-возврат если был запланирован
            autoReturnJob?.let { handler.removeCallbacks(it) }
            autoReturnJob = null

            // Плавная смена спрайта
            crossfadeTo(newState)

            // Авто-возврат в idle для временных состояний
            val autoReturnMs = when (newState) {
                "greeting" -> 3500L
                else       -> null
            }
            if (autoReturnMs != null) {
                val job = Runnable { transitionToState("idle") }
                autoReturnJob = job
                handler.postDelayed(job, autoReturnMs)
            }
        }
    }

    private fun crossfadeTo(newState: String) {
        val view = avatarView ?: return
        currentState = newState
        val bmp = loadBitmap(newState) ?: return

        // Fade out → swap → fade in
        view.animate().alpha(0f).setDuration(180).setListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                view.setImageBitmap(bmp)
                // Небольшой pop при смене состояния
                view.scaleX = 0.85f
                view.scaleY = 0.85f
                view.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(250)
                    .setInterpolator(OvershootInterpolator(1.5f))
                    .setListener(null)
                    .start()
            }
        }).start()
    }

    private fun playGreetingOnce() {
        // Shake + смена на wave спрайт
        overlayRoot?.let { v ->
            v.animate().scaleX(1.15f).scaleY(1.15f).setDuration(150).withEndAction {
                v.animate().scaleX(1f).scaleY(1f).setDuration(300)
                    .setInterpolator(OvershootInterpolator()).start()
            }.start()
        }
        transitionToState("greeting")
    }

    private fun showOverlay(state: String) = transitionToState(state)
    private fun updateState(state: String) = transitionToState(state)
    private fun hideOverlay() = transitionToState("idle")

    // ── Bitmap helpers ────────────────────────────────────────────────────────

    private fun loadBitmap(state: String): Bitmap? {
        val name = when (state) {
            "listening" -> "aika_listen.png"
            "thinking"  -> "aika_think.png"
            "greeting"  -> "aika_wave.png"
            else        -> "aika_idle.png"
        }
        return loadAssetBitmap(name)
    }

    private fun loadAndSetBitmap(state: String) {
        loadBitmap(state)?.let { avatarView?.setImageBitmap(it) }
    }

    private fun loadAssetBitmap(name: String): Bitmap? = try {
        assets.open("flutter_assets/assets/images/$name")
            .use { BitmapFactory.decodeStream(it) }
    } catch (e: Exception) {
        null
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Aika Overlay", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Aika floating assistant"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Айка активна")
            .setContentText("Нажми чтобы открыть")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(floatRunnable)
        autoReturnJob?.let { handler.removeCallbacks(it) }
        floatAnimator?.cancel()
        pulseAnimator?.cancel()
        shakeAnimator?.cancel()
        try { overlayRoot?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        super.onDestroy()
    }
}
