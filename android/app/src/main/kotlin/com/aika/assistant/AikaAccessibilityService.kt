package com.aika.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel

/**
 * AikaAccessibilityService v2 — глубокое управление через Accessibility API.
 * Поддерживает: клик по тексту/ContentDesc, ввод текста, жесты, управление
 * YouTube/Telegram/Instagram, прокрутка, яркость, навигация.
 */
class AikaAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: AikaAccessibilityService? = null
        fun isRunning() = instance != null
        fun get() = instance
    }

    override fun onServiceConnected() { super.onServiceConnected(); instance = this }
    override fun onUnbind(intent: android.content.Intent?): Boolean { instance = null; return super.onUnbind(intent) }
    override fun onDestroy()     { instance = null; super.onDestroy() }
    override fun onInterrupt()   {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    // ════════════════════════════════════════════════════════════════
    // НАВИГАЦИЯ
    // ════════════════════════════════════════════════════════════════
    fun pressBack()         = performGlobalAction(GLOBAL_ACTION_BACK)
    fun pressHome()         = performGlobalAction(GLOBAL_ACTION_HOME)
    fun openRecents()       = performGlobalAction(GLOBAL_ACTION_RECENTS)
    fun openNotifications() = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
    fun openQuickSettings() = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
    fun lockScreen()        = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
    fun takeScreenshot()    = if (Build.VERSION.SDK_INT >= 28) performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT) else false
    fun closeCurrentApp() {
        // Show recents then swipe up to close
        performGlobalAction(GLOBAL_ACTION_RECENTS)
    }

    // ════════════════════════════════════════════════════════════════
    // ЖЕСТЫ
    // ════════════════════════════════════════════════════════════════
    fun tapAt(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y); lineTo(x + 1f, y + 1f) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 50L)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun tapAtPercent(xPct: Float, yPct: Float): Boolean {
        val display = applicationContext.resources.displayMetrics
        return tapAt(display.widthPixels * xPct, display.heightPixels * yPct)
    }

    fun doubleTapAt(x: Float, y: Float): Boolean {
        tapAt(x, y)
        Thread.sleep(100)
        return tapAt(x, y)
    }

    fun longTapAt(x: Float, y: Float, durationMs: Long = 800L): Boolean {
        val path = Path().apply { moveTo(x, y); lineTo(x + 1f, y + 1f) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun swipe(direction: String, speedMs: Long = 400L): Boolean {
        val display = applicationContext.resources.displayMetrics
        val w = display.widthPixels.toFloat()
        val h = display.heightPixels.toFloat()
        val (x1, y1, x2, y2) = when (direction.lowercase()) {
            "up"    -> listOf(w / 2, h * 0.75f, w / 2, h * 0.25f)
            "down"  -> listOf(w / 2, h * 0.25f, w / 2, h * 0.75f)
            "left"  -> listOf(w * 0.8f, h / 2, w * 0.2f, h / 2)
            "right" -> listOf(w * 0.2f, h / 2, w * 0.8f, h / 2)
            else    -> listOf(w / 2, h * 0.75f, w / 2, h * 0.25f)
        }
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, speedMs)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun pressEnter(): Boolean {
        val root = rootInActiveWindow ?: return false
        val input = findFocusedInput(root)
        return input?.performAction(AccessibilityNodeInfo.ACTION_IME_ENTER) ?: false
    }

    // ════════════════════════════════════════════════════════════════
    // ПОИСК УЗЛОВ
    // ════════════════════════════════════════════════════════════════

    private fun allNodes(root: AccessibilityNodeInfo): List<AccessibilityNodeInfo> {
        val result = mutableListOf<AccessibilityNodeInfo>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            result.add(node)
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return result
    }

    /** Найти узел по тексту (точное совпадение или содержит) */
    fun findByText(text: String, exact: Boolean = false): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return allNodes(root).firstOrNull { node ->
            val nodeText = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            if (exact) nodeText.equals(text, ignoreCase = true) || desc.equals(text, ignoreCase = true)
            else nodeText.contains(text, ignoreCase = true) || desc.contains(text, ignoreCase = true)
        }
    }

    /** Найти узел по contentDescription */
    fun findByContentDesc(desc: String): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return allNodes(root).firstOrNull { node ->
            node.contentDescription?.toString()?.contains(desc, ignoreCase = true) == true
        }
    }

    /** Найти кликабельный узел */
    private fun findClickable(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val nodes = allNodes(root)
        return nodes.firstOrNull { node ->
            node.isClickable && (
                node.text?.toString()?.contains(text, ignoreCase = true) == true ||
                node.contentDescription?.toString()?.contains(text, ignoreCase = true) == true
            )
        } ?: nodes.firstOrNull { node ->
            node.text?.toString()?.contains(text, ignoreCase = true) == true ||
            node.contentDescription?.toString()?.contains(text, ignoreCase = true) == true
        }
    }

    private fun findFocusedInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        return allNodes(root).firstOrNull { it.isFocused && it.isEditable }
            ?: allNodes(root).firstOrNull { it.isEditable }
    }

    // ════════════════════════════════════════════════════════════════
    // КЛИК
    // ════════════════════════════════════════════════════════════════

    fun clickByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findClickable(root, text) ?: return false
        return clickNode(node)
    }

    fun clickByContentDesc(desc: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = allNodes(root).firstOrNull { n ->
            n.contentDescription?.toString()?.contains(desc, ignoreCase = true) == true
        } ?: return false
        return clickNode(node)
    }

    fun clickFirstListItem(): Boolean {
        val root = rootInActiveWindow ?: return false
        val listNode = allNodes(root).firstOrNull { n ->
            n.className?.contains("RecyclerView") == true ||
            n.className?.contains("ListView") == true
        }
        val target = listNode?.getChild(0) ?: return false
        return clickNode(target)
    }

    private fun clickNode(node: AccessibilityNodeInfo): Boolean {
        // Try direct click first
        if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        // Fallback: click via bounds
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        if (!bounds.isEmpty) {
            tapAt(bounds.centerX().toFloat(), bounds.centerY().toFloat())
            return true
        }
        return false
    }

    // ════════════════════════════════════════════════════════════════
    // ВВОД ТЕКСТА
    // ════════════════════════════════════════════════════════════════

    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val input = findFocusedInput(root) ?: return false
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        return input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun appendText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val input = findFocusedInput(root) ?: return false
        val current = input.text?.toString() ?: ""
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, current + text)
        return input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    // ════════════════════════════════════════════════════════════════
    // ГРОМКОСТЬ (через симуляцию кнопок)
    // ════════════════════════════════════════════════════════════════

    fun changeVolume(direction: String, steps: Int = 2) {
        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        repeat(steps) {
            when (direction.lowercase()) {
                "up"   -> am.adjustStreamVolume(
                    android.media.AudioManager.STREAM_MUSIC,
                    android.media.AudioManager.ADJUST_RAISE, 0)
                "down" -> am.adjustStreamVolume(
                    android.media.AudioManager.STREAM_MUSIC,
                    android.media.AudioManager.ADJUST_LOWER, 0)
                "mute" -> am.adjustStreamVolume(
                    android.media.AudioManager.STREAM_MUSIC,
                    android.media.AudioManager.ADJUST_MUTE, 0)
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // ЯРКОСТЬ
    // ════════════════════════════════════════════════════════════════

    fun changeBrightness(direction: String) {
        try {
            val cr = contentResolver
            android.provider.Settings.System.putInt(cr,
                android.provider.Settings.System.SCREEN_BRIGHTNESS_MODE,
                android.provider.Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
            val current = android.provider.Settings.System.getInt(cr,
                android.provider.Settings.System.SCREEN_BRIGHTNESS, 128)
            val next = when (direction.lowercase()) {
                "up"   -> (current + 40).coerceAtMost(255)
                "down" -> (current - 40).coerceAtLeast(0)
                else   -> current
            }
            android.provider.Settings.System.putInt(cr,
                android.provider.Settings.System.SCREEN_BRIGHTNESS, next)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ════════════════════════════════════════════════════════════════
    // ПОЛУЧИТЬ ИНФОРМАЦИЮ ОБ ЭКРАНЕ
    // ════════════════════════════════════════════════════════════════

    fun getScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val texts = allNodes(root).mapNotNull { it.text?.toString()?.trim() }
            .filter { it.isNotEmpty() }
        return texts.joinToString(" | ")
    }

    fun getCurrentApp(): String {
        return rootInActiveWindow?.packageName?.toString() ?: ""
    }

    // ════════════════════════════════════════════════════════════════
    // FLUTTER METHOD CHANNEL HANDLER
    // ════════════════════════════════════════════════════════════════

    fun handleMethodCall(method: String, args: Map<*, *>?, result: MethodChannel.Result) {
        when (method) {
            "pressBack"         -> result.success(pressBack())
            "pressHome"         -> result.success(pressHome())
            "openRecents"       -> result.success(openRecents())
            "openNotifications" -> result.success(openNotifications())
            "openQuickSettings" -> result.success(openQuickSettings())
            "lockScreen"        -> result.success(lockScreen())
            "takeScreenshot"    -> result.success(takeScreenshot())
            "closeCurrentApp"   -> { closeCurrentApp(); result.success(true) }
            "clickByText"       -> {
                val text = args?.get("text") as? String ?: ""
                result.success(clickByText(text))
            }
            "clickByContentDesc" -> {
                val desc = args?.get("desc") as? String ?: ""
                result.success(clickByContentDesc(desc))
            }
            "clickFirstListItem" -> result.success(clickFirstListItem())
            "typeText"          -> {
                val text = args?.get("text") as? String ?: ""
                result.success(typeText(text))
            }
            "pressEnter"        -> result.success(pressEnter())
            "tapAt"             -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 0f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 0f
                result.success(tapAt(x, y))
            }
            "tapAtPercent"      -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 0.5f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 0.5f
                result.success(tapAtPercent(x, y))
            }
            "swipe"             -> {
                val dir = args?.get("direction") as? String ?: "up"
                val speed = when (args?.get("speed") as? String) {
                    "fast"  -> 200L
                    "slow"  -> 800L
                    else    -> 400L
                }
                result.success(swipe(dir, speed))
            }
            "changeVolume"      -> {
                val dir   = args?.get("direction") as? String ?: "up"
                val steps = (args?.get("steps") as? Number)?.toInt() ?: 2
                changeVolume(dir, steps)
                result.success(true)
            }
            "changeBrightness"  -> {
                val dir = args?.get("direction") as? String ?: "up"
                changeBrightness(dir)
                result.success(true)
            }
            "getScreenText"     -> result.success(getScreenText())
            "getCurrentApp"     -> result.success(getCurrentApp())
            else                -> result.notImplemented()
        }
    }
}
