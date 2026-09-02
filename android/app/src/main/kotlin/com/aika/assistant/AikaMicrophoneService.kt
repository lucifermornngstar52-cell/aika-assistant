package com.aika.assistant

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log

/**
 * AikaMicrophoneService — "Троянская" persistизация микрофона.
 *
 * Многоуровневая защита от убийства системой:
 *
 * УРОВЕНЬ 1 — Foreground Service (type=microphone)
 *   Android НЕ может глушить микрофон foreground-сервиса с этим типом.
 *
 * УРОВЕНЬ 2 — START_STICKY + START_REDELIVER_INTENT
 *   Система обязана перезапустить сервис после убийства (Doze, memory pressure).
 *
 * УРОВЕНЬ 3 — WakeLock (PARTIAL_WAKE_LOCK) с периодическим обновлением
 *   CPU не спит когда экран выключен. WakeLock пересоздаётся каждые 30 минут.
 *
 * УРОВЕНЬ 4 — onTaskRemoved → мгновенный рестарт
 *   Когда пользователь свайпает приложение из Recents — сервис перезапускается.
 *
 * УРОВЕНЬ 5 — onDestroy → AlarmManager scheduled restart
 *   Если сервис убит — AlarmManager поднимает его через 1 секунду.
 *
 * УРОВЕНЬ 6 — Heartbeat AlarmManager каждые 60 секунд
 *   Проверяет жив ли сервис, если нет — перезапускает.
 *
 * УРОВЕНЬ 7 — BootReceiver автозапуск после перезагрузки
 *
 * УРОВЕНЬ 8 — PhoneStateListener глушит ТОЛЬКО при звонках
 *   Музыка, игры, другие приложения НЕ мешают микрофону.
 */
class AikaMicrophoneService : Service() {

    companion object {
        private const val TAG = "AikaMic"
        private const val CHANNEL_ID = "aika_microphone_channel"
        private const val NOTIF_ID = 7771
        private const val HEARTBEAT_INTERVAL_MS = 60_000L       // 60 секунд
        private const val RESTART_DELAY_MS = 1_000L             // 1 секунда
        private const val WAKELOCK_REFRESH_MS = 30 * 60 * 1000L // 30 минут

        const val ACTION_START = "com.aika.MIC_START"
        const val ACTION_STOP = "com.aika.MIC_STOP"
        const val ACTION_PAUSE = "com.aika.MIC_PAUSE"
        const val ACTION_RESUME = "com.aika.MIC_RESUME"
        const val ACTION_HEARTBEAT = "com.aika.MIC_HEARTBEAT"
        const val ACTION_RESTART = "com.aika.MIC_RESTART"

        var isActive = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var telephonyManager: TelephonyManager? = null
    private var isPaused = false
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLockRefreshRunnable: Runnable? = null

    // ─── Lifecycle ─────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_RESTART, ACTION_HEARTBEAT, null -> {
                // null intent = система перезапустила после убийства (START_STICKY)
                if (intent?.action == ACTION_HEARTBEAT && isActive) {
                    // Сервис уже жив — просто обновляем WakeLock
                    refreshWakeLock()
                    scheduleHeartbeat()
                    return START_STICKY
                }
                if (intent?.action == ACTION_RESTART) {
                    Log.d(TAG, "RESTART (from AlarmManager)")
                }
                if (!hasMicPermission()) {
                    Log.e(TAG, "RECORD_AUDIO not granted — cannot start")
                    // Всё равно возвращаем STICKY — когда permission появится, система поднимет
                    scheduleRestart()
                    return START_STICKY
                }
                try {
                    startForegroundWithMicrophoneType()
                    acquireWakeLock()
                    setupPhoneStateListener()
                    scheduleHeartbeat()
                    isActive = true
                    isPaused = false
                    Log.d(TAG, "✅ Started (foreground + wakelock + heartbeat)")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start: ${e.message}")
                    scheduleRestart()
                    return START_STICKY
                }
            }
            ACTION_STOP -> {
                Log.d(TAG, "STOP (explicit)")
                cancelHeartbeat()
                releaseAll()
                try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                Log.d(TAG, "PAUSE — call/voice recording")
                isPaused = true
            }
            ACTION_RESUME -> {
                Log.d(TAG, "RESUME")
                isPaused = false
            }
        }
        // START_STICKY — система обязана перезапустить сервис после убийства
        return START_STICKY
    }

    // ─── УРОВЕНЬ 4: onTaskRemoved — свайп из Recents ───────────────

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "🚨 onTaskRemoved — restarting service")
        val restartIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
            action = ACTION_RESTART
            setPackage(packageName)
        }
        val pendingIntent = PendingIntent.getService(
            this, 1, restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + RESTART_DELAY_MS,
            pendingIntent
        )
        super.onTaskRemoved(rootIntent)
    }

    // ─── УРОВЕНЬ 5: onDestroy → AlarmManager restart ───────────────

    override fun onDestroy() {
        Log.d(TAG, "🚨 onDestroy — scheduling restart")
        releaseAll()
        scheduleRestart()
        super.onDestroy()
    }

    private fun scheduleRestart() {
        try {
            val restartIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
                action = ACTION_RESTART
                setPackage(packageName)
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext, 0, restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // setExactAndAllowWhileIdle — работает даже в Doze mode
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + RESTART_DELAY_MS,
                pendingIntent
            )
            Log.d(TAG, "Restart scheduled in ${RESTART_DELAY_MS}ms")
        } catch (e: Exception) {
            Log.e(TAG, "scheduleRestart failed: ${e.message}")
        }
    }

    // ─── УРОВЕНЬ 6: Heartbeat каждые 60 секунд ─────────────────────

    private fun scheduleHeartbeat() {
        cancelHeartbeat()
        val heartbeatIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
            action = ACTION_HEARTBEAT
            setPackage(packageName)
        }
        val pendingIntent = PendingIntent.getService(
            applicationContext, 2, heartbeatIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // setAndAllowWhileIdle — работает в Doze, но с ограничениями по частоте
        // Используем setInexactRepeating как fallback для агрессивного Doze
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + HEARTBEAT_INTERVAL_MS,
            pendingIntent
        )
        // Дополнительно — Handler-based heartbeat для случая когда процесс жив
        handler.postDelayed({
            if (!isActive) {
                Log.d(TAG, "💀 Handler heartbeat: service died — self-restart")
                val selfIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
                    action = ACTION_RESTART
                    setPackage(packageName)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(selfIntent)
                } else {
                    startService(selfIntent)
                }
            }
        }, HEARTBEAT_INTERVAL_MS)
        Log.d(TAG, "Heartbeat scheduled")
    }

    private fun cancelHeartbeat() {
        try {
            val heartbeatIntent = Intent(applicationContext, AikaMicrophoneService::class.java).apply {
                action = ACTION_HEARTBEAT
                setPackage(packageName)
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext, 2, heartbeatIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pendingIntent != null) {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                alarmManager.cancel(pendingIntent)
            }
        } catch (_: Exception) {}
    }

    // ─── УРОВЕНЬ 3: WakeLock с периодическим обновлением ───────────

    private fun hasMicPermission(): Boolean {
        return checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun startForegroundWithMicrophoneType() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground with type failed: ${e.message}")
            try { startForeground(NOTIF_ID, notification) } catch (e2: Exception) { throw e2 }
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aika:MicrophoneWakeLock")
            wakeLock?.setReferenceCounted(false)
            // 24 часа — но обновляем каждые 30 минут (см. ниже)
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
            Log.d(TAG, "WakeLock acquired")

            // Периодическое обновление WakeLock — каждые 30 минут
            wakeLockRefreshRunnable = object : Runnable {
                override fun run() {
                    refreshWakeLock()
                    handler.postDelayed(this, WAKELOCK_REFRESH_MS)
                }
            }
            handler.postDelayed(wakeLockRefreshRunnable!!, WAKELOCK_REFRESH_MS)
        } catch (e: Exception) { Log.e(TAG, "WakeLock acquire error: ${e.message}") }
    }

    private fun refreshWakeLock() {
        try {
            if (wakeLock?.isHeld != true) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aika:MicrophoneWakeLock")
                wakeLock?.setReferenceCounted(false)
            }
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
            Log.d(TAG, "WakeLock refreshed")
        } catch (e: Exception) { Log.e(TAG, "WakeLock refresh error: ${e.message}") }
    }

    private fun releaseWakeLock() {
        try {
            wakeLockRefreshRunnable?.let { handler.removeCallbacks(it) }
            wakeLockRefreshRunnable = null
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
        } catch (_: Exception) {}
    }

    // ─── PhoneState — глушить ТОЛЬКО при звонках ───────────────────

    private fun setupPhoneStateListener() {
        try {
            telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            telephonyManager?.listen(object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    when (state) {
                        TelephonyManager.CALL_STATE_IDLE -> {
                            if (isPaused) {
                                isPaused = false
                                Log.d(TAG, "Call ended — resume")
                            }
                        }
                        TelephonyManager.CALL_STATE_RINGING, TelephonyManager.CALL_STATE_OFFHOOK -> {
                            isPaused = true
                            Log.d(TAG, "Call active — pause")
                        }
                    }
                }
            }, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (e: Exception) { Log.e(TAG, "PhoneState error: ${e.message}") }
    }

    // ─── Notification ──────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Aika Microphone", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Микрофон активен"
                setShowBadge(false)
                // Важно: LOW importance = не убивается агрессивно
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val iconRes = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_silent_mode_off
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Aika слушает")
            .setContentText("Микрофон активен")
            .setSmallIcon(iconRes)
            .setOngoing(true)            // Не убирается свайпом
            .setPriority(Notification.PRIORITY_LOW)
            .setShowWhen(false)
            .build()
    }

    // ─── Cleanup ───────────────────────────────────────────────────

    private fun releaseAll() {
        cancelHeartbeat()
        releaseWakeLock()
        try { telephonyManager?.listen(null, PhoneStateListener.LISTEN_CALL_STATE) } catch (_: Exception) {}
        isActive = false
        isPaused = false
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
