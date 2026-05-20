package com.aika.assistant

import android.app.Notification
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Слушает все входящие уведомления и шлёт их во Flutter через EventChannel.
 * Данные: { "pkg", "title", "text", "time" }
 */
class AikaNotificationListenerService : NotificationListenerService() {

    companion object {
        const val ACTION_NOTIF = "com.aika.assistant.NOTIFICATION"
        const val EXTRA_PKG    = "pkg"
        const val EXTRA_TITLE  = "title"
        const val EXTRA_TEXT   = "text"
        const val EXTRA_TIME   = "time"

        // Пакеты которые нас интересуют (остальные игнорируем чтобы не спамить)
        private val WATCHED_PACKAGES = setOf(
            "org.telegram.messenger",
            "com.whatsapp",
            "com.vkontakte.android",
            "com.instagram.android",
            "com.google.android.gm",
            "com.android.mms",
            "com.samsung.android.messaging",
            "com.viber.voip",
            "ru.ok.android",
        )

        // Кэш последних уведомлений (для брифинга)
        val recentNotifications = ArrayDeque<Map<String, String>>(maxCapacity = 50)
        private const val maxCapacity = 50
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        if (!WATCHED_PACKAGES.contains(pkg)) return

        val extras: Bundle = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
        val text  = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()  ?: ""
        if (title.isBlank() && text.isBlank()) return

        val entry = mapOf(
            "pkg"   to pkg,
            "title" to title,
            "text"  to text,
            "time"  to sbn.postTime.toString(),
        )

        // Добавляем в кэш
        if (recentNotifications.size >= maxCapacity) recentNotifications.removeFirst()
        recentNotifications.addLast(entry)

        // Шлём broadcast во Flutter
        sendBroadcast(Intent(ACTION_NOTIF).apply {
            setPackage(packageName)
            putExtra(EXTRA_PKG,   pkg)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_TEXT,  text)
            putExtra(EXTRA_TIME,  sbn.postTime)
        })
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}
}
