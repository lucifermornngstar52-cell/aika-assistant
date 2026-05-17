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
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import kotlin.math.roundToInt
import kotlin.math.sin

class AikaOverlayService : Service() {

    companion object {
        const val ACTION_SHOW    = "com.aika.SHOW"
        const val ACTION_UPDATE  = "com.aika.UPDATE"
        const val ACTION_HIDE    = "com.aika.HIDE"
        const val EXTRA_STATE    = "state"
        private const val CHANNEL_ID = "aika_overlay_channel"
        private const val NOTIF_ID   = 1337

        var isRunning = false
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var avatarView: ImageView? = null
    private var params: WindowManager.LayoutParams? = null

    private val handler = Handler(Looper.getMainLooper())
    private var tick = 0L
    private val floatRunnable = object : Runnable {
        override fun run() {
            overlayRoot?.translationY = (sin(tick * 0.04) * 10).toFloat()
            tick++
            handler.postDelayed(this, 16)
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
                showOverlay(state)
            }
            ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                updateState(state)
            }
            ACTION_HIDE   -> hideOverlay()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Setup ─────────────────────────────────────────────────────────────────

    private fun setupOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = resources.displayMetrics.density
        val sizePx = (120 * density).roundToInt()

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
            y = (100 * density).roundToInt()
        }

        val frame = FrameLayout(this)
        val imageView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        frame.addView(imageView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Drag support
        var ix = 0; var iy = 0; var tx = 0f; var ty = 0f
        frame.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    ix = params!!.x; iy = params!!.y
                    tx = event.rawX; ty = event.rawY; true
                }
                MotionEvent.ACTION_MOVE -> {
                    params!!.x = ix + (event.rawX - tx).roundToInt()
                    params!!.y = iy + (event.rawY - ty).roundToInt()
                    try { windowManager?.updateViewLayout(frame, params) } catch (_: Exception) {}
                    true
                }
                else -> false
            }
        }

        overlayRoot = frame
        avatarView  = imageView

        setAvatar("idle")

        try {
            windowManager?.addView(frame, params)
            handler.post(floatRunnable)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ── State ─────────────────────────────────────────────────────────────────

    private fun showOverlay(state: String) {
        handler.post { setAvatar(state) }
    }

    private fun updateState(state: String) {
        handler.post { setAvatar(state) }
    }

    private fun hideOverlay() {
        // Don't actually remove — just switch back to idle so sprite stays visible
        handler.post { setAvatar("idle") }
    }

    private fun setAvatar(state: String) {
        val name = when (state) {
            "listening" -> "aika_listen.png"
            "thinking"  -> "aika_think.png"
            "greeting"  -> "aika_wave.png"
            else        -> "aika_idle.png"
        }
        loadAssetBitmap(name)?.let { avatarView?.setImageBitmap(it) }
    }

    private fun loadAssetBitmap(name: String): Bitmap? = try {
        assets.open("flutter_assets/assets/images/$name")
            .use { BitmapFactory.decodeStream(it) }
    } catch (e: Exception) { null }

    // ── Foreground notification ───────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Aika Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Aika floating assistant"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
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
        try {
            overlayRoot?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
