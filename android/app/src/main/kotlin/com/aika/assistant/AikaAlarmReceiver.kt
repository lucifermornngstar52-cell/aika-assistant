package com.aika.assistant

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class AikaAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getStringExtra("alarm_id") ?: return
        val label   = intent.getStringExtra("alarm_label") ?: ""

        // Show heads-up notification (full screen if possible)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "aika_alarm_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                channelId,
                "Будильники Айки",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Будильники от ассистента Айка"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
            }
            nm.createNotificationChannel(ch)
        }

        // Launch app intent
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pi = PendingIntent.getActivity(
            context, alarmId.hashCode(), launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = "⏰ Будильник Айки"
        val body  = if (label.isNotEmpty()) "Подъём! 📌 $label" else "Подъём! Пора просыпаться 🌸"

        val notif = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pi, true)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setVibrate(longArrayOf(0, 500, 200, 500))
            .build()

        nm.notify(alarmId.hashCode(), notif)
    }

    companion object {
        fun schedule(context: Context, alarmId: String, triggerMillis: Long, label: String) {
            val intent = Intent(context, AikaAlarmReceiver::class.java).apply {
                action = "com.aika.ALARM_FIRED"
                putExtra("alarm_id", alarmId)
                putExtra("alarm_label", label)
            }
            val pi = PendingIntent.getBroadcast(
                context, alarmId.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMillis, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerMillis, pi)
            }
        }

        fun cancel(context: Context, alarmId: String) {
            val intent = Intent(context, AikaAlarmReceiver::class.java).apply {
                action = "com.aika.ALARM_FIRED"
            }
            val pi = PendingIntent.getBroadcast(
                context, alarmId.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pi)
        }
    }
}
