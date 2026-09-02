package com.aika.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Автозапуск после перезагрузки устройства.
 * Стартует ОБА сервиса: overlay + microphone.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        Log.d("Aika", "Boot completed — starting services")

        // 1. Microphone Service — всегда (не требует overlay permission)
        if (context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            try {
                val micIntent = Intent(context, AikaMicrophoneService::class.java).apply {
                    action = AikaMicrophoneService.ACTION_START
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(micIntent)
                } else {
                    context.startService(micIntent)
                }
                Log.d("Aika", "Microphone service auto-started after boot")
            } catch (e: Exception) {
                Log.e("Aika", "Failed to start microphone after boot: ${e.message}")
            }
        } else {
            Log.d("Aika", "RECORD_AUDIO not granted — skipping mic auto-start")
        }

        // 2. Overlay Service — только если есть overlay permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(context)) {
                Log.d("Aika", "No overlay permission — skipping overlay auto-start on boot")
                return
            }
        }
        try {
            val overlayIntent = Intent(context, AikaOverlayService::class.java).apply {
                action = AikaOverlayService.ACTION_SHOW
                putExtra(AikaOverlayService.EXTRA_STATE, "idle")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(overlayIntent)
            } else {
                context.startService(overlayIntent)
            }
            Log.d("Aika", "Overlay auto-started after boot")
        } catch (e: Exception) {
            Log.e("Aika", "Failed to start overlay after boot: ${e.message}")
        }
    }
}
