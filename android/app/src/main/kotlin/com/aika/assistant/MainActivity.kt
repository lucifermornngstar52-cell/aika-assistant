package com.aika.assistant

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aika.assistant/overlay"
    private var windowManager: WindowManager? = null
    private var overlayView: LinearLayout? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "requestPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "showOverlay" -> {
                    val message = call.argument<String>("message") ?: "Слушаю..."
                    showOverlay(message)
                    result.success(null)
                }
                "updateOverlay" -> {
                    val message = call.argument<String>("message") ?: ""
                    updateOverlay(message)
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
        } else true
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

    private fun showOverlay(message: String) {
        if (!hasOverlayPermission()) return
        hideOverlay()

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(Color.parseColor("#CC0D1120"))
            setPadding(32, 20, 32, 20)
        }

        // Neon blue dot
        val dot = TextView(this).apply {
            text = "●"
            textSize = 12f
            setTextColor(Color.parseColor("#FF00D4FF"))
            setPadding(0, 0, 16, 0)
        }

        val label = TextView(this).apply {
            text = message
            textSize = 14f
            setTextColor(Color.parseColor("#FFE8F4FF"))
        }

        layout.addView(dot)
        layout.addView(label)
        overlayView = layout

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = 120
        }

        try {
            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updateOverlay(message: String) {
        overlayView?.let { layout ->
            val label = layout.getChildAt(1) as? TextView
            label?.text = message
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
