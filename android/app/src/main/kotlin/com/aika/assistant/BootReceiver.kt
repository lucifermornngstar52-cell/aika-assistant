package com.aika.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Автозапуск overlay после перезагрузки устройства.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        Log.d("Aika", "Boot completed — checking overlay permission")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(context)) {
                Log.d("Aika", "No overlay permission — skipping auto-start on boot")
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