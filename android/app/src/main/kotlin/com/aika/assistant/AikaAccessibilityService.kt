package com.aika.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AikaAccessibilityService : AccessibilityService() {

    companion object {
        var currentPackage: String = ""
        var currentAppLabel: String = ""
        const val ACTION_SCREEN_EVENT = "com.aika.assistant.SCREEN_EVENT"
        const val ACTION_SEND_MESSAGE = "com.aika.assistant.SEND_MESSAGE"
        const val EXTRA_PACKAGE    = "package"
        const val EXTRA_LABEL      = "label"
        const val EXTRA_EVENT_TYPE = "event_type"
        const val EXTRA_APP        = "app"        // "whatsapp" | "telegram"
        const val EXTRA_CONTACT    = "contact"
        const val EXTRA_MESSAGE    = "message"

        // Singleton ссылка на сервис для вызова из broadcast
        var instance: AikaAccessibilityService? = null
    }

    private val handler = Handler(Looper.getMainLooper())

    // Состояние машины отправки
    private var pendingApp: String = ""
    private var pendingContact: String = ""
    private var pendingMessage: String = ""
    private enum class SendStep { IDLE, WAITING_APP_OPEN, SEARCHING_CONTACT, WAITING_CHAT_OPEN, TYPING, DONE }
    private var sendStep = SendStep.IDLE
    private var stepRetry = 0

    override fun onServiceConnected() {
        instance = this
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                         AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 200
        }
        serviceInfo = info
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    // ── Запуск отправки ─────────────────────────────────────────────────────
    fun startSendMessage(app: String, contact: String, message: String) {
        pendingApp = app
        pendingContact = contact
        pendingMessage = message
        sendStep = SendStep.WAITING_APP_OPEN
        stepRetry = 0

        val pkg = if (app == "whatsapp") "com.whatsapp" else "org.telegram.messenger"
        val intent = packageManager.getLaunchIntentForPackage(pkg)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        if (intent != null) {
            startActivity(intent)
        } else {
            sendStep = SendStep.IDLE
            notifyFlutter("error", "Приложение не установлено")
        }
    }

    // ── Accessibility events ────────────────────────────────────────────────
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Трекинг текущего приложения
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val pkg = event.packageName?.toString() ?: ""
            if (pkg.isNotEmpty() && pkg != packageName && pkg != "android" && pkg != currentPackage) {
                currentPackage = pkg
                currentAppLabel = getAppLabel(pkg)
                val broadcastIntent = Intent(ACTION_SCREEN_EVENT).apply {
                    setPackage(packageName)
                    putExtra(EXTRA_PACKAGE, pkg)
                    putExtra(EXTRA_LABEL, currentAppLabel)
                    putExtra(EXTRA_EVENT_TYPE, "app_changed")
                }
                sendBroadcast(broadcastIntent)
            }
        }

        // Машина состояний отправки
        if (sendStep != SendStep.IDLE) {
            handler.postDelayed({ processStep(event) }, 1000)
        }
    }

    private fun processStep(event: AccessibilityEvent) {
        val targetPkg = if (pendingApp == "whatsapp") "com.whatsapp" else "org.telegram.messenger"
        val evtPkg = event.packageName?.toString() ?: ""

        when (sendStep) {
            SendStep.WAITING_APP_OPEN -> {
                if (evtPkg == targetPkg) {
                    sendStep = SendStep.SEARCHING_CONTACT
                    stepRetry = 0
                    handler.postDelayed({ findAndClickContact() }, 2000)
                } else {
                    stepRetry++
                    if (stepRetry > 10) { resetSend("error", "Не удалось открыть $pendingApp"); return }
                }
            }
            SendStep.SEARCHING_CONTACT,
            SendStep.WAITING_CHAT_OPEN,
            SendStep.TYPING -> { /* handled by findAndClickContact / typeAndSend */ }
            else -> {}
        }
    }

    // ── Поиск контакта ──────────────────────────────────────────────────────
    private fun findAndClickContact() {
        if (sendStep == SendStep.IDLE) return
        stepRetry++
        if (stepRetry > 20) { resetSend("error", "Контакт не найден: $pendingContact"); return }

        val root = rootInActiveWindow ?: run {
            handler.postDelayed({ findAndClickContact() }, 1000); return
        }

        // 1. Контакт уже виден в списке — кликаем (с поиском кликабельного родителя)
        val contactNode = root.findAccessibilityNodeInfosByText(pendingContact)
            ?.firstOrNull()
            ?: findNodeContainingText(root, pendingContact)
        if (contactNode != null) {
            val clickable = if (contactNode.isClickable) contactNode
                else generateSequence(contactNode.parent) { it.parent }.take(5).firstOrNull { it.isClickable }
            if (clickable != null) {
                clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                sendStep = SendStep.WAITING_CHAT_OPEN
                stepRetry = 0
                handler.postDelayed({ waitForChatAndType() }, 2500)
                return
            }
        }

        // 2. Ищем иконку/кнопку поиска (лупа) и нажимаем её
        val searchBtn = findNodeByCondition(root) { node ->
            val desc = (node.contentDescription ?: "").toString().lowercase()
            val rid  = (node.viewIdResourceName ?: "").lowercase()
            node.isClickable && !node.className.toString().contains("EditText") &&
            (desc.contains("search") || desc.contains("поиск") ||
             rid.contains("search_btn") || rid.contains("menu_search") || rid.contains("action_search"))
        }
        if (searchBtn != null) {
            searchBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeContactName(pendingContact) }, 1000)
            return
        }

        // 3. Поле поиска уже открыто — вводим имя
        val searchBar = findSearchBar(root)
        if (searchBar != null) {
            searchBar.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeContactName(pendingContact) }, 800)
            return
        }

        handler.postDelayed({ findAndClickContact() }, 1000)
    }
    private fun typeContactName(name: String) {
        val root = rootInActiveWindow ?: return
        // Находим активное поле ввода (поиск)
        val searchInput = findEditText(root) ?: findSearchBar(root) ?: return
        searchInput.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply { putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, name) }
        searchInput.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        stepRetry = 0
        handler.postDelayed({ clickContactFromSearch() }, 1200)
    }

    private fun clickContactFromSearch() {
        if (sendStep == SendStep.IDLE) return
        stepRetry++
        if (stepRetry > 10) { resetSend("error", "Контакт не найден в поиске"); return }

        val root = rootInActiveWindow ?: run {
            handler.postDelayed({ clickContactFromSearch() }, 800); return
        }

        // Ищем первый результат с именем контакта (частичное совпадение)
        val node = findNodeContainingText(root, pendingContact)
        if (node != null) {
            node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            sendStep = SendStep.WAITING_CHAT_OPEN
            stepRetry = 0
            handler.postDelayed({ waitForChatAndType() }, 2500)
        } else {
            handler.postDelayed({ clickContactFromSearch() }, 800)
        }
    }

    // ── Ожидание открытия чата и ввод ──────────────────────────────────────
    private fun waitForChatAndType() {
        if (sendStep == SendStep.IDLE) return
        stepRetry++
        if (stepRetry > 25) { resetSend("error", "Чат не открылся"); return }

        val root = rootInActiveWindow ?: run {
            handler.postDelayed({ waitForChatAndType() }, 1000); return
        }

        // Ищем поле ввода сообщений СТРОГО — по resource-id мессенджера
        // НЕ проверяем отсутствие searchBar — он есть и в чате (в тулбаре)
        val inputField = findMessageInputStrict(root)

        if (inputField != null && inputField.isEditable) {
            // Дополнительная защита: убеждаемся что это НЕ строка поиска контакта
            // Если поле содержит имя контакта — мы ещё в поиске, ждём
            val currentText = (inputField.text ?: "").toString()
            val isSearchField = currentText.lowercase().contains(pendingContact.lowercase().take(3)) &&
                                currentText.length < 30
            if (isSearchField) {
                handler.postDelayed({ waitForChatAndType() }, 1000)
                return
            }
            sendStep = SendStep.TYPING
            inputField.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeMessageFresh() }, 800)
        } else {
            handler.postDelayed({ waitForChatAndType() }, 1000)
        }
    }

    // Вводим сообщение — берём свежую ноду чтобы не держать устаревшую
    private fun typeMessageFresh() {
        val root = rootInActiveWindow ?: return
        val inputField = findMessageInputStrict(root) ?: return
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pendingMessage)
        }
        inputField.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        handler.postDelayed({ clickSendButton() }, 700)
    }

    private fun typeMessage(node: AccessibilityNodeInfo) {
        // Prefer fresh strict lookup over cached node
        val root = rootInActiveWindow
        val target = if (root != null) findMessageInputStrict(root) ?: node else node
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pendingMessage)
        }
        target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        handler.postDelayed({ clickSendButton() }, 700)
    }

    private fun clickSendButton() {
        val root = rootInActiveWindow ?: return
        // Ищем кнопку отправки по content-description
        val sendBtn = findSendButton(root)
        if (sendBtn != null) {
            sendBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            notifyFlutter("success", "Сообщение отправлено $pendingContact через $pendingApp")
            resetSend(null, null)
        } else {
            // Fallback: нажимаем Enter
            val inputField = findMessageInput(root)
            inputField?.performAction(AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY)
            notifyFlutter("success", "Сообщение отправлено $pendingContact")
            resetSend(null, null)
        }
    }

    // ── Поиск нод ───────────────────────────────────────────────────────────
    private fun findSearchBar(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val descKeywords = listOf("search", "поиск", "найти", "search_src_text")
        return findNodeByCondition(root) { node ->
            val desc = (node.contentDescription ?: "").toString().lowercase()
            val rid  = (node.viewIdResourceName ?: "").lowercase()
            val hint = (node.hintText ?: "").toString().lowercase()
            descKeywords.any { desc.contains(it) || rid.contains(it) || hint.contains(it) }
        }
    }

    private fun findEditText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        return findNodeByCondition(root) { node ->
            node.className?.toString()?.contains("EditText") == true && node.isEnabled
        }
    }

    private fun findMessageInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // WhatsApp: entry / message_et; Telegram: chat_message_text
        val ridKeywords = listOf("entry", "message_et", "chat_message", "input", "compose", "text_input")
        return findNodeByCondition(root) { node ->
            val rid = (node.viewIdResourceName ?: "").lowercase()
            val cls = (node.className ?: "").toString()
            cls.contains("EditText") && (ridKeywords.any { rid.contains(it) } || node.isEditable)
        }
    }

    /** Строгий поиск поля ввода сообщения — исключает строки поиска и заголовки */
    private fun findMessageInputStrict(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // Известные resource-id полей сообщения (WhatsApp: entry; Telegram: chat_message_text)
        val msgRids = listOf(
                             // WhatsApp
                             "entry",
                             // Telegram
                             "chat_message_text", "editTextMessage",
                             // Общие
                             "message_et", "chat_input", "compose_text",
                             "text_input", "msg_input", "message_input",
                             "input_text", "compose_box", "message_box")
        // Явные исключения — поисковые поля
        val searchRids = listOf("search", "поиск", "find", "query", "filter")
        val searchDescs = listOf("search", "поиск", "найти")

        // 1) Сначала ищем по известным resource-id
        val byRid = findNodeByCondition(root) { node ->
            val rid = (node.viewIdResourceName ?: "").lowercase()
            val cls = (node.className ?: "").toString()
            cls.contains("EditText") && msgRids.any { rid.contains(it) }
        }
        if (byRid != null) return byRid

        // 2) Fallback: любой editable EditText, не являющийся поиском
        return findNodeByCondition(root) { node ->
            val rid  = (node.viewIdResourceName ?: "").lowercase()
            val cls  = (node.className ?: "").toString()
            val desc = (node.contentDescription ?: "").toString().lowercase()
            val hint = (node.hintText ?: "").toString().lowercase()
            val isEditText = cls.contains("EditText")
            val isSearch   = searchRids.any { rid.contains(it) } ||
                             searchDescs.any { desc.contains(it) || hint.contains(it) }
            isEditText && node.isEditable && !isSearch
        }
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // WhatsApp: send, conversation_send; Telegram: chat_send_button, btn_send
        val descKeys = listOf("send", "отправить", "submit", "send message")
        val ridKeys  = listOf("send", "btn_send", "chat_send", "conversation_send",
                              "action_send", "send_button", "mic_send")
        return findNodeByCondition(root) { node ->
            val desc = (node.contentDescription ?: "").toString().lowercase()
            val rid  = (node.viewIdResourceName ?: "").lowercase()
            (descKeys.any { desc.contains(it) } || ridKeys.any { rid.contains(it) }) && node.isClickable
        }
    }

    private fun findNodeByText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val results = root.findAccessibilityNodeInfosByText(text)
        return results?.firstOrNull()
    }

    private fun findNodeContainingText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val lower = text.lowercase()
        return findNodeByCondition(root) { node ->
            val nodeText = (node.text ?: "").toString().lowercase()
            nodeText.contains(lower) && node.isClickable
        }
    }

    private fun findNodeByCondition(
        root: AccessibilityNodeInfo,
        condition: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (condition(root)) return root
        for (i in 0 until root.childCount) {
            val child = root.getChild(i) ?: continue
            val found = findNodeByCondition(child, condition)
            if (found != null) return found
        }
        return null
    }

    // ── Утилиты ─────────────────────────────────────────────────────────────
    private fun notifyFlutter(status: String, message: String) {
        val intent = Intent("com.aika.assistant.SEND_RESULT").apply {
            setPackage(packageName)
            putExtra("status", status)
            putExtra("message", message)
        }
        sendBroadcast(intent)
    }

    private fun resetSend(status: String?, msg: String?) {
        if (status != null && msg != null) notifyFlutter(status, msg)
        sendStep = SendStep.IDLE
        stepRetry = 0
        pendingApp = ""
        pendingContact = ""
        pendingMessage = ""
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) { packageName }
    }

    override fun onInterrupt() {}
    // ── Screen Reader методы ─────────────────────────────────────────────────

    /** Собирает весь текст с текущего экрана */
    fun getAllScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        collectTextFromNode(root, sb, 0)
        return sb.toString()
    }

    private fun collectTextFromNode(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 10) return
        val text = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        when {
            !text.isNullOrEmpty() -> sb.appendLine(text)
            !desc.isNullOrEmpty() -> sb.appendLine(desc)
        }
        for (i in 0 until node.childCount) {
            collectTextFromNode(node.getChild(i), sb, depth + 1)
        }
    }

    /** Кликает по элементу с нужным текстом */
    fun clickByText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(targetText)
        for (node in nodes ?: emptyList()) {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return true
            }
            val parent = node.parent
            if (parent?.isClickable == true) {
                parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return true
            }
        }
        return false
    }

    /** Прокрутка */
    fun scroll(direction: String) {
        val root = rootInActiveWindow ?: return
        val action = if (direction == "down")
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        else
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        scrollNodeRecursive(root, action)
    }

    private fun scrollNodeRecursive(node: AccessibilityNodeInfo?, action: Int) {
        if (node == null) return
        if (node.isScrollable) { node.performAction(action); return }
        for (i in 0 until node.childCount) scrollNodeRecursive(node.getChild(i), action)
    }

    /** Кнопка Назад */
    fun performBack() = performGlobalAction(GLOBAL_ACTION_BACK)


    // ── Полное управление телефоном ──────────────────────────────────────────

    /** Тап по координатам (Android 7+) */
    fun tapAt(x: Float, y: Float) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return
        val path = android.graphics.Path().apply { moveTo(x, y) }
        val gesture = android.accessibilityservice.GestureDescription.Builder()
            .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        dispatchGesture(gesture, null, null)
    }

    /** Долгий тап по координатам */
    fun longTapAt(x: Float, y: Float) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return
        val path = android.graphics.Path().apply { moveTo(x, y) }
        val gesture = android.accessibilityservice.GestureDescription.Builder()
            .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 1000))
            .build()
        dispatchGesture(gesture, null, null)
    }

    /** Свайп от (x1,y1) до (x2,y2) */
    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return
        val path = android.graphics.Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val gesture = android.accessibilityservice.GestureDescription.Builder()
            .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        dispatchGesture(gesture, null, null)
    }

    /** Системная кнопка Home */
    fun pressHome() = performGlobalAction(GLOBAL_ACTION_HOME)

    /** Недавние приложения */
    fun pressRecents() = performGlobalAction(GLOBAL_ACTION_RECENTS)

    /** Уведомления */
    fun openNotifications() = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    /** Быстрые настройки */
    fun openQuickSettings() = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

    /** Ввод текста в активное поле */
    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val editText = findFocusedOrFirstEditText(root) ?: return false
        val args = android.os.Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return editText.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /** Очистить активное поле */
    fun clearText(): Boolean {
        val root = rootInActiveWindow ?: return false
        val editText = findFocusedOrFirstEditText(root) ?: return false
        val args = android.os.Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
        }
        return editText.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /** Нажать Enter/Done в активном поле */
    fun pressEnter(): Boolean {
        val root = rootInActiveWindow ?: return false
        val edit = findFocusedOrFirstEditText(root) ?: return false
        val args = android.os.Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_MOVEMENT_GRANULARITY_INT, 
                   AccessibilityNodeInfo.MOVEMENT_GRANULARITY_LINE)
        }
        return edit.performAction(AccessibilityNodeInfo.ACTION_NEXT_AT_MOVEMENT_GRANULARITY, args)
    }

    /** Получить размер экрана */
    fun getScreenSize(): Map<String, Int> {
        val dm = resources.displayMetrics
        return mapOf("width" to dm.widthPixels, "height" to dm.heightPixels)
    }

    private fun findFocusedOrFirstEditText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // Сначала ищем фокусированный элемент
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused != null && focused.isEditable) return focused
        // Потом первый редактируемый
        return findNodeByCondition(root) { it.isEditable && it.isFocusable }
    }


}


