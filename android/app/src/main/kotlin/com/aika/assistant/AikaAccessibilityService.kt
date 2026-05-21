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
            handler.postDelayed({ processStep(event) }, 800)
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
                    handler.postDelayed({ findAndClickContact() }, 1200)
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
        if (stepRetry > 15) { resetSend("error", "Контакт не найден: $pendingContact"); return }

        val root = rootInActiveWindow ?: run {
            handler.postDelayed({ findAndClickContact() }, 800); return
        }

        // Ищем поисковую строку и кликаем
        val searchNode = findSearchBar(root)
        if (searchNode != null) {
            searchNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeContactName(pendingContact) }, 600)
            return
        }

        // Ищем контакт в списке напрямую
        val contactNode = findNodeByText(root, pendingContact)
        if (contactNode != null) {
            contactNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            sendStep = SendStep.WAITING_CHAT_OPEN
            stepRetry = 0
            handler.postDelayed({ waitForChatAndType() }, 1500)
            return
        }

        handler.postDelayed({ findAndClickContact() }, 800)
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
            handler.postDelayed({ waitForChatAndType() }, 1500)
        } else {
            handler.postDelayed({ clickContactFromSearch() }, 800)
        }
    }

    // ── Ожидание открытия чата и ввод ──────────────────────────────────────
    private fun waitForChatAndType() {
        if (sendStep == SendStep.IDLE) return
        stepRetry++
        if (stepRetry > 15) { resetSend("error", "Чат не открылся"); return }

        val root = rootInActiveWindow ?: run {
            handler.postDelayed({ waitForChatAndType() }, 800); return
        }

        val inputField = findMessageInput(root)
        if (inputField != null) {
            sendStep = SendStep.TYPING
            inputField.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            handler.postDelayed({ typeMessage(inputField) }, 500)
        } else {
            handler.postDelayed({ waitForChatAndType() }, 800)
        }
    }

    private fun typeMessage(node: AccessibilityNodeInfo) {
        val args = Bundle().apply {
            putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pendingMessage)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        handler.postDelayed({ clickSendButton() }, 600)
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

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val keywords = listOf("send", "отправить", "submit")
        return findNodeByCondition(root) { node ->
            val desc = (node.contentDescription ?: "").toString().lowercase()
            val rid  = (node.viewIdResourceName ?: "").lowercase()
            keywords.any { desc.contains(it) || rid.contains(it) }
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


}

