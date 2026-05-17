package com.aika.assistant

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aika.assistant/overlay"
    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var currentState: String = "idle"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasOverlayPermission())
                    "requestPermission" -> {
                        requestOverlayPermission()
                        result.success(null)
                    }
                    "showOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        showOverlay(state)
                        result.success(null)
                    }
                    "updateOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        updateOverlayState(state)
                        result.success(null)
                    }
                    "hideOverlay" -> {
                        hideOverlay()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    private fun getAssetBitmap(name: String): Bitmap? {
        return try {
            val assetManager = assets
            val inputStream = assetManager.open("flutter_assets/assets/images/$name")
            val bitmap = BitmapFactory.decodeStream(inputStream)
            inputStream.close()
            bitmap
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun showOverlay(state: String) {
        if (!hasOverlayPermission()) return
        hideOverlay()

        currentState = state
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val sizePx = 160
        val density = resources.displayMetrics.density
        val sizePxReal = (sizePx * density).roundToInt()
        val heightPxReal = (sizePx * 1.4 * density).roundToInt()

        val params = WindowManager.LayoutParams(
            sizePxReal,
            heightPxReal,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (50 * density).roundToInt()
            y = (120 * density).roundToInt()
        }
        overlayParams = params

        val frame = FrameLayout(this)

        val imageView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            tag = "avatar"
        }
        updateAvatarImage(imageView, state)

        frame.addView(
            imageView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        // Drag support
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f

        frame.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - initialTouchX).roundToInt()
                    params.y = initialY + (event.rawY - initialTouchY).roundToInt()
                    try {
                        windowManager?.updateViewLayout(frame, params)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    true
                }
                else -> false
            }
        }

        overlayView = frame

        // Floating animation
        val handler = Handler(Looper.getMainLooper())
        val animator = object : Runnable {
            var tick = 0
            override fun run() {
                if (overlayView == null) return
                try {
                    val floatOffset = (Math.sin(tick * 0.05) * 8).toFloat()
                    frame.translationY = floatOffset
                    tick++
                    handler.postDelayed(this, 16)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        handler.post(animator)

        try {
            windowManager?.addView(frame, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updateAvatarImage(imageView: ImageView, state: String) {
        val imageName = when (state) {
            "listening" -> "aika_listen.png"
            "thinking" -> "aika_think.png"
            "greeting" -> "aika_wave.png"
            else -> "aika_idle.png"
        }
        val bmp = getAssetBitmap(imageName)
        if (bmp != null) {
            imageView.setImageBitmap(bmp)
        }
    }

    private fun updateOverlayState(state: String) {
        currentState = state
        val frame = overlayView ?: return
        val imageView = frame.findViewWithTag<ImageView>("avatar") ?: return
        Handler(Looper.getMainLooper()).post {
            updateAvatarImage(imageView, state)
        }
    }

    private fun hideOverlay() {
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        overlayView = null
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }
}
