package com.aikaassistant.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.telecom.TelecomManager
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class PhoneControlChannel(private val context: Context, private val activity: Activity?) {
    companion object {
        const val CHANNEL = "aika/phone_control"
    }

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBrightness" -> {
                    val value = call.argument<Int>("value") ?: 128
                    setBrightness(value, result)
                }
                "setAutoBrightness" -> {
                    setAutoBrightness(result)
                }
                "endCall" -> {
                    endCall(result)
                }
                "answerCall" -> {
                    answerCall(result)
                }
                "takeScreenshot" -> {
                    // Через Accessibility Service
                    result.success("screenshot_requested")
                }
                "getVolume" -> {
                    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val vol = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    result.success(vol.toDouble() / max.toDouble())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setBrightness(value: Int, result: MethodChannel.Result) {
        try {
            if (Settings.System.canWrite(context)) {
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
                )
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    value.coerceIn(0, 255)
                )
                activity?.window?.let { window ->
                    val params = window.attributes
                    params.screenBrightness = value / 255f
                    window.attributes = params
                }
                result.success("ok")
            } else {
                // Запрашиваем разрешение WRITE_SETTINGS
                val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.error("PERMISSION", "Нужно разрешение WRITE_SETTINGS", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun setAutoBrightness(result: MethodChannel.Result) {
        try {
            if (Settings.System.canWrite(context)) {
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC
                )
                result.success("ok")
            } else {
                result.error("PERMISSION", "Нужно разрешение WRITE_SETTINGS", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun endCall(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                telecomManager.endCall()
                result.success("ok")
            } else {
                result.error("VERSION", "Требуется Android 9+", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun answerCall(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                telecomManager.acceptRingingCall()
                result.success("ok")
            } else {
                result.error("VERSION", "Требуется Android 8+", null)
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
