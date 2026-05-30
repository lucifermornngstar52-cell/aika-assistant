package com.aika.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel

class AikaAccessibilityService : AccessibilityService() {

    companion object {
        var instance: AikaAccessibilityService? = null
        var currentPackage: String = ""
        var currentAppLabel: String = ""
        const val ACTION_SCREEN_EVENT = "com.aika.assistant.SCREEN_EVENT"
        const val ACTION_SEND_MESSAGE = "com.aika.assistant.SEND_MESSAGE"
        var flutterChannel: MethodChannel? = null
    }

    // ── Send message state ──────────────────────────────────
    private var pendingApp: String? = null
    private var pendingContact: String? = null
    private var pendingMessage: String? = null
    private var sendStep: String = "idle"
    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        instance = this
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 100
        }
        serviceInfo = info
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    // ═══════════════════════════════════════════════════════════
    // SEND MESSAGE
    // ═══════════════════════════════════════════════════════════

    fun startSendMessage(app: String, contact: String, message: String) {
        pendingApp = app
        pendingContact = contact
        pendingMessage = message
        sendStep = "open_app"

        val pkg = when {
            app.contains("whatsapp", true) -> "com.whatsapp"
            app.contains("telegram", true) -> "org.telegram.messenger"
            app.contains("instagram", true) -> "com.instagram.android"
            app.contains("вконтакте", true) || app.contains("vk", true) -> "com.vkontakte.android"
            app.contains("viber", true) -> "com.viber.voip"
            else -> app
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
        } else {
            notifyFlutter("error", "Приложение не найдено: $app")
            resetSend(null, null)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg != "com.aika.assistant") {
            currentPackage = pkg
            currentAppLabel = try {
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(pkg, 0)
                ).toString()
            } catch (e: Exception) { pkg }

            val broadcast = Intent(ACTION_SCREEN_EVENT).apply {
                putExtra("package", pkg)
                putExtra("label", currentAppLabel)
            }
            sendBroadcast(broadcast)
        }

        if (sendStep != "idle") {
            processStep(event)
        }
    }

    private fun processStep(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        val expectedPkg = when {
            pendingApp?.contains("whatsapp", true) == true -> "com.whatsapp"
            pendingApp?.contains("telegram", true) == true -> "org.telegram.messenger"
            pendingApp?.contains("instagram", true) == true -> "com.instagram.android"
            pendingApp?.contains("вконтакте", true) == true -> "com.vkontakte.android"
            pendingApp?.contains("viber", true) == true -> "com.viber.voip"
            else -> pendingApp ?: ""
        }

        if (!pkg.contains(expectedPkg) && !expectedPkg.contains(pkg)) return

        when (sendStep) {
            "open_app" -> {
                sendStep = "find_contact"
                handler.postDelayed({ findAndClickContact() }, 1500)
            }
            "find_contact" -> {
                handler.postDelayed({ findAndClickContact() }, 500)
            }
            "wait_chat" -> {
                handler.postDelayed({ waitForChatAndType() }, 500)
            }
        }
    }

    private fun findAndClickContact() {
        val root = rootInActiveWindow ?: run {
            notifyFlutter("error", "Нет доступа к экрану")
            resetSend(null, null)
            return
        }

        // Пробуем нажать на иконку поиска
        val searchBtn = findSearchButton(root)
        if (searchBtn != null) {
            searchBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeContactName() }, 800)
            return
        }

        // Пробуем найти поле поиска
        val searchBar = findSearchInput(root)
        if (searchBar != null) {
            searchBar.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeContactName() }, 500)
            return
        }

        // Ищем контакт прямо в списке
        val contact = pendingContact ?: return
        val node = findNodeContainingText(root, contact)
        if (node != null) {
            clickNodeOrParent(node)
            sendStep = "wait_chat"
            handler.postDelayed({ waitForChatAndType() }, 1500)
        } else {
            notifyFlutter("error", "Контакт не найден: $contact")
            resetSend(null, null)
        }
    }

    private fun typeContactName() {
        val root = rootInActiveWindow ?: return
        val contact = pendingContact ?: return

        val searchInput = findSearchInput(root) ?: run {
            notifyFlutter("error", "Поле поиска не найдено")
            resetSend(null, null)
            return
        }

        searchInput.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, contact)
        }
        searchInput.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)

        sendStep = "click_contact"
        handler.postDelayed({ clickContactFromSearch() }, 1500)
    }

    private fun clickContactFromSearch() {
        val root = rootInActiveWindow ?: return
        val contact = pendingContact ?: return

        val node = findNodeContainingText(root, contact)
        if (node != null) {
            clickNodeOrParent(node)
            sendStep = "wait_chat"
            handler.postDelayed({ waitForChatAndType() }, 2000)
        } else {
            notifyFlutter("error", "Контакт не найден в результатах: $contact")
            resetSend(null, null)
        }
    }

    private fun waitForChatAndType() {
        val root = rootInActiveWindow ?: run {
            notifyFlutter("error", "Нет доступа к чату")
            resetSend(null, null)
            return
        }

        val inputField = findMessageInput(root)
        if (inputField != null) {
            inputField.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeMessageInField(inputField) }, 500)
        } else {
            handler.postDelayed({ waitForChatAndType() }, 1000)
        }
    }

    private fun typeMessageInField(node: AccessibilityNodeInfo) {
        val fresh = findMessageInput(rootInActiveWindow ?: return) ?: node
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pendingMessage)
        }
        fresh.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        handler.postDelayed({ clickSendButton() }, 600)
    }

    private fun clickSendButton() {
        val root = rootInActiveWindow ?: return
        val sendBtn = findSendButton(root)
        if (sendBtn != null) {
            sendBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            notifyFlutter("success", "Сообщение отправлено")
        } else {
            // Fallback: Enter key
            val inputField = findMessageInput(root)
            inputField?.performAction(AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY)
            notifyFlutter("success", "Сообщение отправлено (Enter)")
        }
        resetSend(null, null)
    }

    // ═══════════════════════════════════════════════════════════
    // SCREEN ACTIONS (вызываются из Flutter)
    // ═══════════════════════════════════════════════════════════

    fun getAllScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        collectTextFromNode(root, sb, 0)
        return sb.toString()
    }

    /** Клик по элементу с текстом */
    fun clickByText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeContainingText(root, targetText) ?: return false
        return clickNodeOrParent(node)
    }

    /** Клик по элементу с точным текстом */
    fun clickByExactText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeByExactText(root, targetText) ?: return false
        return clickNodeOrParent(node)
    }

    /** Клик по описанию (content-description) */
    fun clickByDescription(desc: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findNodeByDescription(root, desc) ?: return false
        return clickNodeOrParent(node)
    }

    /** Клик по resource-id */
    fun clickById(resourceId: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByViewId(resourceId)
        if (nodes.isNullOrEmpty()) return false
        return clickNodeOrParent(nodes[0])
    }

    /** Ввод текста в поле с текстом/id */
    fun typeInField(hintOrId: String, text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        // Ищем по id
        var node = root.findAccessibilityNodeInfosByViewId(hintOrId)?.firstOrNull()
        // Ищем по тексту/hint
        if (node == null) node = findEditTextByHint(root, hintOrId)
        if (node == null) node = findNodeContainingText(root, hintOrId)
        if (node == null) return false

        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        return true
    }

    /** Скролл */
    fun scroll(direction: String) {
        val action = if (direction == "up" || direction == "left")
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        else
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        scrollNodeRecursive(rootInActiveWindow, action)
    }

    /** Назад */
    fun performBack() = performGlobalAction(GLOBAL_ACTION_BACK)

    /** Домой */
    fun pressHome() = performGlobalAction(GLOBAL_ACTION_HOME)

    /** Недавние */
    fun pressRecents() = performGlobalAction(GLOBAL_ACTION_RECENTS)

    /** Шторка уведомлений */
    fun openNotifications() = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    /** Быстрые настройки */
    fun openQuickSettings() = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

    /** Блокировка экрана */
    fun lockScreen() = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)

    /** Тап по координатам */
    fun tapAt(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    /** Долгий тап */
    fun longTapAt(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 800)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    /** Свайп */
    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300) {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    /** Получить список всех кликабельных элементов с текстом */
    fun getClickableElements(): List<Map<String, Any>> {
        val root = rootInActiveWindow ?: return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        collectClickableNodes(root, result)
        return result
    }

    /** Получить элемент в фокусе */
    fun getFocusedElement(): Map<String, Any?>? {
        val root = rootInActiveWindow ?: return null
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return mapOf(
            "text" to (node.text?.toString() ?: ""),
            "hint" to (node.hintText?.toString() ?: ""),
            "class" to (node.className?.toString() ?: ""),
            "id" to (node.viewIdResourceName ?: ""),
            "x" to rect.centerX(),
            "y" to rect.centerY()
        )
    }

    // ═══════════════════════════════════════════════════════════
    // NODE FINDERS
    // ═══════════════════════════════════════════════════════════

    private fun findSearchButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val descs = listOf("search", "поиск", "Search")
        for (desc in descs) {
            val nodes = root.findAccessibilityNodeInfosByText(desc)
            if (!nodes.isNullOrEmpty()) {
                val btn = nodes.firstOrNull { it.isClickable } ?: nodes.firstOrNull()
                if (btn != null) return btn
            }
        }
        return null
    }

    private fun findSearchInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val ids = listOf(
            "com.whatsapp:id/search_input",
            "org.telegram.messenger:id/search_field",
            "com.instagram.android:id/action_bar_search_edit_text",
            "com.vkontakte.android:id/search_edit_text"
        )
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        // Fallback — ищем EditText
        return findEditTextByHint(root, "поиск")
            ?: findEditTextByHint(root, "search")
    }

    private fun findMessageInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val strictIds = listOf(
            "com.whatsapp:id/entry",
            "org.telegram.messenger:id/chat_message_text",
            "org.telegram.messenger:id/editTextMessage",
            "com.instagram.android:id/direct_text_message_edit_text",
            "com.vkontakte.android:id/message_text",
            "com.viber.voip:id/chat_edittext"
        )
        for (id in strictIds) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        // Fallback — EditText внизу экрана
        return findBottomEditText(root)
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val ids = listOf(
            "com.whatsapp:id/send",
            "org.telegram.messenger:id/chat_message_enter",
            "com.instagram.android:id/send_button",
            "com.vkontakte.android:id/send_button"
        )
        for (id in ids) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        val descs = listOf("Send", "Отправить", "send")
        for (desc in descs) {
            val nodes = root.findAccessibilityNodeInfosByText(desc)
            if (!nodes.isNullOrEmpty()) return nodes[0]
        }
        return null
    }

    private fun findNodeByExactText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        if (root.text?.toString()?.equals(text, ignoreCase = true) == true) return root
        for (i in 0 until root.childCount) {
            val found = findNodeByExactText(root.getChild(i) ?: continue, text)
            if (found != null) return found
        }
        return null
    }

    private fun findNodeContainingText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val lower = text.lowercase()
        if (root.text?.toString()?.lowercase()?.contains(lower) == true) return root
        if (root.contentDescription?.toString()?.lowercase()?.contains(lower) == true) return root
        for (i in 0 until root.childCount) {
            val found = findNodeContainingText(root.getChild(i) ?: continue, text)
            if (found != null) return found
        }
        return null
    }

    private fun findNodeByDescription(root: AccessibilityNodeInfo, desc: String): AccessibilityNodeInfo? {
        val lower = desc.lowercase()
        if (root.contentDescription?.toString()?.lowercase()?.contains(lower) == true) return root
        for (i in 0 until root.childCount) {
            val found = findNodeByDescription(root.getChild(i) ?: continue, desc)
            if (found != null) return found
        }
        return null
    }

    private fun findEditTextByHint(root: AccessibilityNodeInfo, hint: String): AccessibilityNodeInfo? {
        val lower = hint.lowercase()
        val cls = root.className?.toString() ?: ""
        if (cls.contains("EditText")) {
            if (root.hintText?.toString()?.lowercase()?.contains(lower) == true) return root
            if (root.text?.toString()?.lowercase()?.contains(lower) == true) return root
        }
        for (i in 0 until root.childCount) {
            val found = findEditTextByHint(root.getChild(i) ?: continue, hint)
            if (found != null) return found
        }
        return null
    }

    private fun findBottomEditText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val editTexts = mutableListOf<AccessibilityNodeInfo>()
        collectEditTexts(root, editTexts)
        if (editTexts.isEmpty()) return null
        // Берём самый нижний EditText (вероятно поле ввода сообщения)
        return editTexts.maxByOrNull {
            val rect = Rect(); it.getBoundsInScreen(rect); rect.top
        }
    }

    private fun collectEditTexts(node: AccessibilityNodeInfo?, list: MutableList<AccessibilityNodeInfo>) {
        if (node == null) return
        if (node.className?.toString()?.contains("EditText") == true) list.add(node)
        for (i in 0 until node.childCount) collectEditTexts(node.getChild(i), list)
    }

    private fun clickNodeOrParent(node: AccessibilityNodeInfo): Boolean {
        if (node.isClickable) {
            node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            return true
        }
        var parent = node.parent
        repeat(5) {
            if (parent?.isClickable == true) {
                parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return true
            }
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
        if (node == null || depth > 20) return
        val text = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        if (!text.isNullOrEmpty()) sb.appendLine(text)
        else if (!desc.isNullOrEmpty()) sb.appendLine(desc)
        for (i in 0 until node.childCount) collectTextFromNode(node.getChild(i), sb, depth + 1)
    }

    private fun collectClickableNodes(node: AccessibilityNodeInfo?, result: MutableList<Map<String, Any>>) {
        if (node == null) return
        if (node.isClickable) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
            if (text.isNotEmpty()) {
                result.add(mapOf(
                    "text" to text,
                    "id" to (node.viewIdResourceName ?: ""),
                    "x" to rect.centerX(),
                    "y" to rect.centerY(),
                    "class" to (node.className?.toString() ?: "")
                ))
            }
        }
        for (i in 0 until node.childCount) collectClickableNodes(node.getChild(i), result)
    }

    // ═══════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════

    private fun notifyFlutter(status: String, message: String) {
        handler.post {
            flutterChannel?.invokeMethod("onMessageSent", mapOf("status" to status, "message" to message))
        }
    }

    private fun resetSend(status: String?, msg: String?) {
        pendingApp = null
        pendingContact = null
        pendingMessage = null
        sendStep = "idle"
    }

    private fun getAppLabel(packageName: String): String = try {
        packageManager.getApplicationLabel(
            packageManager.getApplicationInfo(packageName, 0)
        ).toString()
    } catch (e: Exception) { packageName }

    override fun onInterrupt() {}
}

    // ── Дополнительные методы которые ожидает MainActivity ──────

    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
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

    fun getScreenSize(): Map<String, Int> {
        val wm = getSystemService(WINDOW_SERVICE) as android.view.WindowManager
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
