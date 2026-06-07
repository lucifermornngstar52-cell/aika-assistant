package com.aika.assistant

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ContactsHandler — поиск контактов.
 * Адаптировано из openclaw-assistant ContactsHandler.kt (MIT License).
 * MethodChannel: "com.aika.assistant/contacts"
 */
class ContactsHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "searchContacts" -> handleSearch(call, result)
            else -> result.notImplemented()
        }
    }

    private fun hasPermission() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) ==
                PackageManager.PERMISSION_GRANTED

    private fun handleSearch(call: MethodCall, result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("PERMISSION_DENIED", "READ_CONTACTS permission required", null)
            return
        }

        val query = call.argument<String>("query") ?: ""
        if (query.isBlank()) {
            result.error("INVALID_QUERY", "Query must not be empty", null)
            return
        }

        val contacts = mutableListOf<Map<String, String>>()
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        val selection    = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf("%$query%")

        try {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection, selection, selectionArgs,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
            )?.use { cursor ->
                val nameIdx   = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numberIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val seen      = mutableSetOf<String>()

                while (cursor.moveToNext()) {
                    val name   = cursor.getString(nameIdx)  ?: continue
                    val number = cursor.getString(numberIdx) ?: continue
                    val key    = "$name|$number"
                    if (seen.add(key)) {
                        contacts.add(mapOf("name" to name, "phone" to number))
                    }
                }
            }
            result.success(contacts)
        } catch (e: Exception) {
            result.error("QUERY_ERROR", e.message, null)
        }
    }
}
