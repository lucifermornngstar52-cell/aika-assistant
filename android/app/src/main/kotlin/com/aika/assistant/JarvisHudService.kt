package com.aika.assistant

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import androidx.core.app.NotificationCompat
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * JarvisHudService — Iron Man HUD overlay.
 * Рисуется через Canvas прямо в WindowManager (SYSTEM_ALERT_WINDOW).
 * Не блокирует касания (FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCHABLE),
 * исчезает на FLAG_SECURE экранах автоматически.
 *
 * Триггеры:
 *   ACTION_SHOW_TARGET  + EXTRA_X + EXTRA_Y — показать прицел в координатах тапа
 *   ACTION_SHOW         — показать фоновый HUD (скобки, сканирование, статус)
 *   ACTION_HIDE         — скрыть HUD
 *   ACTION_STATUS       + EXTRA_TEXT — обновить строку статуса
 */
class JarvisHudService : Service() {

    companion object {
        const val ACTION_SHOW         = "com.aika.HUD_SHOW"
        const val ACTION_HIDE         = "com.aika.HUD_HIDE"
        const val ACTION_SHOW_TARGET  = "com.aika.HUD_TARGET"
        const val ACTION_STATUS       = "com.aika.HUD_STATUS"
        const val ACTION_PULSE        = "com.aika.HUD_PULSE"   // короткая вспышка

        const val EXTRA_X = "x"
        const val EXTRA_Y = "y"
        const val EXTRA_TEXT = "text"

        const val CHANNEL_ID = "jarvis_hud"
        const val NOTIF_ID = 7771

        // Iron Man палитра
        const val COL_RED     = 0xFFFF3131.toInt()
        const val COL_GOLD    = 0xFFFFD700.toInt()
        const val COL_CYAN    = 0xFF00CFFF.toInt()
        const val COL_WHITE   = 0xFFF0F0F0.toInt()
        const val COL_DIM     = 0x66FF3131.toInt()
        const val COL_DIM_GOLD= 0x55FFD700.toInt()
        const val COL_DIM_CYAN= 0x4400CFFF.toInt()

        @Volatile private var instance: JarvisHudService? = null
        fun showTarget(x: Float, y: Float) {
            instance?.let {
                val i = Intent(it, JarvisHudService::class.java)
                    .setAction(ACTION_SHOW_TARGET)
                    .putExtra(EXTRA_X, x)
                    .putExtra(EXTRA_Y, y)
                it.startService(i)
            }
        }
        fun showStatus(text: String) {
            instance?.let {
                val i = Intent(it, JarvisHudService::class.java)
                    .setAction(ACTION_STATUS)
                    .putExtra(EXTRA_TEXT, text)
                it.startService(i)
            }
        }
        fun showBackground() {
            instance?.let {
                val i = Intent(it, JarvisHudService::class.java).setAction(ACTION_SHOW)
                it.startService(i)
            }
        }
        fun hide() {
            instance?.let {
                val i = Intent(it, JarvisHudService::class.java).setAction(ACTION_HIDE)
                it.startService(i)
            }
        }
    }

    private var wm: WindowManager? = null
    private var hudView: HudView? = null
    private var params: WindowManager.LayoutParams? = null
    private var statusText: String = "J.A.R.V.I.S. ONLINE"
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        startForeground(NOTIF_ID, buildNotification("J.A.R.V.I.S. HUD активен"))
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        Log.d("JarvisHUD", "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW        -> showHud()
            ACTION_HIDE        -> hideHud()
            ACTION_SHOW_TARGET -> {
                val x = intent.getFloatExtra(EXTRA_X, -1f)
                val y = intent.getFloatExtra(EXTRA_Y, -1f)
                if (x >= 0 && y >= 0) triggerTarget(x, y)
            }
            ACTION_STATUS      -> {
                statusText = intent.getStringExtra(EXTRA_TEXT) ?: statusText
                hudView?.setStatusText(statusText)
            }
            ACTION_PULSE        -> hudView?.pulse()
            null               -> showHud()
        }
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "JARVIS HUD", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Iron Man HUD overlay"
                setShowBadge(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("J.A.R.V.I.S.")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showHud() {
        if (hudView != null) return
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0; y = 0
        }
        params = p
        val v = HudView(this)
        hudView = v
        v.setStatusText(statusText)
        try {
            wm?.addView(v, p)
            Log.d("JarvisHUD", "View added")
        } catch (e: Exception) {
            Log.e("JarvisHUD", "addView failed: ${e.message}")
        }
    }

    private fun hideHud() {
        hudView?.let { 
            try { wm?.removeView(it) } catch (_: Exception) {}
        }
        hudView = null
    }

    private fun triggerTarget(x: Float, y: Float) {
        if (hudView == null) showHud()
        hudView?.triggerTarget(x, y)
    }

    override fun onDestroy() {
        hideHud()
        instance = null
        super.onDestroy()
    }

    // ════════════════════════════════════════════════════════════════
    //  HudView — Canvas-based Iron Man HUD
    // ════════════════════════════════════════════════════════════════
    private class HudView(ctx: Context) : View(ctx) {
        private val density = ctx.resources.displayMetrics.density
        private val W get() = width.toFloat()
        private val H get() = height.toFloat()

        // Состояние
        private var statusText: String = "J.A.R.V.I.S. ONLINE"
        private var targetX: Float = -1f
        private var targetY: Float = -1f
        private var targetAlpha: Float = 0f
        private var targetRadius: Float = 0f
        private var targetLockProgress: Float = 0f   // 0..1
        private var sweepAngle: Float = 0f           // сканлайн
        private var ringRotation: Float = 0f         // вращение центрального кольца
        private var pulseAlpha: Float = 0f
        private var bgAlpha: Float = 0.85f

        // Аниматоры
        private val choreographer = Choreographer.getInstance()
        private var lastFrameNanos: Long = 0
        private var isRunning = true

        // Пэйнты — переиспользуем
        private val pRedThin = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_RED; style = Paint.Style.STROKE; strokeWidth = 2f * density
        }
        private val pRedBold = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_RED; style = Paint.Style.STROKE; strokeWidth = 3.5f * density
        }
        private val pGoldThin = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_GOLD; style = Paint.Style.STROKE; strokeWidth = 1.5f * density
        }
        private val pGoldBold = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_GOLD; style = Paint.Style.STROKE; strokeWidth = 2.5f * density
        }
        private val pCyan = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_CYAN; style = Paint.Style.STROKE; strokeWidth = 1.5f * density
        }
        private val pDim = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_DIM; style = Paint.Style.STROKE; strokeWidth = 1f * density
        }
        private val pDimCyan = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_DIM_CYAN; style = Paint.Style.STROKE; strokeWidth = 1f * density
        }
        private val pDimGold = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_DIM_GOLD; style = Paint.Style.STROKE; strokeWidth = 1f * density
        }
        private val pWhite = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_WHITE; style = Paint.Style.STROKE; strokeWidth = 1.5f * density
        }
        private val pFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        private val pText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_GOLD; textSize = 9f * density
            isFakeBoldText = true; letterSpacing = 0.15f
        }
        private val pTextSmall = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_CYAN; textSize = 7f * density
            letterSpacing = 0.1f
        }
        private val pTextRed = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = COL_RED; textSize = 8f * density
            isFakeBoldText = true; letterSpacing = 0.1f
        }

        private val dashPath = DashPathEffect(floatArrayOf(8f, 8f), 0f)
        private val dashPathFine = DashPathEffect(floatArrayOf(4f, 6f), 0f)

        init {
            setLayerType(LAYER_TYPE_HARDWARE, null)
        }

        fun setStatusText(t: String) { statusText = t; invalidate() }

        fun pulse() {
            pulseAlpha = 1f
        }

        fun triggerTarget(x: Float, y: Float) {
            targetX = x; targetY = y
            targetAlpha = 1f
            targetRadius = 200f * density
            targetLockProgress = 0f
            // анимация захвата — кольцо сжимается
            val anim = ValueAnimator.ofFloat(0f, 1f)
            anim.duration = 700
            anim.interpolator = LinearInterpolator()
            anim.addUpdateListener { 
                targetLockProgress = it.animatedValue as Float
                targetRadius = (200f * density) * (1f - targetLockProgress * 0.7f)
                invalidate()
            }
            anim.start()
            // авто-затухание через 1.8 сек
            object : android.os.CountDownTimer(1800, 30) {
                override fun onTick(m: Long) {
                    if (m < 800) targetAlpha = (m / 800f)
                    invalidate()
                }
                override fun onFinish() { targetAlpha = 0f; invalidate() }
            }.start()
        }

        // Главный цикл анимации — явный object чтобы `this` был FrameCallback
        private val frameCallback: Choreographer.FrameCallback = object : Choreographer.FrameCallback() {
            override fun doFrame(frameTimeNanos: Long) {
                if (!isRunning) return
                if (lastFrameNanos > 0L) {
                    val dt = (frameTimeNanos - lastFrameNanos) / 1_000_000_000f
                    sweepAngle = (sweepAngle + 90f * dt) % 360f       // 90°/сек
                    ringRotation = (ringRotation + 45f * dt) % 360f   // 45°/сек
                    if (pulseAlpha > 0f) pulseAlpha = (pulseAlpha - dt * 2f).coerceAtLeast(0f)
                }
                lastFrameNanos = frameTimeNanos
                invalidate()
                choreographer.postFrameCallback(this)
            }
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            isRunning = true
            choreographer.postFrameCallback(frameCallback)
        }

        override fun onDetachedFromWindow() {
            isRunning = false
            choreographer.removeFrameCallback(frameCallback)
            super.onDetachedFromWindow()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
            val w = W; val h = H
            if (w < 1 || h < 1) return

            val a = bgAlpha
            pRedThin.alpha = (255 * a).toInt()
            pGoldThin.alpha = (255 * a).toInt()

            // ── 1. HEX ФОН (очень тусклая сетка) ──────────────────────
            drawHexGrid(canvas, w, h)

            // ── 2. УГЛОВЫЕ СКОБКИ ─────────────────────────────────────
            drawCornerBrackets(canvas, w, h)

            // ── 3. ВЕРХНИЙ HUD BAR ────────────────────────────────────
            drawTopBar(canvas, w, h)

            // ── 4. ЛЕВАЯ СТОРОНА — статус-бары ────────────────────────
            drawLeftStatusBars(canvas, h)

            // ── 5. ПРАВАЯ СТОРОНА — компас / круг ────────────────────
            drawRightCompass(canvas, w, h)

            // ── 6. НИЖНИЙ BAR — координаты ───────────────────────────
            drawBottomBar(canvas, w, h)

            // ── 7. ЦЕНТРАЛЬНЫЙ ПРИЦЕЛ — если активен ─────────────────
            if (targetAlpha > 0 && targetX > 0 && targetY > 0) {
                drawTargetReticle(canvas, targetX, targetY, targetAlpha, targetRadius, targetLockProgress)
            }

            // ── 8. PULSE — короткая вспышка ─────────────────────────
            if (pulseAlpha > 0) {
                pFill.color = COL_RED
                pFill.alpha = (40 * pulseAlpha).toInt()
                canvas.drawRect(0f, 0f, w, h, pFill)
            }

            // ── 9. СКАНЛАЙН ──────────────────────────────────────────
            drawSweepLine(canvas, w, h)
        }

        // ══════════════════════════════════════════════════════════
        //  ДЕТАЛИ
        // ══════════════════════════════════════════════════════════

        private fun drawHexGrid(c: Canvas, w: Float, h: Float) {
            val r = 28f * density
            val dx = r * 1.5f
            val dy = r * sqrt(3f)
            pDim.pathEffect = dashPathFine
            pDim.alpha = 35
            var row = 0
            var y = -dy
            while (y < h + dy) {
                val xOff = if (row % 2 == 0) 0f else dx / 2
                var x = -dx + xOff
                while (x < w + dx) {
                    drawHex(c, x, y, r, pDim)
                    x += dx
                }
                y += dy / 2; row++
            }
            pDim.pathEffect = null
            pDim.alpha = (255 * bgAlpha).toInt()
        }

        private fun drawHex(c: Canvas, cx: Float, cy: Float, r: Float, p: Paint) {
            val path = Path()
            for (i in 0..5) {
                val a = Math.PI / 3 * i
                val x = cx + r * cos(a).toFloat()
                val y = cy + r * sin(a).toFloat()
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            path.close()
            c.drawPath(path, p)
        }

        private fun drawCornerBrackets(c: Canvas, w: Float, h: Float) {
            val m = 24 * density   // margin
            val len = 70 * density
            val t = 3f * density
            // Цвет — золотой, толще
            pGoldBold.alpha = (255 * bgAlpha).toInt()

            // Верх-лево
            c.drawLine(m, m, m + len, m, pGoldBold)
            c.drawLine(m, m, m, m + len, pGoldBold)
            // уголок-акцент
            pRedBold.alpha = (255 * bgAlpha).toInt()
            c.drawLine(m, m, m + 18 * density, m, pRedBold)
            c.drawLine(m, m, m, m + 18 * density, pRedBold)

            // Верх-право
            c.drawLine(w - m, m, w - m - len, m, pGoldBold)
            c.drawLine(w - m, m, w - m, m + len, pGoldBold)
            c.drawLine(w - m, m, w - m - 18 * density, m, pRedBold)
            c.drawLine(w - m, m, w - m, m + 18 * density, pRedBold)

            // Низ-лево
            c.drawLine(m, h - m, m + len, h - m, pGoldBold)
            c.drawLine(m, h - m, m, h - m - len, pGoldBold)
            c.drawLine(m, h - m, m + 18 * density, h - m, pRedBold)
            c.drawLine(m, h - m, m, h - m - 18 * density, pRedBold)

            // Низ-право
            c.drawLine(w - m, h - m, w - m - len, h - m, pGoldBold)
            c.drawLine(w - m, h - m, w - m, h - m - len, pGoldBold)
            c.drawLine(w - m, h - m, w - m - 18 * density, h - m, pRedBold)
            c.drawLine(w - m, h - m, w - m, h - m - 18 * density, pRedBold)

            // Тонкие декоративные полоски внутри углов
            pGoldThin.alpha = (180 * bgAlpha).toInt()
            val dm = 30 * density
            val dl = 40 * density
            c.drawLine(m + dm, m + 8 * density, m + dm + dl, m + 8 * density, pGoldThin)
            c.drawLine(w - m - dm, m + 8 * density, w - m - dm - dl, m + 8 * density, pGoldThin)
            c.drawLine(m + dm, h - m - 8 * density, m + dm + dl, h - m - 8 * density, pGoldThin)
            c.drawLine(w - m - dm, h - m - 8 * density, w - m - dm - dl, h - m - 8 * density, pGoldThin)
        }

        private fun drawTopBar(c: Canvas, w: Float, h: Float) {
            val cx = w / 2
            val ty = 36 * density
            // Центральный заголовок
            pText.textSize = 10 * density
            pText.alpha = (255 * bgAlpha).toInt()
            val title = "J . A . R . V . I . S ."
            val tw = pText.measureText(title)
            c.drawText(title, cx - tw / 2, ty, pText)
            // Подпись
            pTextSmall.alpha = (200 * bgAlpha).toInt()
            val sub = "STARK INDUSTRIES // MK-VII"
            val sw = pTextSmall.measureText(sub)
            c.drawText(sub, cx - sw / 2, ty + 14 * density, pTextSmall)
            // Тонкая линия под заголовком
            pGoldThin.alpha = (180 * bgAlpha).toInt()
            c.drawLine(cx - 80 * density, ty + 22 * density, cx + 80 * density, ty + 22 * density, pGoldThin)
            // Симметричные «крылья»
            c.drawLine(cx - 80 * density, ty + 22 * density, cx - 140 * density, ty + 22 * density, pDimGold)
            c.drawLine(cx + 80 * density, ty + 22 * density, cx + 140 * density, ty + 22 * density, pDimGold)
            // Маленькие квадратики на концах
            pFill.color = COL_GOLD
            pFill.alpha = (200 * bgAlpha).toInt()
            c.drawRect(cx - 144 * density, ty + 18 * density, cx - 140 * density, ty + 26 * density, pFill)
            c.drawRect(cx + 140 * density, ty + 18 * density, cx + 144 * density, ty + 26 * density, pFill)
        }

        private fun drawLeftStatusBars(c: Canvas, h: Float) {
            val x0 = 36 * density
            val y0 = h / 2 - 70 * density
            val barW = 90 * density
            val barH = 6 * density
            val gap = 12 * density
            val labels = listOf("PWR", "CPU", "NET", "MEM", "AUX")
            val values = listOf(0.92f, 0.78f, 1.0f, 0.64f, 0.85f)
            for (i in labels.indices) {
                val y = y0 + i * (barH + gap)
                // label
                pTextSmall.alpha = (180 * bgAlpha).toInt()
                pTextSmall.textSize = 7 * density
                c.drawText(labels[i], x0, y - 2 * density, pTextSmall)
                // bg
                pDim.alpha = (200 * bgAlpha).toInt()
                c.drawRect(x0 + 30 * density, y - barH, x0 + 30 * density + barW, y, pDim)
                // fill
                pFill.color = COL_GOLD
                pFill.alpha = (220 * bgAlpha).toInt()
                c.drawRect(x0 + 30 * density, y - barH, x0 + 30 * density + barW * values[i], y, pFill)
                // value
                pTextSmall.alpha = (200 * bgAlpha).toInt()
                val v = "${(values[i] * 100).toInt()}%"
                c.drawText(v, x0 + 30 * density + barW + 5 * density, y, pTextSmall)
            }
        }

        private fun drawRightCompass(c: Canvas, w: Float, h: Float) {
            val cx = w - 60 * density
            val cy = h / 2
            val r = 32 * density
            // Внешнее кольцо
            pGoldThin.alpha = (200 * bgAlpha).toInt()
            c.drawCircle(cx, cy, r, pGoldThin)
            // Внутреннее кольцо с тиками
            pDim.alpha = (180 * bgAlpha).toInt()
            for (i in 0..11) {
                val a = Math.PI / 6 * i
                val x1 = cx + r * cos(a).toFloat()
                val y1 = cy + r * sin(a).toFloat()
                val x2 = cx + (r - 6 * density) * cos(a).toFloat()
                val y2 = cy + (r - 6 * density) * sin(a).toFloat()
                c.drawLine(x1, y1, x2, y2, if (i % 3 == 0) pGoldThin else pDim)
            }
            // Вращающийся внутренний треугольник (компас-стрелка)
            val aRad = Math.toRadians((sweepAngle * 2).toDouble())
            pRedBold.alpha = (220 * bgAlpha).toInt()
            val p1 = floatArrayOf(cx + (r - 14 * density) * cos(aRad).toFloat(), cy + (r - 14 * density) * sin(aRad).toFloat())
            val p2 = floatArrayOf(cx + 6 * density * cos(aRad + Math.PI / 2).toFloat(), cy + 6 * density * sin(aRad + Math.PI / 2).toFloat())
            val p3 = floatArrayOf(cx + 6 * density * cos(aRad - Math.PI / 2).toFloat(), cy + 6 * density * sin(aRad - Math.PI / 2).toFloat())
            val tri = Path().apply {
                moveTo(p1[0], p1[1]); lineTo(p2[0], p2[1]); lineTo(p3[0], p3[1]); close()
            }
            c.drawPath(tri, pRedBold)
            // Центральная точка
            pFill.color = COL_GOLD
            pFill.alpha = (255 * bgAlpha).toInt()
            c.drawCircle(cx, cy, 2 * density, pFill)
            // N
            pTextSmall.alpha = (200 * bgAlpha).toInt()
            pTextSmall.textSize = 7 * density
            c.drawText("N", cx - 3 * density, cy - r - 4 * density, pTextSmall)
        }

        private fun drawBottomBar(c: Canvas, w: Float, h: Float) {
            val y = h - 36 * density
            val m = 24 * density
            val cx = w / 2
            // Тонкая линия
            pGoldThin.alpha = (180 * bgAlpha).toInt()
            c.drawLine(m + 60 * density, y, w - m - 60 * density, y, pGoldThin)
            // Статус-строка слева
            pTextSmall.alpha = (220 * bgAlpha).toInt()
            pTextSmall.textSize = 7.5f * density
            c.drawText(statusText, m + 60 * density, y - 5 * density, pTextSmall)
            // Координаты справа
            val coord = String.format("X:%04d  Y:%04d", (targetX.coerceAtLeast(0f)).toInt(), (targetY.coerceAtLeast(0f)).toInt())
            val cw = pTextSmall.measureText(coord)
            c.drawText(coord, w - m - 60 * density - cw, y - 5 * density, pTextSmall)
            // Декоративные точки
            pFill.color = COL_GOLD
            pFill.alpha = (220 * bgAlpha).toInt()
            c.drawCircle(m + 50 * density, y, 2 * density, pFill)
            c.drawCircle(w - m - 50 * density, y, 2 * density, pFill)
            // Анимированные деления на линии (бегущие)
            val dashOffset = (System.currentTimeMillis() / 30f) % 30f
            pCyan.alpha = (200 * bgAlpha).toInt()
            pCyan.pathEffect = DashPathEffect(floatArrayOf(3f, 27f), dashOffset)
            c.drawLine(m + 60 * density, y + 5 * density, w - m - 60 * density, y + 5 * density, pCyan)
            pCyan.pathEffect = null
        }

        private fun drawSweepLine(c: Canvas, w: Float, h: Float) {
            // Вертикальный сканлайт — двигается сверху вниз
            val cycle = 6000 // мс за цикл
            val t = (System.currentTimeMillis() % cycle) / cycle.toFloat()
            val sx = t * w
            // градиент-«луч»
            val grad = LinearGradient(sx - 60 * density, 0f, sx + 60 * density, 0f,
                intArrayOf(Color.TRANSPARENT, 0x44FFD700.toInt(), Color.TRANSPARENT),
                null, Shader.TileMode.CLAMP)
            pFill.shader = grad
            pFill.alpha = (80 * bgAlpha).toInt()
            c.drawRect(sx - 60 * density, 0f, sx + 60 * density, h, pFill)
            pFill.shader = null
            // Центральная линия сканера
            pCyan.alpha = (160 * bgAlpha).toInt()
            c.drawLine(sx, 0f, sx, h, pCyan)
        }

        private fun drawTargetReticle(c: Canvas, x: Float, y: Float, alpha: Float, radius: Float, lock: Float) {
            val a = (255 * alpha).toInt()
            pRedBold.alpha = a
            pRedThin.alpha = a
            pGoldThin.alpha = a
            pCyan.alpha = a
            pTextRed.alpha = a
            pFill.alpha = a

            // 1. Внешнее вращающееся кольцо (4 дуги)
            val rOut = radius
            val sweep = 50f
            val gap = 40f
            val rot = ringRotation
            val rect = RectF(x - rOut, y - rOut, x + rOut, y + rOut)
            for (i in 0..3) {
                val start = rot + i * 90f
                c.drawArc(rect, start, sweep, false, pRedBold)
            }

            // 2. Внутреннее кольцо — пунктир, вращается в обратную сторону
            val rIn = rOut * 0.65f
            val rectIn = RectF(x - rIn, y - rIn, x + rIn, y + rIn)
            pGoldThin.pathEffect = dashPath
            c.drawCircle(x, y, rIn, pGoldThin)
            pGoldThin.pathEffect = null

            // 3. 4 таргет-уголка (как у Iron Man при захвате)
            val bl = rOut * 1.15f   // длина уголка
            val off = rOut * 1.05f
            val cornerLen = 18 * density
            // верх-лево
            c.drawLine(x - off, y - off, x - off + cornerLen, y - off, pGoldBold)
            c.drawLine(x - off, y - off, x - off, y - off + cornerLen, pGoldBold)
            // верх-право
            c.drawLine(x + off, y - off, x + off - cornerLen, y - off, pGoldBold)
            c.drawLine(x + off, y - off, x + off, y - off + cornerLen, pGoldBold)
            // низ-лево
            c.drawLine(x - off, y + off, x - off + cornerLen, y + off, pGoldBold)
            c.drawLine(x - off, y + off, x - off, y + off - cornerLen, pGoldBold)
            // низ-право
            c.drawLine(x + off, y + off, x + off - cornerLen, y + off, pGoldBold)
            c.drawLine(x + off, y + off, x + off, y + off - cornerLen, pGoldBold)

            // 4. Перекрестие — тонкие линии до центра
            pCyan.alpha = (200 * alpha).toInt()
            val cl = rOut * 0.4f
            val gap2 = rOut * 0.12f
            c.drawLine(x - cl, y, x - gap2, y, pCyan)
            c.drawLine(x + gap2, y, x + cl, y, pCyan)
            c.drawLine(x, y - cl, x, y - gap2, pCyan)
            c.drawLine(x, y + gap2, x, y + cl, pCyan)

            // 5. Центральная точка — пульсирующая
            val cpulse = 3 * density + 2 * density * (sin(System.currentTimeMillis() / 150.0)).toFloat()
            pFill.color = COL_RED
            pFill.alpha = a
            c.drawCircle(x, y, cpulse, pFill)
            pFill.color = COL_WHITE
            pFill.alpha = (a * 0.6f).toInt()
            c.drawCircle(x, y, cpulse * 0.5f, pFill)

            // 6. Радиальный «захват» — расходящиеся круги при lock
            if (lock > 0) {
                val pulseR = rOut + lock * 60 * density
                pRedThin.alpha = ((1 - lock) * a).toInt()
                c.drawCircle(x, y, pulseR, pRedThin)
            }

            // 7. Надпись TARGET LOCKED (когда lock > 0.6)
            if (lock > 0.6f) {
                val textA = ((lock - 0.6f) / 0.4f * a).toInt()
                pTextRed.alpha = textA
                pTextRed.textSize = 9 * density
                val txt = "TARGET LOCKED"
                val tw = pTextRed.measureText(txt)
                c.drawText(txt, x - tw / 2, y + off + 22 * density, pTextRed)
                // Координаты под прицелом
                pTextSmall.alpha = textA
                pTextSmall.color = COL_CYAN
                pTextSmall.textSize = 7 * density
                val coord = String.format("[ %03d , %03d ]", x.toInt(), y.toInt())
                val cw = pTextSmall.measureText(coord)
                c.drawText(coord, x - cw / 2, y + off + 35 * density, pTextSmall)
                pTextSmall.color = COL_CYAN
            }
        }

        override fun onTouchEvent(event: MotionEvent?): Boolean {
            // Пропускаем все касания сквозь
            return false
        }
    }
}
