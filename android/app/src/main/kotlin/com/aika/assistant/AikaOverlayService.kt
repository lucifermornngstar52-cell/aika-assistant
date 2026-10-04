package com.aika.assistant

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.graphics.drawable.GradientDrawable
import android.widget.LinearLayout
import android.widget.TextView
import android.view.MotionEvent
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.app.NotificationCompat
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * AivoraOverlayService Live2D overlay через Android WebView.
 * Окно ровно по размеру модели, не перекрывает UI.
 * Перетаскивание работает нативно через WindowManager.updateViewLayout.
 */
class AikaOverlayService: Service() {

 companion object {
 const val ACTION_SHOW = "com.aika.SHOW"
 const val ACTION_UPDATE = "com.aika.UPDATE"
 const val ACTION_HIDE = "com.aika.HIDE"
 const val ACTION_CONFIG = "com.aika.CONFIG"
 const val ACTION_MUSIC = "com.aika.MUSIC"
 const val ACTION_ANIM = "com.aika.ANIM"
 const val ACTION_SWITCH_MODEL = "com.aika.SWITCH_MODEL"
 const val ACTION_DRAG_ENABLED = "com.aika.DRAG_ENABLED"
 const val ACTION_SET_MODE = "com.aika.SET_MODE" // "live2d" | "3d"
 const val EXTRA_MODE = "mode"

 const val EXTRA_STATE = "state"
 const val EXTRA_SIZE = "size"
 const val EXTRA_SIDE = "side"
 const val EXTRA_OPACITY = "opacity"
 const val EXTRA_PLAYING = "playing"
 const val EXTRA_ANIM = "anim_name"
 const val EXTRA_MODEL_PATH = "model_path"
 const val EXTRA_DRAG_ENABLED = "drag_enabled"
 const val EXTRA_SOUND_PATH = "sound_path"
 const val ACTION_PLAY_SOUND = "aika.overlay.PLAY_SOUND"
 const val ACTION_STOP_SOUND = "aika.overlay.STOP_SOUND"
 const val ACTION_SHOW_TIP = "aika.overlay.SHOW_TIP"
 const val ACTION_HIDE_TIP = "aika.overlay.HIDE_TIP"
 // ── Плавающая кнопка Minecraft-пилота ──
 const val ACTION_SHOW_PILOT = "aika.overlay.SHOW_PILOT"
 const val ACTION_HIDE_PILOT = "aika.overlay.HIDE_PILOT"
 const val ACTION_PILOT_STATUS = "aika.overlay.PILOT_STATUS"
 const val ACTION_PILOT_CMD = "aika.PILOT_COMMAND" // broadcast → MainActivity → Flutter
 const val EXTRA_CMD = "cmd"
 const val EXTRA_STATUS = "pilot_status"
 const val EXTRA_TIP_TITLE = "tip_title"
 const val EXTRA_TIP_TEXT = "tip_text"
 const val EXTRA_TIP_SECONDS = "tip_seconds"
 const val ENGINE_ID = "live2d_overlay_engine"

 private const val CHANNEL_ID = "aika_overlay_channel"
 private const val NOTIF_ID = 1337
 private const val TAG = "AikaOverlay"
 private const val BASE_URL = "file:///android_asset/flutter_assets/assets/"

 var isRunning = false
 var isHiddenByUser = false // persist across service instances
 }

 private val handler = Handler(Looper.getMainLooper())
 private var wm: WindowManager? = null
 private var webView: WebView? = null
 private var params: WindowManager.LayoutParams? = null

 private var dragEnabled = true
 private var currentState = "idle"
 private var currentMode = "live2d" // "live2d" | "3d"

 // ── Плавающая кнопка + окно Minecraft-пилота ──────────────────────
 private var pilotButton: LinearLayout? = null
 private var pilotButtonParams: WindowManager.LayoutParams? = null
 private var pilotWindow: LinearLayout? = null
 private var pilotWindowParams: WindowManager.LayoutParams? = null
 private var pilotInput: android.widget.EditText? = null
 private var pilotStatusView: TextView? = null
 private var pilotResizeStartW = 0
 private var pilotResizeStartH = 0
 private var pilotResizeStartX = 0f
 private var pilotResizeStartY = 0f

 // ── Карточка-подсказка (рецепты Майнкрафт и т.п.) ────────────────
 private var tipView: LinearLayout? = null
 private var tipParams: WindowManager.LayoutParams? = null
 private var tipHideRunnable: Runnable? = null

 private fun getHtmlPath(): String =
 if (currentMode == "3d") "file:///android_asset/flutter_assets/assets/model3d_viewer.html"
 else "file:///android_asset/flutter_assets/assets/live2d_viewer.html"
 private var sizeDp = 120f
 private var opacity = 1f
 private var side = "left"

 // Drag state
 private var dragStartX = 0
 private var dragStartY = 0
 private var touchStartX = 0f
 private var touchStartY = 0f
 private var isDragging = false

 override fun onBind(intent: Intent?): IBinder? = null

 // PERF: WebView оверлея рендерил анимацию даже при ВЫКЛЮЧЕННОМ экране —
 // GPU/батарея молотили в пустоту. Гасим рендер на ACTION_SCREEN_OFF.
 private var screenReceiver: BroadcastReceiver? = null

 override fun onCreate() {
 super.onCreate()
 isRunning = true
 createNotificationChannel()
 startForeground(NOTIF_ID, buildNotification())
 // Загружаем сохранённый размер из prefs
 try {
 val prefs = getSharedPreferences("flutter.overlay_prefs", Context.MODE_PRIVATE)
 val savedSize = prefs.getFloat("overlay_size", 120f)
 sizeDp = savedSize
 val savedOpacity = prefs.getFloat("overlay_opacity", 1f)
 opacity = savedOpacity
 val savedSide = prefs.getString("overlay_side", "left")?: "left"
 side = savedSide
 Log.d(TAG, "Loaded prefs: size=$sizeDp opacity=$opacity side=$side")
 } catch (e: Exception) {
 Log.e(TAG, "Failed to load prefs: ${e.message}")
 }
 // НЕ создаём окно если пользователь его выключил (isHiddenByUser).
 // onCreate вызывается ДО onStartCommand — если тут сделать setupWindow,
 // то проверка isHiddenByUser в onStartCommand уже бесполезна.
 // ACTION_SHOW в onStartCommand вызовет setupWindow если нужно.
 if (!isHiddenByUser) {
 handler.post { setupWindow() }
 } else {
 Log.d(TAG, "onCreate: skipping setupWindow — isHiddenByUser=true")
 }
 // Пауза рендера при гашении экрана, возобновление при разблокировке.
 screenReceiver = object: BroadcastReceiver() {
 override fun onReceive(ctx: Context?, intent: Intent?) {
 val wv = webView?: return
 try {
 when (intent?.action) {
 Intent.ACTION_SCREEN_OFF -> wv.onPause()
 Intent.ACTION_USER_PRESENT, Intent.ACTION_SCREEN_ON -> wv.onResume()
 }
 } catch (_: Exception) {}
 }
 }
 registerReceiver(screenReceiver, IntentFilter().apply {
 addAction(Intent.ACTION_SCREEN_OFF)
 addAction(Intent.ACTION_SCREEN_ON)
 addAction(Intent.ACTION_USER_PRESENT)
 })
 }

 override fun onDestroy() {
 isRunning = false
 try { screenReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
 screenReceiver = null
 handler.post {
 try { webView?.let { wm?.removeView(it) } } catch (_: Exception) {}
 webView?.destroy()
 webView = null
 hideTipNow()
 }
 super.onDestroy()
 }

 @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
 private fun setupWindow() {
 wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
 val density = resources.displayMetrics.density

 val wPx = (sizeDp * density).roundToInt()
 val hPx = (sizeDp * 1.6f * density).roundToInt()

 val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
 WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
 else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

 // FLAG_NOT_FOCUSABLE — не забирает фокус
 // FLAG_NOT_TOUCH_MODAL — касания вне окна проходят насквозь
 // УБИРАЕМ FLAG_LAYOUT_IN_SCREEN — он расширяет хит-зону
 params = WindowManager.LayoutParams(
 wPx, hPx,
 overlayType,
 WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
 WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
 WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
 PixelFormat.TRANSPARENT
).apply {
 gravity = Gravity.TOP or Gravity.START
 val screenW = resources.displayMetrics.widthPixels
 x = if (side == "right") screenW - wPx - (16 * density).roundToInt()
 else (16 * density).roundToInt()
 y = (120 * density).roundToInt()
 }

 val wv = WebView(applicationContext)
 webView = wv
 wv.alpha = opacity
 wv.setBackgroundColor(Color.TRANSPARENT)
 wv.background?.alpha = 0

 wv.settings.apply {
 javaScriptEnabled = true
 allowFileAccess = true
 allowContentAccess = true
 @Suppress("DEPRECATION") allowFileAccessFromFileURLs = true
 @Suppress("DEPRECATION") allowUniversalAccessFromFileURLs = true
 mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
 mediaPlaybackRequiresUserGesture = false
 domStorageEnabled = true
 cacheMode = WebSettings.LOAD_DEFAULT
 useWideViewPort = true
 loadWithOverviewMode = true
 setSupportZoom(false)
 builtInZoomControls = false
 displayZoomControls = false
 }

 wv.webChromeClient = WebChromeClient()
 wv.webViewClient = object: WebViewClient() {
 override fun shouldInterceptRequest(v: WebView?, r: WebResourceRequest?): WebResourceResponse? = null
 override fun onPageFinished(v: WebView?, url: String?) {
 handler.postDelayed({
 v?.evaluateJavascript("window.setAikaState('$currentState')", null)
 }, 2500)
 }
 }

 wv.addJavascriptInterface(object {
 @JavascriptInterface
 fun onModelLoaded() {
 handler.post {
 webView?.evaluateJavascript("window.setAikaState('$currentState')", null)
 }
 }
 @JavascriptInterface
 fun onTap() { Log.d(TAG, "tap") }
 }, "AndroidBridge")

 // ── Touch handler — перетаскивание прямо на WebView ─────────────────
 wv.setOnTouchListener { _, ev ->
 when (ev.actionMasked) {
 MotionEvent.ACTION_DOWN -> {
 isDragging = false
 dragStartX = params!!.x
 dragStartY = params!!.y
 touchStartX = ev.rawX
 touchStartY = ev.rawY
 // Пропускаем касания в прозрачных краях (верх 20%, низ 10%)
 val relY = ev.y / wv.height.toFloat()
 if (relY < 0.18f) return@setOnTouchListener false
 false
 }
 MotionEvent.ACTION_MOVE -> {
 val dx = ev.rawX - touchStartX
 val dy = ev.rawY - touchStartY
 if (!isDragging && (abs(dx) > 8 || abs(dy) > 8)) {
 isDragging = true
 }
 if (isDragging && dragEnabled) {
 params!!.x = (dragStartX + dx).roundToInt()
 params!!.y = (dragStartY + dy).roundToInt()
 try { wm?.updateViewLayout(wv, params) } catch (_: Exception) {}
 return@setOnTouchListener true
 }
 false
 }
 MotionEvent.ACTION_UP -> {
 if (!isDragging) {
 // тап — приветствие
 wv.evaluateJavascript("window.setAikaState('greeting')", null)
 handler.postDelayed({
 webView?.evaluateJavascript("window.setAikaState('idle')", null)
 }, 2500)
 }
 isDragging = false
 false
 }
 else -> false
 }
 }

 wv.loadUrl("${BASE_URL}live2d_viewer.html")

 // Fallback — показываем через 5 сек если JS не ответил
 handler.postDelayed({ webView?.let { if (it.alpha < 0.5f) it.alpha = opacity } }, 5000)

 try {
 wm?.addView(wv, params)
 } catch (e: Exception) {
 Log.e(TAG, "addView failed: ${e.message}")
 }
 }

 override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
 val density = resources.displayMetrics.density

 when (intent?.action) {
 ACTION_SHOW_PILOT -> {
 handler.post { showPilotButton() }
 }
 ACTION_HIDE_PILOT -> {
 handler.post { hidePilotOverlay() }
 }
 ACTION_PILOT_STATUS -> {
 val st = intent.getStringExtra(EXTRA_STATUS)?: ""
 handler.post { setPilotStatus(st) }
 }
 ACTION_SHOW -> {
 val st = intent.getStringExtra(EXTRA_STATE)?: "idle"
 currentState = st // сбрасывает "hidden" при повторном включении
 isHiddenByUser = false // user re-enabled overlay
 handler.post {
 if (webView == null) setupWindow()
 else webView?.evaluateJavascript("window.setAikaState('$st')", null)
 }
 }
 ACTION_UPDATE -> {
 // Не пересоздаём окно если оно было спрятано (ACTION_HIDE)
 if (isHiddenByUser) return START_NOT_STICKY
 val st = intent.getStringExtra(EXTRA_STATE)?: "idle"
 currentState = st
 handler.post {
 if (webView == null) return@post // окно спрятано — не воссоздаём
 webView?.evaluateJavascript("window.setAikaState('$st')", null)
 }
 }
 ACTION_HIDE -> {
 currentState = "hidden"
 isHiddenByUser = true // remember across instances
 handler.post {
 try { webView?.let { wm?.removeView(it) } } catch (_: Exception) {}
 webView?.destroy()
 webView = null
 // НЕ вызываем stopSelf() — сервис остаётся живым.
 // Это prevents recreation в onStartCommand где
 // isHiddenByUser ещё не успел бы сработать в onCreate.
 }
 }
 ACTION_CONFIG -> {
 val newSize = intent.getFloatExtra(EXTRA_SIZE, 0f)
 val newOpacity = intent.getFloatExtra(EXTRA_OPACITY, -1f)
 val newSide = intent.getStringExtra(EXTRA_SIDE)
 handler.post {
 val p = params?: return@post
 val wv = webView?: return@post
 var changed = false
 if (newSize > 0f) {
 sizeDp = newSize
 p.width = (sizeDp * density).roundToInt()
 p.height = (sizeDp * 1.6f * density).roundToInt()
 changed = true
 }
 if (newOpacity >= 0f) {
 opacity = newOpacity
 wv.alpha = opacity
 }
 if (newSide!= null) {
 side = newSide
 val screenW = resources.displayMetrics.widthPixels
 p.x = if (side == "right") screenW - p.width - (16 * density).roundToInt()
 else (16 * density).roundToInt()
 changed = true
 }
 if (changed) try { wm?.updateViewLayout(wv, p) } catch (_: Exception) {}
 // Сохраняем в prefs
 try {
 val prefs = getSharedPreferences("flutter.overlay_prefs", Context.MODE_PRIVATE)
 prefs.edit()
.putFloat("overlay_size", sizeDp)
.putFloat("overlay_opacity", opacity)
.putString("overlay_side", side)
.apply()
 } catch (_: Exception) {}
 }
 }
 ACTION_SWITCH_MODEL -> {
 val path = intent.getStringExtra(EXTRA_MODEL_PATH)?: return START_STICKY
 Log.d("AikaOverlay", "switchModel to: $path (mode=$currentMode)")
 handler.post {
 if (webView!= null) {
 if (currentMode == "3d") {
 // 3D model: use model3D.loadModel with full asset URL
 val fullPath = "file:///android_asset/flutter_assets/assets/$path"
 webView?.evaluateJavascript(
 "window.model3D? window.model3D.loadModel('$fullPath'): console.log('no model3D')",
 null
)
 } else {
 // Live2D: use switchModel
 webView?.evaluateJavascript("window.switchModel('$path')") { result ->
 Log.d("AikaOverlay", "switchModel result: $result")
 }
 }
 } else {
 Log.e("AikaOverlay", "webView is null!")
 setupWindow()
 }
 }
 }
 ACTION_SET_MODE -> {
 val mode = intent.getStringExtra(EXTRA_MODE)?: "live2d"
 currentMode = mode
 handler.post {
 webView?.loadUrl(getHtmlPath())
 }
 }
 ACTION_DRAG_ENABLED -> {
 dragEnabled = intent.getBooleanExtra(EXTRA_DRAG_ENABLED, true)
 }
 ACTION_ANIM -> {
 val anim = intent.getStringExtra(EXTRA_ANIM)?: return START_STICKY
 handler.post {
 webView?.evaluateJavascript("window.setAikaState('$anim')", null)
 }
 }
 ACTION_PLAY_SOUND -> {
 val path = intent.getStringExtra(EXTRA_SOUND_PATH)?: return START_STICKY
 handler.post {
 // Передаём путь в JS — экранируем одинарные кавычки
 val safePath = path.replace("'", "\'")
 webView?.evaluateJavascript("window.externalPlaySound('$safePath')", null)
 }
 }
 ACTION_STOP_SOUND -> {
 handler.post {
 webView?.evaluateJavascript("window.externalStopSound()", null)
 }
 }
 ACTION_MUSIC -> {
 val playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
 currentState = if (playing) "listening" else "idle"
 handler.post {
 webView?.evaluateJavascript("window.setAikaState('$currentState')", null)
 }
 }
 ACTION_SHOW_TIP -> {
 val title = intent.getStringExtra(EXTRA_TIP_TITLE)?: "Подсказка"
 val text = intent.getStringExtra(EXTRA_TIP_TEXT)?: ""
 val secs = intent.getIntExtra(EXTRA_TIP_SECONDS, 45)
 handler.post { showTipCard(title, text, secs) }
 }
 ACTION_HIDE_TIP -> {
 handler.post { hideTipNow() }
 }
 }
 return START_STICKY
 }

 // ── Карточка-подсказка поверх всего ─────────────────────────────
 @SuppressLint("ClickableViewAccessibility")
 private fun showTipCard(title: String, text: String, seconds: Int) {
 // окно оверлея может быть ещё не создано — нам нужен только wm
 if (wm == null) {
 wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
 }

 hideTipNow()

 val density = resources.displayMetrics.density
 val screenW = resources.displayMetrics.widthPixels

 val card = LinearLayout(this).apply {
 orientation = LinearLayout.VERTICAL
 val pad = (12 * density).roundToInt()
 setPadding(pad, pad, pad, pad)
 background = GradientDrawable().apply {
 setColor(0xEE1A1626.toInt())
 cornerRadius = 16 * density
 setStroke((1 * density).roundToInt(), 0xFF8B7BD8.toInt())
 }
 }

 val titleView = TextView(this).apply {
 this.text = title
 setTextColor(0xFFEDE7FF.toInt())
 textSize = 15f
 setTypeface(typeface, android.graphics.Typeface.BOLD)
 }
 val textView = TextView(this).apply {
 this.text = text
 setTextColor(0xFFC9C3E6.toInt())
 textSize = 13f
 setLineSpacing(2f, 1f)
 }
 val hintView = TextView(this).apply {
 this.text = "нажми, чтобы закрыть"
 setTextColor(0x99FFFFFF.toInt())
 textSize = 10f
 }

 card.addView(titleView)
 card.addView(textView)
 card.addView(hintView)

 card.setOnClickListener { hideTipNow() }

 val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
 WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
 else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

 val tipW = (screenW * 0.8f).roundToInt().coerceAtMost((320 * density).roundToInt())
 val tipParams = WindowManager.LayoutParams(
 tipW,
 WindowManager.LayoutParams.WRAP_CONTENT,
 overlayType,
 WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
 WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
 PixelFormat.TRANSLUCENT
).apply {
 gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
 y = (64 * density).roundToInt()
 }
 this.tipParams = tipParams

 try {
 wm?.addView(card, tipParams)
 tipView = card
 } catch (e: Exception) {
 Log.e(TAG, "tip addView failed: ${e.message}")
 return
 }

 // автоскрытие
 tipHideRunnable?.let { handler.removeCallbacks(it) }
 val hide = Runnable { hideTipNow() }
 tipHideRunnable = hide
 handler.postDelayed(hide, seconds * 1000L)
 }

 private fun hideTipNow() {
 tipHideRunnable?.let { handler.removeCallbacks(it) }
 tipHideRunnable = null
 val tv = tipView
 if (tv!= null) {
 try { wm?.removeView(tv) } catch (_: Exception) {}
 }
 tipView = null
 }

 // ═══════════════════════════════════════════════════════════════════
 // ПИЛОТ MINECRAFT: круглая кнопка → растягиваемое окно с промптом
 // Кнопка живёт поверх любой игры, окно масштабируется пальцем.
 // ═══════════════════════════════════════════════════════════════════

 private fun dp(v: Float): Int = (v * resources.displayMetrics.density).roundToInt()

 private fun overlayType(): Int =
 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
 WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
 else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

 private fun sendPilotCommand(cmd: String) {
 setPilotStatus("▶ $cmd")
 sendBroadcast(Intent(ACTION_PILOT_CMD).putExtra(EXTRA_CMD, cmd))
 }

 private fun setPilotStatus(st: String) {
 pilotStatusView?.let { it.text = if (st.isEmpty()) "Готова к запуску" else st }
 }

 private fun hidePilotOverlay() {
 hidePilotWindow()
 pilotButton?.let { try { wm?.removeView(it) } catch (_: Exception) {} }
 pilotButton = null
 }

 private fun showPilotButton() {
 if (pilotButton == null) {
 try { if (wm == null) wm = getSystemService(WindowManager::class.java) } catch (_: Exception) {}
 val wm0 = wm?: return

 val btn = LinearLayout(this).apply {
 orientation = LinearLayout.VERTICAL
 gravity = Gravity.CENTER
 val bg = GradientDrawable().apply {
 shape = GradientDrawable.OVAL
 setColor(Color.parseColor("#CC20204A"))
 setStroke(dp(1.5f), Color.parseColor("#FF8B7CF6"))
 }
 background = bg
 addView(TextView(this@AikaOverlayService).apply {
 text = "П"; textSize = 22f
 setTextColor(0xFFEDE7FF.toInt())
 setTypeface(typeface, android.graphics.Typeface.BOLD)
 })
 }

 val p = WindowManager.LayoutParams(
 dp(52f), dp(52f),
 overlayType(),
 WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
 WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
 PixelFormat.TRANSLUCENT
).apply {
 gravity = Gravity.TOP or Gravity.START
 x = resources.displayMetrics.widthPixels - dp(76f)
 y = dp(170f)
 }

 // Тап = окно, движение = перетаскивание
 btn.setOnTouchListener { _, ev ->
 val pp = pilotButtonParams
 when (ev.actionMasked) {
 MotionEvent.ACTION_DOWN -> {
 touchStartX = ev.rawX; touchStartY = ev.rawY; isDragging = false
 true
 }
 MotionEvent.ACTION_MOVE -> {
 if (pp == null) return@setOnTouchListener true
 val dx = ev.rawX - touchStartX
 val dy = ev.rawY - touchStartY
 if (abs(dx) > 8 || abs(dy) > 8) isDragging = true
 if (isDragging) {
 pp.x = (pp.x + dx).toInt()
 pp.y = (pp.y + dy).toInt()
 touchStartX = ev.rawX; touchStartY = ev.rawY
 try { wm?.updateViewLayout(pilotButton, pp) } catch (_: Exception) {}
 }
 true
 }
 MotionEvent.ACTION_UP -> {
 if (!isDragging) togglePilotWindow()
 else { /* кнопка уже перетащена */ }
 true
 }
 else -> false
 }
 }

 try {
 wm0.addView(btn, p)
 pilotButton = btn
 pilotButtonParams = p
 Log.i(TAG, "pilot button shown")
 } catch (e: Exception) {
 Log.e(TAG, "pilot button failed: ${e.message}")
 }
 } else {
 togglePilotWindow()
 }
 }

 private fun togglePilotWindow() {
 if (pilotWindow!= null) hidePilotWindow() else showPilotWindow()
 }

 private fun hidePilotWindow() {
 pilotWindow?.let { try { wm?.removeView(it) } catch (_: Exception) {} }
 pilotWindow = null
 pilotWindowParams = null
 }

 private fun chip(label: String, cmd: String): TextView {
 return TextView(this).apply {
 text = label
 textSize = 12f
 setTextColor(0xFFEDE7FF.toInt())
 setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
 val bg = GradientDrawable().apply {
 cornerRadius = dp(16f).toFloat()
 setColor(Color.parseColor("#2A2340"))
 setStroke(dp(1f), Color.parseColor("#558B7CF6"))
 }
 background = bg
 setOnClickListener { sendPilotCommand(cmd) }
 }
 }

 @SuppressLint("InflateParams")
 private fun showPilotWindow() {
 try { if (wm == null) wm = getSystemService(WindowManager::class.java) } catch (_: Exception) {}
 val wm0 = wm?: return
 val sw = resources.displayMetrics.widthPixels
 val sh = resources.displayMetrics.heightPixels

 val root = LinearLayout(this).apply {
 orientation = LinearLayout.VERTICAL
 val bg = GradientDrawable().apply {
 cornerRadius = dp(14f).toFloat()
 setColor(Color.parseColor("#F2141430"))
 setStroke(dp(1f), Color.parseColor("#668B7CF6"))
 }
 background = bg
 setPadding(dp(10f), dp(8f), dp(10f), dp(6f))
 }

 // ── Шапка: тянешь за неё — двигаешь окно ──
 val header = LinearLayout(this).apply {
 orientation = LinearLayout.HORIZONTAL
 gravity = Gravity.CENTER_VERTICAL
 }
 header.addView(TextView(this).apply {
 text = "Minecraft-пилот"
 setTextColor(0xFFEDE7FF.toInt())
 textSize = 14f
 setTypeface(typeface, android.graphics.Typeface.BOLD)
 }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
 header.addView(TextView(this).apply {
 text = "×"
 setTextColor(0x99FFFFFF.toInt())
 textSize = 16f
 setPadding(dp(12f), dp(4f), dp(12f), dp(4f))
 setOnClickListener { hidePilotWindow() }
 })
 root.addView(header)

 // ── Ввод промпта ──
 val input = android.widget.EditText(this).apply {
 hint = "промпт: наруби дерево / построй дом…"
 setHintTextColor(0x66FFFFFF.toInt())
 setTextColor(0xFFF2EFFF.toInt())
 textSize = 13f
 setSingleLine(true)
 imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEND
 val bg = GradientDrawable().apply {
 cornerRadius = dp(8f).toFloat()
 setColor(Color.parseColor("#221A2E"))
 }
 background = bg
 setPadding(dp(10f), dp(8f), dp(10f), dp(8f))
 }
 pilotInput = input
 root.addView(input, LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
).apply { topMargin = dp(6f) })

 // ── Быстрые команды ──
 val chips = android.widget.HorizontalScrollView(this).apply {
 isHorizontalScrollBarEnabled = false
 }
 val chipRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
 val lp = LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
).apply { rightMargin = dp(6f) }
 chipRow.addView(chip(" дерево", "наруби дерево"), lp)
 chipRow.addView(chip(" копай", "прокопайся вниз 3 блока"), lp)
 chipRow.addView(chip(" прямо", "беги прямо 3 секунды"), lp)
 chipRow.addView(chip(" броди", "поброди 20 секунд"), lp)
 chipRow.addView(chip(" стоп", "стоп"), lp)
 chips.addView(chipRow)
 root.addView(chips, LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
).apply { topMargin = dp(6f) })

 // ── Кнопка «Старт» ──
 val startBtn = TextView(this).apply {
 text = "▶ Старт"
 setTextColor(0xFF0A0618.toInt())
 textSize = 14f
 gravity = Gravity.CENTER
 setTypeface(typeface, android.graphics.Typeface.BOLD)
 setPadding(dp(10f), dp(10f), dp(10f), dp(10f))
 val bg = GradientDrawable().apply {
 cornerRadius = dp(10f).toFloat()
 setColor(Color.parseColor("#FF8B7CF6"))
 }
 background = bg
 setOnClickListener {
 val t = pilotInput?.text?.toString()?.trim()?: ""
 if (t.isEmpty()) { setPilotStatus("Напиши задачу или жми кнопку выше"); return@setOnClickListener }
 sendPilotCommand(t)
 }
 }
 root.addView(startBtn, LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
).apply { topMargin = dp(8f) })

 // ── Статус ──
 val status = TextView(this).apply {
 text = "Готова к запуску"
 setTextColor(0x99FFFFFF.toInt())
 textSize = 11f
 setPadding(0, dp(4f), 0, dp(2f))
 }
 pilotStatusView = status
 root.addView(status)

 // ── Ручка масштабирования (правый нижний угол) ──
 val grip = TextView(this).apply {
 text = "⤢"
 setTextColor(0x99FFFFFF.toInt())
 textSize = 20f
 setPadding(dp(8f), dp(2f), dp(4f), dp(2f))
 }
 root.addView(grip, LinearLayout.LayoutParams(
 LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
).apply { gravity = Gravity.END })

 val winW = (sw * 0.78f).roundToInt().coerceAtMost(dp(430f))
 val p = WindowManager.LayoutParams(
 winW,
 WindowManager.LayoutParams.WRAP_CONTENT,
 overlayType(),
 WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL, // фокус нужен для клавиатуры
 PixelFormat.TRANSLUCENT
).apply {
 gravity = Gravity.TOP or Gravity.START
 x = ((sw - winW) / 2).coerceAtLeast(0)
 y = dp(56f)
 softInputMode = WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or
 WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
 }

 // Движение окна за шапку
 header.setOnTouchListener { _, ev ->
 val pp = pilotWindowParams?: return@setOnTouchListener false
 when (ev.actionMasked) {
 MotionEvent.ACTION_DOWN -> { touchStartX = ev.rawX; touchStartY = ev.rawY; true }
 MotionEvent.ACTION_MOVE -> {
 pp.x = (pp.x + (ev.rawX - touchStartX)).toInt()
 pp.y = (pp.y + (ev.rawY - touchStartY)).toInt()
 touchStartX = ev.rawX; touchStartY = ev.rawY
 try { wm?.updateViewLayout(pilotWindow, pp) } catch (_: Exception) {}
 true
 }
 else -> false
 }
 }

 // Масштабирование за ⤢
 grip.setOnTouchListener { _, ev ->
 val pp = pilotWindowParams?: return@setOnTouchListener false
 val vw = pilotWindow?: return@setOnTouchListener false
 when (ev.actionMasked) {
 MotionEvent.ACTION_DOWN -> {
 if (pp.height == WindowManager.LayoutParams.WRAP_CONTENT) pp.height = vw.height
 pilotResizeStartW = pp.width
 pilotResizeStartH = pp.height
 pilotResizeStartX = ev.rawX
 pilotResizeStartY = ev.rawY
 true
 }
 MotionEvent.ACTION_MOVE -> {
 pp.width = (pilotResizeStartW + (ev.rawX - pilotResizeStartX).toInt())
.coerceIn(dp(240f), sw - dp(20f))
 pp.height = (pilotResizeStartH + (ev.rawY - pilotResizeStartY).toInt())
.coerceIn(dp(150f), sh - dp(140f))
 try { wm?.updateViewLayout(vw, pp) } catch (_: Exception) {}
 true
 }
 else -> false
 }
 }

 // Enter в поле = Старт
 input.setOnEditorActionListener { _, actionId, _ ->
 if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEND) {
 val t = input.text.toString().trim()
 if (t.isNotEmpty()) sendPilotCommand(t)
 true
 } else false
 }

 try {
 wm0.addView(root, p)
 pilotWindow = root
 pilotWindowParams = p
 Log.i(TAG, "pilot window shown ${winW}px")
 } catch (e: Exception) {
 Log.e(TAG, "pilot window failed: ${e.message}")
 }
 }

 private fun createNotificationChannel() {
 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
 val ch = NotificationChannel(CHANNEL_ID, "Aivora Overlay", NotificationManager.IMPORTANCE_MIN)
 ch.setShowBadge(false)
 getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
 }
 }

 private fun buildNotification(): Notification =
 NotificationCompat.Builder(this, CHANNEL_ID)
.setContentTitle("Aivora активна")
.setContentText("Нажми чтобы открыть")
.setSmallIcon(android.R.drawable.ic_dialog_info)
.setPriority(NotificationCompat.PRIORITY_MIN)
.setOngoing(true)
.build()
}

