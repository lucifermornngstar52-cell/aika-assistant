package com.aika.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

class AikaAccessibilityService : AccessibilityService() {

    companion object {
        // Последнее известное приложение на экране
        var currentPackage: String = ""
        var currentAppLabel: String = ""

        // Канал для передачи событий в Flutter
        const val ACTION_SCREEN_EVENT = "com.aika.assistant.SCREEN_EVENT"
        const val EXTRA_PACKAGE = "package"
        const val EXTRA_LABEL = "label"
        const val EXTRA_EVENT_TYPE = "event_type"
    }

    override fun onServiceConnected() {
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                         AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 300
        }
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                val pkg = event.packageName?.toString() ?: return
                // Игнорируем наш оверлей и системные окна
                if (pkg == packageName || pkg == "android") return
                if (pkg == currentPackage) return

                currentPackage = pkg
                currentAppLabel = getAppLabel(pkg)

                // Шлём broadcast чтобы Flutter мог узнать
                val intent = Intent(ACTION_SCREEN_EVENT).apply {
                    setPackage(packageName)
                    putExtra(EXTRA_PACKAGE, pkg)
                    putExtra(EXTRA_LABEL, currentAppLabel)
                    putExtra(EXTRA_EVENT_TYPE, "app_changed")
                }
                sendBroadcast(intent)
            }
            else -> {}
        }
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    override fun onInterrupt() {}
}
