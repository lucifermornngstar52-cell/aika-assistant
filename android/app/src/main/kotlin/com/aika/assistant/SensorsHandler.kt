package com.aika.assistant

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * SensorsHandler — шагомер через TYPE_STEP_COUNTER.
 * Адаптировано из openclaw-assistant MotionHandler.kt (MIT License).
 * MethodChannel: "com.aika.assistant/sensors"
 */
class SensorsHandler(private val context: Context) : MethodChannel.MethodCallHandler, SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val stepSensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    private var currentSteps: Float = 0f
    private var registered = false

    init {
        register()
    }

    private fun register() {
        if (registered || stepSensor == null) return
        sensorManager.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_UI)
        registered = true
    }

    fun unregister() {
        if (!registered) return
        sensorManager.unregisterListener(this)
        registered = false
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_STEP_COUNTER) {
            currentSteps = event.values[0]
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSteps" -> result.success(currentSteps.toInt())
            "isAvailable" -> result.success(stepSensor != null)
            else -> result.notImplemented()
        }
    }
}
