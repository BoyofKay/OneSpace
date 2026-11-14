package com.onespace.onespace

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Uses Android's system document picker. No storage permission, file path, or
 * persistent URI permission is requested. Data is returned only to the signed-in
 * Flutter UI and must be uploaded to an RLS-protected bucket.
 */
class MainActivity : FlutterFragmentActivity() {
    private val maxBytes = 10 * 1024 * 1024
    private var pendingDocument: MethodChannel.Result? = null
    private var pendingContact: MethodChannel.Result? = null
    private var pendingVcard: Map<String, String>? = null
    // External shares stay in memory only, until the signed-in UI collects them.
    private var pendingShare: Map<String, String>? = null
    private var shareChannel: MethodChannel? = null

    private val pickContact = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activity ->
        val pending = pendingContact ?: return@registerForActivityResult
        pendingContact = null
        if (activity.resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return@registerForActivityResult
        }
        val selected = activity.data?.data
        if (selected == null) {
            pending.success(null)
            return@registerForActivityResult
        }
        try {
            pending.success(readSelectedContact(selected))
        } catch (e: Exception) {
            pending.error("CONTACT_READ_FAILED", e.message ?: "Could not read contact", null)
        }
    }

    private val contactsPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        val pending = pendingContact ?: return@registerForActivityResult
        if (!granted) {
            pendingContact = null
            pending.error("CONTACT_PERMISSION_DENIED",
                "Contacts permission is needed to import the selected contact.", null)
        } else {
            try {
                pickContact.launch(Intent(Intent.ACTION_PICK,
                    ContactsContract.Contacts.CONTENT_URI))
            } catch (e: Exception) {
                pendingContact = null
                pending.error("CONTACT_PICK_FAILED", e.message, null)
            }
        }
    }

    private fun readSelectedContact(uri: Uri): Map<String, String> {
        var selectedId: String? = null
        var name = ""
        contentResolver.query(uri, arrayOf(
            ContactsContract.Contacts._ID,
            ContactsContract.Contacts.DISPLAY_NAME_PRIMARY), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    selectedId = cursor.getString(0)
                    name = cursor.getString(1) ?: ""
                }
            }
        val result = mutableMapOf("person" to name.take(180))
        val id = selectedId ?: return result
        contentResolver.query(ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.Data.MIMETYPE,
                ContactsContract.Data.DATA1, ContactsContract.Data.DATA4),
            "${ContactsContract.Data.CONTACT_ID} = ?",
            arrayOf(id), null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val kind = cursor.getString(0) ?: continue
                val value = cursor.getString(1)?.trim().orEmpty()
                val extra = cursor.getString(2)?.trim().orEmpty()
                if (value.isEmpty()) continue
                when (kind) {
                    ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE ->
                        result.putIfAbsent("phone", value.take(80))
                    ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE ->
                        result.putIfAbsent("email", value.take(254))
                    ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE ->
                        result.putIfAbsent("address", value.take(1000))
                    ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> {
                        result.putIfAbsent("company", value.take(180))
                        if (extra.isNotEmpty()) result.putIfAbsent("role", extra.take(180))
                    }
                    ContactsContract.CommonDataKinds.Website.CONTENT_ITEM_TYPE ->
                        result.putIfAbsent("website", value.take(500))
                }
            }
        }
        return result
    }

    private fun parseVcard(text: String): Map<String, String>? {
        if (!text.contains("BEGIN:VCARD", ignoreCase = true)) return null
        val lines = mutableListOf<String>()
        for (line in text.replace("\r\n", "\n").split("\n")) {
            if ((line.startsWith(" ") || line.startsWith("\t")) && lines.isNotEmpty())
                lines[lines.size - 1] += line.drop(1)
            else lines.add(line)
        }
        val result = mutableMapOf<String, String>()
        for (line in lines) {
            val delimiter = line.indexOf(':')
            if (delimiter < 1) continue
            val name = line.substring(0, delimiter).substringBefore(';')
                .substringAfterLast('.').uppercase()
            val raw = line.substring(delimiter + 1)
                .replace("\\n", "\n").replace("\\,", ",").trim()
            if (raw.isEmpty()) continue
            when (name) {
                "FN" -> result.putIfAbsent("person", raw.take(180))
                "TEL" -> result.putIfAbsent("phone", raw.take(80))
                "EMAIL" -> result.putIfAbsent("email", raw.take(254))
                "ADR" -> result.putIfAbsent("address", raw.replace(';', ' ').take(1000))
                "ORG" -> result.putIfAbsent("company", raw.take(180))
                "TITLE" -> result.putIfAbsent("role", raw.take(180))
                "URL" -> result.putIfAbsent("website", raw.take(500))
            }
        }
        return if (result.isNotEmpty()) result else null
    }

    private fun captureShare(incoming: Intent?) {
        if (incoming?.action != Intent.ACTION_SEND) return
        val mime = incoming.type.orEmpty().lowercase()
        if (mime in listOf("text/x-vcard", "text/vcard", "text/directory",
                "application/vcard", "application/x-vcard")) {
            try {
                val uri = incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                val data = if (uri == null) {
                    incoming.getStringExtra(Intent.EXTRA_TEXT).orEmpty().take(65536)
                } else {
                    contentResolver.openInputStream(uri)?.use { source ->
                        val bytes = ByteArrayOutputStream()
                        val buffer = ByteArray(4096)
                        while (bytes.size() < 65536) {
                            val count = source.read(buffer, 0,
                                minOf(buffer.size, 65536 - bytes.size()))
                            if (count <= 0) break
                            bytes.write(buffer, 0, count)
                        }
                        bytes.toString(Charsets.UTF_8.name())
                    }.orEmpty()
                }
                pendingVcard = parseVcard(data)
                if (pendingVcard != null) shareChannel?.invokeMethod("shareAvailable", true)
            } catch (_: Exception) { /* Ignore malformed or unreadable vCards. */ }
            return
        }
        if (mime != "text/plain") return
        val sharedText = incoming.getStringExtra(Intent.EXTRA_TEXT)?.take(8000)?.trim()
        if (sharedText.isNullOrEmpty()) return
        pendingShare = mapOf(
            "text" to sharedText,
            "subject" to (incoming.getStringExtra(Intent.EXTRA_SUBJECT) ?: "").take(160)
        )
        shareChannel?.invokeMethod("shareAvailable", true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
    }

    private val pickDocument = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        val result = pendingDocument ?: return@registerForActivityResult
        pendingDocument = null
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }
        try {
            var displayName = "Travel document"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        displayName = cursor.getString(0) ?: displayName
                    }
                }
            val stream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Cannot read document")
            val output = ByteArrayOutputStream()
            stream.use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val length = input.read(buffer)
                    if (length < 0) break
                    if (output.size() + length > maxBytes) {
                        throw IllegalArgumentException("Document exceeds 10 MB")
                    }
                    output.write(buffer, 0, length)
                }
            }
            result.success(mapOf("name" to displayName, "bytes" to output.toByteArray()))
        } catch (e: Exception) {
            result.error("DOCUMENT_READ_FAILED", e.message ?: "Unable to read the document", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "onespace/incoming_share"
        )
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingShare" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "onespace/device_contacts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickContact" -> {
                        if (pendingContact != null) {
                            result.error("ALREADY_PICKING", "A contact is being selected", null)
                        } else {
                            pendingContact = result
                            if (ContextCompat.checkSelfPermission(this,
                                    Manifest.permission.READ_CONTACTS) ==
                                PackageManager.PERMISSION_GRANTED) {
                                try {
                                    pickContact.launch(Intent(Intent.ACTION_PICK,
                                        ContactsContract.Contacts.CONTENT_URI))
                                } catch (e: Exception) {
                                    pendingContact = null
                                    result.error("CONTACT_PICK_FAILED", e.message, null)
                                }
                            } else {
                                contactsPermission.launch(Manifest.permission.READ_CONTACTS)
                            }
                        }
                    }
                    "saveToPhone" -> {
                        val map = call.arguments as? Map<*, *> ?: emptyMap<String, String>()
                        fun field(key: String): String = map[key]?.toString().orEmpty()
                        try {
                            val insert = Intent(Intent.ACTION_INSERT).apply {
                                type = ContactsContract.Contacts.CONTENT_TYPE
                                putExtra(ContactsContract.Intents.Insert.NAME, field("person"))
                                putExtra(ContactsContract.Intents.Insert.PHONE, field("phone"))
                                putExtra(ContactsContract.Intents.Insert.EMAIL, field("email"))
                                putExtra(ContactsContract.Intents.Insert.POSTAL, field("address"))
                                putExtra(ContactsContract.Intents.Insert.COMPANY, field("company"))
                                putExtra(ContactsContract.Intents.Insert.JOB_TITLE, field("role"))
                            }
                            startActivity(insert)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CONTACT_SAVE_FAILED", e.message, null)
                        }
                    }
                    "takePendingVcard" -> {
                        result.success(pendingVcard)
                        pendingVcard = null
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "onespace/travel_documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickDocument") {
                    result.notImplemented()
                } else if (pendingDocument != null) {
                    result.error("ALREADY_PICKING", "Document picker is already open", null)
                } else {
                    pendingDocument = result
                    try {
                        pickDocument.launch(arrayOf(
                            "application/pdf", "image/jpeg", "image/png", "image/webp"
                        ))
                    } catch (e: Exception) {
                        pendingDocument = null
                        result.error("PICKER_FAILED", e.message, null)
                    }
                }
            }
    }
}
