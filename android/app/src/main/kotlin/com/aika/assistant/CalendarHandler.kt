package com.aika.assistant

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * CalendarHandler — нативный доступ к системному календарю.
 * Адаптировано из openclaw-assistant CalendarHandler.kt (MIT License).
 * Подключается к MethodChannel "com.aika.assistant/calendar" в MainActivity.
 */
class CalendarHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getEvents" -> handleGetEvents(call, result)
            "createEvent" -> handleCreateEvent(call, result)
            else -> result.notImplemented()
        }
    }

    private fun hasReadPermission() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
                PackageManager.PERMISSION_GRANTED

    private fun hasWritePermission() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALENDAR) ==
                PackageManager.PERMISSION_GRANTED

    private fun handleGetEvents(call: MethodCall, result: MethodChannel.Result) {
        if (!hasReadPermission()) {
            result.error("PERMISSION_DENIED", "READ_CALENDAR permission required", null)
            return
        }

        val startMs = call.argument<Long>("startMs") ?: System.currentTimeMillis()
        val endMs   = call.argument<Long>("endMs")   ?: startMs + 86400000L

        val events  = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.ALL_DAY,
        )

        val selection = "(${CalendarContract.Events.DTSTART} >= ?) AND (${CalendarContract.Events.DTSTART} <= ?)"
        val selArgs   = arrayOf(startMs.toString(), endMs.toString())

        try {
            context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection, selection, selArgs,
                "${CalendarContract.Events.DTSTART} ASC"
            )?.use { cursor ->
                val idxTitle    = cursor.getColumnIndex(CalendarContract.Events.TITLE)
                val idxStart    = cursor.getColumnIndex(CalendarContract.Events.DTSTART)
                val idxEnd      = cursor.getColumnIndex(CalendarContract.Events.DTEND)
                val idxDesc     = cursor.getColumnIndex(CalendarContract.Events.DESCRIPTION)
                val idxLocation = cursor.getColumnIndex(CalendarContract.Events.EVENT_LOCATION)
                val idxAllDay   = cursor.getColumnIndex(CalendarContract.Events.ALL_DAY)

                while (cursor.moveToNext()) {
                    events.add(mapOf(
                        "title"     to (cursor.getString(idxTitle) ?: ""),
                        "startMs"   to cursor.getLong(idxStart),
                        "endMs"     to cursor.getLong(idxEnd),
                        "desc"      to (cursor.getString(idxDesc) ?: ""),
                        "location"  to (cursor.getString(idxLocation) ?: ""),
                        "allDay"    to (cursor.getInt(idxAllDay) == 1),
                    ))
                }
            }
            result.success(events)
        } catch (e: Exception) {
            result.error("QUERY_ERROR", e.message, null)
        }
    }

    private fun handleCreateEvent(call: MethodCall, result: MethodChannel.Result) {
        if (!hasWritePermission()) {
            result.error("PERMISSION_DENIED", "WRITE_CALENDAR permission required", null)
            return
        }

        val title   = call.argument<String>("title") ?: "Событие"
        val startMs = call.argument<Long>("startMs") ?: System.currentTimeMillis()
        val endMs   = call.argument<Long>("endMs")   ?: startMs + 3600000L
        val desc    = call.argument<String>("description") ?: ""

        val calId = getFirstWritableCalendarId()
        if (calId == null) {
            result.error("NO_CALENDAR", "No writable calendar found", null)
            return
        }

        val values = ContentValues().apply {
            put(CalendarContract.Events.DTSTART, startMs)
            put(CalendarContract.Events.DTEND, endMs)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, desc)
            put(CalendarContract.Events.CALENDAR_ID, calId)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
        }

        try {
            val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            result.success(uri != null)
        } catch (e: Exception) {
            result.error("INSERT_ERROR", e.message, null)
        }
    }

    private fun getFirstWritableCalendarId(): Long? {
        val proj = arrayOf(CalendarContract.Calendars._ID)
        val sel  = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?"
        val args = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, proj, sel, args, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getLong(0)
        }
        return null
    }
}
