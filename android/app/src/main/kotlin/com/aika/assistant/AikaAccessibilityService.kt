package com.aika.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.pm.PackageManager
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo

class AikaAccessibilityService : AccessibilityService() {

    companion object {
        var instance: AikaAccessibilityService? = null
        var screenEventSink: ((Any?) -> Unit)? = null
        private const val TAG = "AikaA11y"
        const val ACTION_SCREEN_EVENT = "com.aika.SCREEN_EVENT"
    }

    private val handler = Handler(Looper.getMainLooper())

    // ── Состояние отправки сообщения ──────────────────────────────────────────
    var pendingApp: String?     = null
    var pendingContact: String? = null
    var pendingMessage: String? = null
    var sendStep: String        = "idle"
    var flutterChannel: io.flutter.plugin.common.MethodChannel? = null

    // ═══════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════

    override fun onServiceConnected() {
        instance = this
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.eventTypes        = AccessibilityEvent.TYPES_ALL_MASK
        info.feedbackType      = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags             = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                                 AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                                 AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY
                                 // FLAG_REQUEST_TOUCH_EXPLORATION_MODE убран — он перехватывал тачскрин
        info.notificationTimeout = 100
        serviceInfo = info
        Log.i(TAG, "AikaAccessibilityService connected ✅")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    // ═══════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                val pkg = event.packageName?.toString() ?: return
                if (pkg == "com.aika.assistant") return
                val label = try {
                    packageManager.getApplicationLabel(
                        packageManager.getApplicationInfo(pkg, 0)
                    ).toString()
                } catch (_: Exception) { pkg }
                handler.post {
                    screenEventSink?.invoke(mapOf("package" to pkg, "label" to label))
                }
            }
        }
        // Шаги отправки сообщений
        if (sendStep != "idle") processStep(event)
    }

    override fun onInterrupt() {}

    // ═══════════════════════════════════════════════════════════════════
    // ── SEND MESSAGE (Telegram / WhatsApp / VK) ──────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun startSendMessage(app: String, contact: String, message: String) {
        pendingApp     = app
        pendingContact = contact
        pendingMessage = message
        sendStep       = "waiting_for_app"
    }

    private fun processStep(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        when (sendStep) {
            "waiting_for_app" -> {
                if (pkg == pendingApp) {
                    handler.postDelayed({ findAndClickContact() }, 800)
                    sendStep = "searching_contact"
                }
            }
            "searching_contact" -> findAndClickContact()
            "typing_contact"    -> { handler.postDelayed({ clickContactFromSearch() }, 600); sendStep = "clicking_contact" }
            "clicking_contact"  -> clickContactFromSearch()
            "waiting_for_chat"  -> waitForChatAndType()
            "typing_message"    -> {
                val root = rootInActiveWindow ?: return
                val node = findMessageInput(root)
                if (node != null) { typeMessageInField(node); sendStep = "sending" }
            }
            "sending"           -> clickSendButton()
        }
    }

    private fun findAndClickContact() {
        val root = rootInActiveWindow ?: return
        val searchBtn = findSearchButton(root)
        if (searchBtn != null) {
            searchBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeContactName() }, 700)
            sendStep = "typing_contact"
        } else {
            val input = findSearchInput(root)
            if (input != null) { typeContactName(); sendStep = "typing_contact" }
        }
    }

    private fun typeContactName() {
        val root  = rootInActiveWindow ?: return
        val input = findSearchInput(root) ?: return
        val args  = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pendingContact ?: "")
        }
        input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        handler.postDelayed({ clickContactFromSearch() }, 1200)
        sendStep = "clicking_contact"
    }

    private fun clickContactFromSearch() {
        val root  = rootInActiveWindow ?: return
        val node  = findNodeContainingText(root, pendingContact ?: "") ?: return
        clickNodeOrParent(node)
        handler.postDelayed({ waitForChatAndType() }, 1000)
        sendStep = "waiting_for_chat"
    }

    private fun waitForChatAndType() {
        val root = rootInActiveWindow ?: return
        val node = findMessageInput(root)
        if (node != null) {
            typeMessageInField(node)
            sendStep = "sending"
        } else {
            handler.postDelayed({ waitForChatAndType() }, 800)
        }
    }

    private fun typeMessageInField(node: AccessibilityNodeInfo) {
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pendingMessage ?: "")
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        handler.postDelayed({ clickSendButton() }, 600)
    }

    private fun clickSendButton() {
        val root = rootInActiveWindow ?: return
        val btn  = findSendButton(root) ?: return
        clickNodeOrParent(btn)
        resetSend("ok", "Сообщение отправлено")
        notifyFlutter("ok", "Сообщение отправлено")
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── SCREEN TEXT ─────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun getAllScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        collectTextFromNode(root, sb, 0)
        return sb.toString().trim()
    }

    /** Полная структура экрана: текст + кликабельные + окна */
    fun getScreenStructure(): Map<String, Any> {
        val root = rootInActiveWindow ?: return mapOf()
        val text     = StringBuilder()
        val clickable = mutableListOf<Map<String, Any>>()
        collectTextFromNode(root, text, 0)
        collectClickableNodes(root, clickable)
        val windowNames = windows?.mapNotNull { w ->
            val wRoot = w.root ?: return@mapNotNull null
            val t = StringBuilder(); collectTextFromNode(wRoot, t, 0)
            mapOf("type" to w.type, "text" to t.toString().take(200))
        } ?: emptyList()
        return mapOf(
            "text"     to text.toString().trim(),
            "buttons"  to clickable,
            "windows"  to windowNames,
        )
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── CLICK / INTERACTION ─────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun clickByText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeContainingText(root, targetText) ?: return false
        return clickNodeOrParent(node)
    }

    fun clickByExactText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeByExactText(root, targetText) ?: return false
        return clickNodeOrParent(node)
    }

    fun clickByDescription(desc: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeByDescription(root, desc) ?: return false
        return clickNodeOrParent(node)
    }

    fun clickById(resourceId: String): Boolean {
        val root  = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByViewId(resourceId)
        if (nodes.isNullOrEmpty()) return false
        return clickNodeOrParent(nodes[0])
    }

    fun longClickByText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeContainingText(root, targetText) ?: return false
        node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)
        return true
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── TEXT INPUT ──────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun typeInField(hintOrId: String, text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        var node = root.findAccessibilityNodeInfosByViewId(hintOrId)?.firstOrNull()
        if (node == null) node = findEditTextByHint(root, hintOrId)
        if (node == null) node = findBottomEditText(root)
        node ?: return false
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        return true
    }

    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        return true
    }

    fun appendText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val current = node.text?.toString() ?: ""
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, current + text)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        return true
    }

    fun clearText(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        return true
    }

    fun pressEnter(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        node.performAction(AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY)
        return true
    }

    fun copySelectedText(): String? {
        val root = rootInActiveWindow ?: return null
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        node.performAction(0x00040000) // ACTION_SELECT_ALL
        node.performAction(AccessibilityNodeInfo.ACTION_COPY)
        return node.text?.toString()
    }

    fun pasteText(): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        return true
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── SCROLL ──────────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun scroll(direction: String) {
        val root   = rootInActiveWindow ?: return
        val action = if (direction == "up")
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        else
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        scrollNodeRecursive(root, action)
    }

    fun scrollScreen(direction: String) = scroll(direction)

    // ═══════════════════════════════════════════════════════════════════
    // ── GLOBAL ACTIONS ──────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun performBack()         = performGlobalAction(GLOBAL_ACTION_BACK)
    fun pressHome()           = performGlobalAction(GLOBAL_ACTION_HOME)
    fun pressRecents()        = performGlobalAction(GLOBAL_ACTION_RECENTS)
    fun openNotifications()   = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
    fun openQuickSettings()   = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
    fun lockScreen()          = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
    fun takeScreenshot()      = if (android.os.Build.VERSION.SDK_INT >= 28)
                                    performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT) else false
    fun toggleSplitScreen()   = if (android.os.Build.VERSION.SDK_INT >= 24)
                                    performGlobalAction(GLOBAL_ACTION_TOGGLE_SPLIT_SCREEN) else false
    fun powerDialog()         = if (android.os.Build.VERSION.SDK_INT >= 21)
                                    performGlobalAction(GLOBAL_ACTION_POWER_DIALOG) else false

    // ═══════════════════════════════════════════════════════════════════
    // ── GESTURES ────────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun tapAt(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 100)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun longTapAt(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 800)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun doubleTapAt(x: Float, y: Float) {
        tapAt(x, y)
        handler.postDelayed({ tapAt(x, y) }, 150)
    }

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300) {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    // ── СИСТЕМНЫЕ КНОПКИ ────────────────────────────────────────────────

    /** Назад (выйти из приложения / закрыть экран) */
    fun pressBack() = performGlobalAction(GLOBAL_ACTION_BACK)

    /** Домой */
    fun goHome() = performGlobalAction(GLOBAL_ACTION_HOME)

    /** Недавние приложения */
    fun openRecents() = performGlobalAction(GLOBAL_ACTION_RECENTS)

    /** Шторка уведомлений */
    fun openNotifications() = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    /** Закрыть текущее приложение через Recents — свайп карточки */
    fun closeCurrentApp() {
        performGlobalAction(GLOBAL_ACTION_RECENTS)
        handler.postDelayed({
            // Свайп карточки вверх чтобы закрыть
            val dm = resources.displayMetrics
            val cx = dm.widthPixels / 2f
            val cy = dm.heightPixels / 2f
            swipe(cx, cy, cx, 0f, 400)
        }, 600)
    }

    /** Удалить/удалить приложение — открываем настройки приложения через Intent */
    fun openAppSettings(packageName: String): Boolean {
        return try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.fromParts("package", packageName, null)
            ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
            applicationContext.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "openAppSettings: $e")
            false
        }
    }

    /** Удалить приложение — открываем стандартный диалог удаления */
    fun uninstallApp(packageName: String): Boolean {
        return try {
            val intent = android.content.Intent(
                android.content.Intent.ACTION_DELETE,
                android.net.Uri.fromParts("package", packageName, null)
            ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
            applicationContext.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "uninstallApp: $e")
            false
        }
    }

    fun pinchZoom(cx: Float, cy: Float, scale: Float) {
        val delta = 200f * scale
        // два пальца расходятся
        val path1 = Path().apply { moveTo(cx - delta/2, cy); lineTo(cx - delta, cy) }
        val path2 = Path().apply { moveTo(cx + delta/2, cy); lineTo(cx + delta, cy) }
        val s1 = GestureDescription.StrokeDescription(path1, 0, 400)
        val s2 = GestureDescription.StrokeDescription(path2, 0, 400)
        dispatchGesture(GestureDescription.Builder().addStroke(s1).addStroke(s2).build(), null, null)
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── QUERYABLE ELEMENTS ──────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    fun getClickableElements(): List<Map<String, Any>> {
        val root   = rootInActiveWindow ?: return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        collectClickableNodes(root, result)
        return result
    }

    fun getFocusedElement(): Map<String, Any?>? {
        val root = rootInActiveWindow ?: return null
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        val rect = Rect(); node.getBoundsInScreen(rect)
        return mapOf(
            "text"  to (node.text?.toString() ?: ""),
            "hint"  to (node.hintText?.toString() ?: ""),
            "id"    to (node.viewIdResourceName ?: ""),
            "class" to (node.className?.toString() ?: ""),
            "x"     to rect.centerX(),
            "y"     to rect.centerY(),
        )
    }

    fun getAllWindows(): List<Map<String, Any>> {
        return windows?.map { w ->
            val wRoot = w.root
            val text  = StringBuilder()
            if (wRoot != null) collectTextFromNode(wRoot, text, 0)
            mapOf(
                "type"  to w.type,
                "layer" to w.layer,
                "text"  to text.toString().take(300),
            )
        } ?: emptyList()
    }

    fun getScreenSize(): Map<String, Int> {
        val wm = getSystemService(android.content.Context.WINDOW_SERVICE) as android.view.WindowManager
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            mapOf("width" to bounds.width(), "height" to bounds.height())
        } else {
            @Suppress("DEPRECATION")
            val display = wm.defaultDisplay
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            display.getRealMetrics(metrics)
            mapOf("width" to metrics.widthPixels, "height" to metrics.heightPixels)
        }
    }

    fun findNodesByClass(className: String): List<Map<String, Any>> {
        val root   = rootInActiveWindow ?: return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        collectNodesByClass(root, className, result)
        return result
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── PRIVATE HELPERS ─────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════

    private fun findSearchButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val ids = listOf("search", "menu_search", "action_search", "search_button")
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        return findNodeByDescription(root, "Search") ?: findNodeByDescription(root, "Поиск")
    }

    private fun findSearchInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val ids = listOf("search_src_text", "search_query", "input_search", "et_search")
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        return findEditTextByHint(root, "поиск") ?: findEditTextByHint(root, "search")
    }

    private fun findMessageInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val hints = listOf("message", "сообщение", "Сообщение", "Message", "Text message")
        for (h in hints) {
            val n = findEditTextByHint(root, h)
            if (n != null) return n
        }
        return findBottomEditText(root)
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val descs = listOf("Send", "Отправить", "send", "send_button")
        for (d in descs) {
            val n = findNodeByDescription(root, d)
            if (n != null) return n
        }
        val ids = listOf("send", "btn_send", "action_send", "iv_send")
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        return null
    }

    private fun findNodeByExactText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        if (root.text?.toString() == text) return root
        for (i in 0 until root.childCount) {
            val n = findNodeByExactText(root.getChild(i) ?: continue, text)
            if (n != null) return n
        }
        return null
    }

    private fun findNodeContainingText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val lo = text.lowercase()
        if (root.text?.toString()?.lowercase()?.contains(lo) == true) return root
        if (root.contentDescription?.toString()?.lowercase()?.contains(lo) == true) return root
        for (i in 0 until root.childCount) {
            val n = findNodeContainingText(root.getChild(i) ?: continue, text)
            if (n != null) return n
        }
        return null
    }

    private fun findNodeByDescription(root: AccessibilityNodeInfo, desc: String): AccessibilityNodeInfo? {
        if (root.contentDescription?.toString()?.contains(desc, ignoreCase = true) == true) return root
        for (i in 0 until root.childCount) {
            val n = findNodeByDescription(root.getChild(i) ?: continue, desc)
            if (n != null) return n
        }
        return null
    }

    private fun findEditTextByHint(root: AccessibilityNodeInfo, hint: String): AccessibilityNodeInfo? {
        if (root.className?.toString()?.contains("EditText") == true) {
            val h = root.hintText?.toString()?.lowercase() ?: ""
            val t = root.text?.toString()?.lowercase() ?: ""
            if (h.contains(hint.lowercase()) || t.contains(hint.lowercase())) return root
        }
        for (i in 0 until root.childCount) {
            val n = findEditTextByHint(root.getChild(i) ?: continue, hint)
            if (n != null) return n
        }
        return null
    }

    private fun findBottomEditText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val editTexts = mutableListOf<AccessibilityNodeInfo>()
        collectEditTexts(root, editTexts)
        if (editTexts.isEmpty()) return null
        return editTexts.maxByOrNull {
            val rect = Rect(); it.getBoundsInScreen(rect); rect.top
        }
    }

    private fun collectNodesByClass(node: AccessibilityNodeInfo?, className: String, result: MutableList<Map<String, Any>>) {
        if (node == null) return
        if (node.className?.toString()?.contains(className, ignoreCase = true) == true) {
            val rect = Rect(); node.getBoundsInScreen(rect)
            result.add(mapOf(
                "text"  to (node.text?.toString() ?: ""),
                "class" to (node.className?.toString() ?: ""),
                "id"    to (node.viewIdResourceName ?: ""),
                "x"     to rect.centerX(),
                "y"     to rect.centerY(),
            ))
        }
        for (i in 0 until node.childCount) collectNodesByClass(node.getChild(i), className, result)
    }

    private fun collectEditTexts(node: AccessibilityNodeInfo?, list: MutableList<AccessibilityNodeInfo>) {
        if (node == null) return
        if (node.className?.toString()?.contains("EditText") == true) list.add(node)
        for (i in 0 until node.childCount) collectEditTexts(node.getChild(i), list)
    }

    private fun clickNodeOrParent(node: AccessibilityNodeInfo): Boolean {
        if (node.isClickable) { node.performAction(AccessibilityNodeInfo.ACTION_CLICK); return true }
        var parent = node.parent
        repeat(5) {
            if (parent?.isClickable == true) { parent!!.performAction(AccessibilityNodeInfo.ACTION_CLICK); return true }
            parent = parent?.parent
        }
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        return true
    }

    private fun scrollNodeRecursive(node: AccessibilityNodeInfo?, action: Int) {
        if (node == null) return
        if (node.isScrollable) { node.performAction(action); return }
        for (i in 0 until node.childCount) scrollNodeRecursive(node.getChild(i), action)
    }

    private fun collectTextFromNode(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 25) return
        val text = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        if (!text.isNullOrEmpty() && text.length > 1) sb.appendLine(text)
        else if (!desc.isNullOrEmpty() && desc.length > 1) sb.appendLine(desc)
        for (i in 0 until node.childCount) collectTextFromNode(node.getChild(i), sb, depth + 1)
    }

    private fun collectClickableNodes(node: AccessibilityNodeInfo?, result: MutableList<Map<String, Any>>) {
        if (node == null) return
        if (node.isClickable) {
            val rect = Rect(); node.getBoundsInScreen(rect)
            val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
            if (text.isNotEmpty()) {
                result.add(mapOf(
                    "text"  to text,
                    "id"    to (node.viewIdResourceName ?: ""),
                    "x"     to rect.centerX(),
                    "y"     to rect.centerY(),
                    "class" to (node.className?.toString() ?: "")
                ))
            }
        }
        for (i in 0 until node.childCount) collectClickableNodes(node.getChild(i), result)
    }

    private fun notifyFlutter(status: String, message: String) {
        handler.post {
            flutterChannel?.invokeMethod("onMessageSent", mapOf("status" to status, "message" to message))
        }
    }

    private fun resetSend(status: String?, msg: String?) {
        pendingApp = null; pendingContact = null; pendingMessage = null; sendStep = "idle"
    }
}
