package com.aika.assistant

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * DeviceAdminReceiver для функции блокировки экрана через DevicePolicyManager.
 * Нужно активировать вручную один раз в настройках устройства.
 */
class AikaDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}
