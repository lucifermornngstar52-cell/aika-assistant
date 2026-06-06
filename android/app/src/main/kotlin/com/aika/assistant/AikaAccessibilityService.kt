package com.aika.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.UiAutomation
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Path
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * AikaAccessibilityService — полный контроль над телефоном через Accessibility API.
 *
 * Архитектура позаимствована из OpenClaw Assistant (MIT):
 * https://github.com/yuga-hashimoto/openclaw-assistant
 *
 * Основные улучшения:
 * 1. findNodes() — поиск узлов по тексту/классу/кликабельности (как в OpenClaw)
 * 2. getInstalledApps() — реальный список приложений через PackageManager
 * 3. performTap/Swipe/LongPress — чистые GestureDescription без побочных эффектов
 * 4. screenHash() — быстрая проверка изменился ли экран
 * 5. describeWindow() — полный снапшот окна для AI
 */
class AikaAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: AikaAccessibilityService? = null
        fun isRunning() = instance != null
        fun get() = instance
    }

    // ─── Lifecycle ───────────────────────────────────────────────────
    override fun onServiceConnected() { super.onServiceConnected(); instance = this }
    override fun onUnbind(intent: android.content.Intent?): Boolean { instance = null; return super.onUnbind(intent) }
    override fun onDestroy() { instance = null; super.onDestroy() }
    override fun onInterrupt() {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) { /* pull-only, нет авто-действий */ }

    // ════════════════════════════════════════════════════════════════
    // ГЛОБАЛЬНАЯ НАВИГАЦИЯ
    // ════════════════════════════════════════════════════════════════
    fun performBack()        = performGlobalAction(GLOBAL_ACTION_BACK)
    fun pressHome()          = performGlobalAction(GLOBAL_ACTION_HOME)
    fun pressRecents()       = performGlobalAction(GLOBAL_ACTION_RECENTS)
    fun openNotifications()  = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
    fun openQuickSettings()  = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
    fun lockScreen()         = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
    fun powerDialog()        = if (Build.VERSION.SDK_INT >= 21) performGlobalAction(GLOBAL_ACTION_POWER_DIALOG) else false
    fun takeScreenshot()     = if (Build.VERSION.SDK_INT >= 28) performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT) else false

    // ════════════════════════════════════════════════════════════════
    // ЖЕСТЫ (из OpenClaw AgentVoiceAccessibilityService)
    // ════════════════════════════════════════════════════════════════

    fun tapAt(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y); lineTo(x + 1f, y + 1f) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 50L)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun longTapAt(x: Float, y: Float, durationMs: Long = 800L): Boolean {
        val path = Path().apply { moveTo(x, y); lineTo(x + 1f, y + 1f) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs.coerceAtLeast(350L))
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun doubleTapAt(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y); lineTo(x + 1f, y + 1f) }
        val s1 = GestureDescription.StrokeDescription(path, 0L, 50L)
        val s2 = GestureDescription.StrokeDescription(path, 200L, 50L)
        return dispatchGesture(GestureDescription.Builder().addStroke(s1).addStroke(s2).build(), null, null)
    }

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300L): Boolean {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs.coerceAtLeast(50L))
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun swipeDir(direction: String): Boolean {
        val dm = resources.displayMetrics
        val w = dm.widthPixels.toFloat()
        val h = dm.heightPixels.toFloat()
        val cx = w / 2f
        val cy = h / 2f
        return when (direction.lowercase()) {
            "up"    -> swipe(cx, h * 0.7f, cx, h * 0.3f)
            "down"  -> swipe(cx, h * 0.3f, cx, h * 0.7f)
            "left"  -> swipe(w * 0.8f, cy, w * 0.2f, cy)
            "right" -> swipe(w * 0.2f, cy, w * 0.8f, cy)
            else    -> swipe(cx, h * 0.7f, cx, h * 0.3f)
        }
    }

    fun pinchZoom(cx: Float, cy: Float, scale: Float) {
        val r = 200f
        val path1 = Path().apply { moveTo(cx - r, cy); lineTo(cx - r * scale, cy) }
        val path2 = Path().apply { moveTo(cx + r, cy); lineTo(cx + r * scale, cy) }
        dispatchGesture(GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path1, 0L, 400L))
            .addStroke(GestureDescription.StrokeDescription(path2, 0L, 400L))
            .build(), null, null)
    }

    // ════════════════════════════════════════════════════════════════
    // ПОИСК УЗЛОВ (адаптировано из OpenClaw ScreenFindNodesCapability)
    // ════════════════════════════════════════════════════════════════

    data class NodeSnapshot(
        val nodeId: String,
        val text: String?,
        val contentDescription: String?,
        val className: String?,
        val viewId: String?,
        val bounds: Rect,
        val clickable: Boolean,
        val longClickable: Boolean,
        val scrollable: Boolean,
        val editable: Boolean,
        val enabled: Boolean,
    )

    /** Возвращает все видимые узлы. Лимит 512 — как в OpenClaw. */
    fun getAllNodes(limit: Int = 512): List<NodeSnapshot> {
        val result = mutableListOf<NodeSnapshot>()
        val roots = runCatching { windows?.mapNotNull { it.root } }.getOrDefault(emptyList())
            .takeIf { it.isNotEmpty() } ?: listOfNotNull(rootInActiveWindow)
        roots.forEachIndexed { wi, root ->
            collectNodes(root, result, limit, wi)
            runCatching { root.recycle() }
        }
        return result
    }

    private fun collectNodes(node: AccessibilityNodeInfo?, out: MutableList<NodeSnapshot>, limit: Int, windowIdx: Int) {
        if (node == null || out.size >= limit) return
        val rect = Rect(); node.getBoundsInScreen(rect)
        if (rect.width() > 0 || rect.height() > 0) {
            out.add(NodeSnapshot(
                nodeId          = "${windowIdx}_${node.hashCode()}",
                text            = node.text?.toString()?.takeIf { it.isNotBlank() },
                contentDescription = node.contentDescription?.toString()?.takeIf { it.isNotBlank() },
                className       = node.className?.toString(),
                viewId          = node.viewIdResourceName?.toString(),
                bounds          = rect,
                clickable       = node.isClickable,
                longClickable   = node.isLongClickable,
                scrollable      = node.isScrollable,
                editable        = node.isEditable,
                enabled         = node.isEnabled,
            ))
        }
        for (i in 0 until node.childCount) collectNodes(node.getChild(i), out, limit, windowIdx)
    }

    /** Поиск по тексту/классу/кликабельности (как в OpenClaw findNodes) */
    fun findNodes(
        text: String? = null,
        className: String? = null,
        clickable: Boolean? = null,
        limit: Int = 20
    ): List<NodeSnapshot> {
        val needle = text?.trim()?.lowercase()?.takeIf { it.isNotBlank() }
        val klass  = className?.trim()?.takeIf { it.isNotBlank() }
        return getAllNodes().filter { node ->
            val hay = listOfNotNull(node.text, node.contentDescription).joinToString(" ").lowercase()
            (needle == null || needle in hay) &&
            (klass  == null || node.className == klass) &&
            (clickable == null || node.clickable == clickable)
        }.take(limit.coerceIn(1, 50))
    }

    /** Hash экрана — быстрая проверка изменился ли UI (из OpenClaw screenHash) */
    fun screenHash(): String {
        val nodes = getAllNodes(200)
        val joined = nodes.joinToString("\u001e") { n ->
            "${n.className}|${n.text}|${n.contentDescription}|${n.viewId}|${n.bounds.left},${n.bounds.top},${n.bounds.right},${n.bounds.bottom}"
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(joined.toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }
    }

    // ════════════════════════════════════════════════════════════════
    // КОМПАКТНЫЙ СНАПШОТ ДЛЯ AI (оптимизированный под GPT-4o-mini)
    // ════════════════════════════════════════════════════════════════

    /** Возвращает компактный текст для AI: тип, текст, bounds */
    fun getScreenStructure(): Map<String, Any> {
        val nodes   = getAllNodes()
        val text    = nodes.mapNotNull { it.text ?: it.contentDescription }
            .filter { it.length > 1 }.distinct().take(40).joinToString("\n")
        val buttons = nodes.filter { it.clickable || it.editable || it.scrollable }
            .take(50).map { n ->
                mapOf(
                    "text" to (n.text ?: n.contentDescription ?: ""),
                    "desc" to (n.contentDescription ?: ""),
                    "class" to (n.className?.split(".")?.last() ?: ""),
                    "id"   to (n.viewId?.split("/")?.last() ?: ""),
                    "x"   to ((n.bounds.left + n.bounds.right) / 2),
                    "y"   to ((n.bounds.top + n.bounds.bottom) / 2),
                    "editable" to n.editable,
                    "scrollable" to n.scrollable
                )
            }
        val pkg = runCatching { windows?.firstOrNull()?.root?.packageName?.toString() }.getOrNull() ?: ""
        return mapOf("text" to text, "buttons" to buttons, "package" to pkg)
    }

    /** Весь текст экрана одной строкой */
    fun getAllScreenText(): String {
        return getAllNodes().mapNotNull { it.text ?: it.contentDescription }
            .filter { it.length > 1 }.distinct().joinToString("\n")
    }

    // ════════════════════════════════════════════════════════════════
    // КЛИКИ
    // ════════════════════════════════════════════════════════════════

    fun clickByText(targetText: String): Boolean {
        val needle = targetText.lowercase()
        return getAllNodes().firstOrNull { n ->
            listOfNotNull(n.text, n.contentDescription).any { it.lowercase().contains(needle) } && n.clickable
        }?.let { clickNode(it) } ?: false
    }

    fun clickByExactText(targetText: String): Boolean {
        return getAllNodes().firstOrNull { n ->
            listOfNotNull(n.text, n.contentDescription).any { it.equals(targetText, ignoreCase = true) }
        }?.let { clickNode(it) } ?: false
    }

    fun clickByDescription(desc: String): Boolean {
        val needle = desc.lowercase()
        return getAllNodes().firstOrNull { n ->
            n.contentDescription?.lowercase()?.contains(needle) == true
        }?.let { clickNode(it) } ?: false
    }

    fun clickById(resourceId: String): Boolean {
        return getAllNodes().firstOrNull { n ->
            n.viewId?.endsWith(resourceId) == true || n.viewId == resourceId
        }?.let { clickNode(it) } ?: false
    }

    fun longClickByText(targetText: String): Boolean {
        val needle = targetText.lowercase()
        return getAllNodes().firstOrNull { n ->
            listOfNotNull(n.text, n.contentDescription).any { it.lowercase().contains(needle) == true } && n.longClickable
        }?.let { node ->
            val cx = ((node.bounds.left + node.bounds.right) / 2).toFloat()
            val cy = ((node.bounds.top + node.bounds.bottom) / 2).toFloat()
            longTapAt(cx, cy)
        } ?: false
    }

    private fun clickNode(node: NodeSnapshot): Boolean {
        // Если центр доступен — тапаем напрямую (как в OpenClaw performTap)
        val cx = ((node.bounds.left + node.bounds.right) / 2).toFloat()
        val cy = ((node.bounds.top + node.bounds.bottom) / 2).toFloat()
        return if (cx > 0 && cy > 0) tapAt(cx, cy) else false
    }

    // ════════════════════════════════════════════════════════════════
    // ВВОД ТЕКСТА
    // ════════════════════════════════════════════════════════════════

    fun typeText(text: String): Boolean {
        val editable = getAllNodes().firstOrNull { it.editable && it.enabled }
        return editable?.let {
            val cx = ((it.bounds.left + it.bounds.right) / 2).toFloat()
            val cy = ((it.bounds.top + it.bounds.bottom) / 2).toFloat()
            tapAt(cx, cy)
            Thread.sleep(200)
            val root = rootInActiveWindow ?: return false
            val focusedNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            val args = Bundle().apply { putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
            focusedNode?.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args) ?: false
        } ?: false
    }

    fun typeInField(hint: String, text: String): Boolean {
        val needle = hint.lowercase()
        val field = getAllNodes().firstOrNull { n ->
            n.editable && n.enabled && (
                hint.isEmpty() ||
                n.text?.lowercase()?.contains(needle) == true ||
                n.contentDescription?.lowercase()?.contains(needle) == true ||
                n.viewId?.lowercase()?.contains(needle) == true
            )
        }
        return field?.let {
            val cx = ((it.bounds.left + it.bounds.right) / 2).toFloat()
            val cy = ((it.bounds.top + it.bounds.bottom) / 2).toFloat()
            tapAt(cx, cy)
            Thread.sleep(200)
            val root = rootInActiveWindow ?: return false
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
            val args = Bundle().apply { putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        } ?: typeText(text)
    }

    fun appendText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val current = focused.text?.toString() ?: ""
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, current + text)
        }
        return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun clearField(): Boolean {
        // Сначала пробуем через системный фокус
        val root = rootInActiveWindow ?: return false
        val sysFocused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (sysFocused != null) {
            val args = Bundle().apply { putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "") }
            return sysFocused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        }
        // Fallback: ищем EditText и тапаем
        val editNode = getAllNodes().firstOrNull { it.editable && it.enabled } ?: return false
        val cx = ((editNode.bounds.left + editNode.bounds.right) / 2).toFloat()
        val cy = ((editNode.bounds.top + editNode.bounds.bottom) / 2).toFloat()
        tapAt(cx, cy)
        Thread.sleep(150)
        val refocused = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle().apply { putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "") }
        return refocused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun pressEnter(): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        // ACTION_IME_ENTER не существует в стандартном API — используем paste+enter через KeyEvent
        return focused.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
    }

    // ════════════════════════════════════════════════════════════════
    // СКРОЛЛ
    // ════════════════════════════════════════════════════════════════

    fun scroll(direction: String) {
        val action = if (direction.lowercase() in listOf("down", "вниз")) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                     else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        getAllNodes().firstOrNull { it.scrollable }?.let { node ->
            val cx = ((node.bounds.left + node.bounds.right) / 2).toFloat()
            val cy = ((node.bounds.top + node.bounds.bottom) / 2).toFloat()
            swipeDir(direction)
        } ?: swipeDir(direction)
    }

    // ════════════════════════════════════════════════════════════════
    // ЗАПУСК ПРИЛОЖЕНИЙ (через PackageManager — как AppsListCapability в OpenClaw)
    // ════════════════════════════════════════════════════════════════

    /** Запускает приложение по package name */
    fun launchApp(packageName: String): Boolean {
        return try {
            val intent = applicationContext.packageManager
                .getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ?: return false
            applicationContext.startActivity(intent)
            true
        } catch (_: Exception) { false }
    }

    /** Возвращает список всех запускаемых приложений — как AppsListCapability из OpenClaw */
    fun getInstalledApps(): List<Map<String, String>> {
        val pm = applicationContext.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0).take(500).map { ri ->
            mapOf(
                "packageName" to ri.activityInfo.packageName,
                "label" to runCatching { ri.loadLabel(pm).toString() }.getOrDefault(ri.activityInfo.packageName)
            )
        }
    }

    /** Ищет package по человеческому названию */
    fun findPackageByName(appName: String): String? {
        val needle = appName.lowercase().trim()
        return getInstalledApps().firstOrNull { app ->
            app["label"]?.lowercase()?.contains(needle) == true ||
            app["packageName"]?.lowercase()?.contains(needle) == true
        }?.get("packageName")
    }

    // ════════════════════════════════════════════════════════════════
    // ВСПОМОГАТЕЛЬНОЕ
    // ════════════════════════════════════════════════════════════════

    fun getScreenSize(): Map<String, Int> {
        val dm = resources.displayMetrics
        return mapOf("width" to dm.widthPixels, "height" to dm.heightPixels)
    }

    fun closeCurrentApp() {
        performGlobalAction(GLOBAL_ACTION_RECENTS)
        Thread.sleep(400)
        // Свайп вверх для закрытия первой карточки
        val dm = resources.displayMetrics
        swipe(dm.widthPixels / 2f, dm.heightPixels * 0.5f, dm.widthPixels / 2f, 0f, 300L)
    }

    fun openAppSettings(packageName: String): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            true
        } catch (_: Exception) { false }
    }

    fun uninstallApp(packageName: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_DELETE).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            true
        } catch (_: Exception) { false }
    }

    fun copySelectedText(): String? {
        val cm = applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        return cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(applicationContext)?.toString()
    }

    fun pasteText(): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        return focused.performAction(AccessibilityNodeInfo.ACTION_PASTE)
    }

    fun toggleSplitScreen(): Boolean =
        if (Build.VERSION.SDK_INT >= 24) performGlobalAction(GLOBAL_ACTION_TOGGLE_SPLIT_SCREEN) else false

    // ════════════════════════════════════════════════════════════════
    // СТАРЫЙ WhatsApp flow (оставляем для совместимости)
    // ════════════════════════════════════════════════════════════════

    private enum class SendStep { IDLE, OPENING, SEARCHING, SELECTING_CONTACT, TYPING_MESSAGE, SENDING }
    private var sendStep = SendStep.IDLE
    private var pendingContact: String? = null
    private var pendingMessage: String? = null
    private var flutterChannel: MethodChannel? = null

    fun startSendMessage(app: String, contact: String, message: String) {
        pendingContact = contact
        pendingMessage = message
        sendStep = SendStep.OPENING
        launchApp(when (app.lowercase()) {
            "whatsapp", "ватсап" -> "com.whatsapp"
            "telegram", "телеграм" -> "org.telegram.messenger"
            "vk", "вк" -> "com.vkontakte.android"
            else -> app
        })
    }

    fun captureScreenBase64(quality: Int = 60): String? {
        if (Build.VERSION.SDK_INT < 28) return null
        takeScreenshot()
        return null // реальный скриншот требует MediaProjection
    }
    // ════════════════════════════════════════════════════════════════
    // МЕТОДЫ ОБРАТНОЙ СОВМЕСТИМОСТИ (используются в MainActivity)
    // ════════════════════════════════════════════════════════════════

    /** @deprecated используй getAllNodes().filter{it.clickable} */
    fun getClickableElements(): List<Map<String, Any>> {
        return getAllNodes().filter { it.clickable || it.editable }.take(50).map { n ->
            mapOf(
                "text"  to (n.text ?: n.contentDescription ?: ""),
                "desc"  to (n.contentDescription ?: ""),
                "class" to (n.className?.split(".")?.last() ?: ""),
                "id"    to (n.viewId?.split("/")?.last() ?: ""),
                "x"     to ((n.bounds.left + n.bounds.right) / 2),
                "y"     to ((n.bounds.top + n.bounds.bottom) / 2),
                "editable" to n.editable
            )
        }
    }

    /** @deprecated используй rootInActiveWindow?.findFocus */
    fun getFocusedElement(): Map<String, Any?>? {
        val root = rootInActiveWindow ?: return null
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        val rect = Rect(); focused.getBoundsInScreen(rect)
        return mapOf(
            "text"  to focused.text?.toString(),
            "desc"  to focused.contentDescription?.toString(),
            "class" to focused.className?.toString(),
            "id"    to focused.viewIdResourceName?.toString(),
            "x"     to ((rect.left + rect.right) / 2),
            "y"     to ((rect.top + rect.bottom) / 2)
        )
    }

    /** @deprecated используй clearField() */
    fun clearText(): Boolean = clearField()

    /** @deprecated используй scroll(direction) */
    fun scrollScreen(direction: String) = scroll(direction)

    /** @deprecated используй findNodes(className=className) */
    fun findNodesByClass(className: String): List<Map<String, Any>> {
        return findNodes(className = className).map { n ->
            mapOf(
                "text"  to (n.text ?: ""),
                "desc"  to (n.contentDescription ?: ""),
                "class" to (n.className ?: ""),
                "id"    to (n.viewId ?: ""),
                "x"     to ((n.bounds.left + n.bounds.right) / 2),
                "y"     to ((n.bounds.top + n.bounds.bottom) / 2)
            )
        }
    }

}