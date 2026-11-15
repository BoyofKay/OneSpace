package com.onespace.onespace

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.provider.MediaStore
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
    private var checklistVoice: TextToSpeech? = null
    private var checklistVoiceReady = false
    private var pendingDocument: MethodChannel.Result? = null
    private var pendingContact: MethodChannel.Result? = null
    private var pendingVcard: Map<String, String>? = null
    // External shares stay in memory only, until the signed-in UI collects them.
    private var pendingShare: Map<String, Any>? = null
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

    // R61: in-app listening (live words, no Google pop-up). Audio stays on
    // the phone's recognizer; only text comes back to OneSpace.
    private var voiceChannel: MethodChannel? = null
    private var recognizer: android.speech.SpeechRecognizer? = null
    private var pendingListenLanguage: String = "en-US"
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private fun sendVoice(method: String, value: Any?) {
        mainHandler.post { voiceChannel?.invokeMethod(method, value) }
    }
    private val micPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startRecognizer(pendingListenLanguage)
        else sendVoice("onError", "permission")
    }
    private fun startRecognizer(language: String) {
        if (!android.speech.SpeechRecognizer.isRecognitionAvailable(this)) {
            sendVoice("onError", "unavailable"); return
        }
        recognizer?.destroy()
        val r = android.speech.SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : android.speech.RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { sendVoice("onReady", null) }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) { sendVoice("onLevel", rmsdB.toDouble()) }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { sendVoice("onEnd", null) }
            override fun onError(error: Int) {
                sendVoice("onError", when (error) {
                    android.speech.SpeechRecognizer.ERROR_NO_MATCH,
                    android.speech.SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "nothing"
                    android.speech.SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
                    android.speech.SpeechRecognizer.ERROR_NETWORK,
                    android.speech.SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
                    else -> "error$error"
                })
            }
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                sendVoice("onFinal", text ?: "")
            }
            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults?.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (!text.isNullOrBlank()) sendVoice("onPartial", text)
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(android.speech.RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        r.startListening(intent)
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
        // R55: a photo or PDF shared from another app. Read once (<= 10 MB) and
        // hand the bytes to Flutter; no storage permission or URI is kept.
        if (mime.startsWith("image/") || mime == "application/pdf") {
            try {
                val uri = incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
                var name = if (mime == "application/pdf") "Shared PDF" else "Shared photo"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) name = c.getString(0) ?: name }
                val bytes = contentResolver.openInputStream(uri)?.use { source ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(16384)
                    while (true) {
                        val count = source.read(buffer)
                        if (count <= 0) break
                        out.write(buffer, 0, count)
                        if (out.size() > maxBytes) throw IllegalStateException("too large")
                    }
                    out.toByteArray()
                } ?: return
                pendingShare = mapOf(
                    "text" to (incoming.getStringExtra(Intent.EXTRA_TEXT) ?: "").take(8000),
                    "subject" to (incoming.getStringExtra(Intent.EXTRA_SUBJECT) ?: "").take(160),
                    "fileBytes" to bytes,
                    "fileName" to name.take(200),
                    "fileMime" to mime
                )
                shareChannel?.invokeMethod("shareAvailable", true)
            } catch (_: Exception) {
                pendingShare = mapOf("text" to "", "subject" to "", "fileError" to "This file is too large or could not be read (10 MB max).")
                shareChannel?.invokeMethod("shareAvailable", true)
            }
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

    // R61: long-press the app icon → "Voice command".
    private var pendingVoiceLaunch = false
    private fun captureVoiceLaunch(incoming: Intent?) {
        if (incoming?.action == "com.onespace.onespace.VOICE") {
            pendingVoiceLaunch = true
            sendVoice("launchVoice", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
        captureVoiceLaunch(intent)
        try {
            androidx.core.content.pm.ShortcutManagerCompat.pushDynamicShortcut(this,
                androidx.core.content.pm.ShortcutInfoCompat.Builder(this, "voice")
                    .setShortLabel(getString(R.string.shortcut_voice_short))
                    .setLongLabel(getString(R.string.shortcut_voice_long))
                    .setIcon(androidx.core.graphics.drawable.IconCompat.createWithResource(this, R.mipmap.ic_launcher))
                    .setIntent(Intent(this, MainActivity::class.java).setAction("com.onespace.onespace.VOICE"))
                    .build())
        } catch (_: Exception) { /* launchers without shortcut support */ }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
        captureVoiceLaunch(intent)
    }

    // R60: voice commands use Android's own speech recognizer screen; the
    // audio never reaches OneSpace — only the recognized text comes back.
    private var pendingVoice: MethodChannel.Result? = null
    private val listenForSpeech = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { outcome ->
        val callback = pendingVoice
        pendingVoice = null
        val heard = outcome.data
            ?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)
            ?.firstOrNull()
        callback?.success(if (outcome.resultCode == Activity.RESULT_OK) heard else null)
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
        // Speech is explicit, local to this screen and stops on background.
        // No listening or microphone access is involved in this channel.
        checklistVoice = TextToSpeech(applicationContext) { status ->
            checklistVoiceReady = status == TextToSpeech.SUCCESS
            checklistVoice?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    if (checklistVoice?.isSpeaking != true) sendVoice("onSpeechDone", null)
                }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) { sendVoice("onSpeechDone", null) }
            })
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "onespace/checklist_speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "stop" -> {
                        checklistVoice?.stop()
                        result.success(null)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text").orEmpty().trim()
                        val language = call.argument<String>("language") ?: "en"
                        val rate = (call.argument<Double>("rate") ?: 1.0).coerceIn(0.7,1.4)
                        val voice = checklistVoice
                        if (!checklistVoiceReady || voice == null) {
                            result.error("VOICE_UNAVAILABLE",
                                "Text to speech is not ready or missing on this device.", null)
                        } else if (text.isEmpty() || text.length > 60000) {
                            result.error("INVALID_TEXT", "Checklist text is empty or too long.", null)
                        } else {
                            val locale = Locale.forLanguageTag(language)
                            val supported = voice.isLanguageAvailable(locale)
                            if (supported >= TextToSpeech.LANG_AVAILABLE) {
                                voice.language = locale
                            } else {
                                voice.language = Locale.getDefault()
                            }
                            voice.setSpeechRate(rate.toFloat())
                            // Android TTS has an utterance size limit. Break on
                            // word boundaries, and queue rather than truncate.
                            val chunks = mutableListOf<String>()
                            val segment = StringBuilder()
                            for (word in text.split(Regex("\\s+"))) {
                                if (segment.length + word.length + 1 > 3000 &&
                                    segment.isNotEmpty()) {
                                    chunks.add(segment.toString())
                                    segment.setLength(0)
                                }
                                if (segment.isNotEmpty()) segment.append(' ')
                                segment.append(word)
                            }
                            if (segment.isNotEmpty()) chunks.add(segment.toString())
                            var resultCode = TextToSpeech.SUCCESS
                            chunks.forEachIndexed { index, chunk ->
                                val queued = voice.speak(chunk,
                                    if (index == 0) TextToSpeech.QUEUE_FLUSH
                                    else TextToSpeech.QUEUE_ADD,
                                    null, "onespace-checklist-${System.nanoTime()}-$index")
                                if (queued == TextToSpeech.ERROR) resultCode = queued
                            }
                            if (resultCode == TextToSpeech.ERROR) {
                                voice.stop()
                                result.error("VOICE_UNAVAILABLE", "The speech engine failed.", null)
                            } else result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Export a rendered scrapbook page into Android Photos using scoped
        // storage, then show the native Share sheet. No storage permission,
        // unrestricted file access or private photo URI is exposed.
        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "onespace/voice")
        voiceChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        pendingListenLanguage = call.argument<String>("language") ?: "en-US"
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                            PackageManager.PERMISSION_GRANTED) startRecognizer(pendingListenLanguage)
                        else micPermission.launch(Manifest.permission.RECORD_AUDIO)
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    "stop" -> { recognizer?.stopListening(); result.success(null); return@setMethodCallHandler }
                    "cancel" -> { recognizer?.cancel(); result.success(null); return@setMethodCallHandler }
                    "takeLaunch" -> {
                        result.success(pendingVoiceLaunch)
                        pendingVoiceLaunch = false
                        return@setMethodCallHandler
                    }
                    "available" -> {
                        result.success(android.speech.SpeechRecognizer.isRecognitionAvailable(this))
                        return@setMethodCallHandler
                    }
                }
                if (call.method != "listen") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingVoice != null) {
                    result.error("BUSY", "Already listening", null)
                    return@setMethodCallHandler
                }
                val language = call.argument<String>("language") ?: "en-US"
                val prompt = call.argument<String>("prompt") ?: "What would you like to do?"
                val intent = Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, language)
                    putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, prompt)
                    putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                try {
                    pendingVoice = result
                    listenForSpeech.launch(intent)
                } catch (e: Exception) {
                    pendingVoice = null
                    result.error("NO_RECOGNIZER", "Speech recognition is not available on this phone.", null)
                }
            }
        // R59: "Download my data" saves a JSON file to Downloads/OneSpace.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "onespace/data_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = (call.argument<String>("name") ?: "OneSpace-data")
                    .replace(Regex("[^a-zA-Z0-9_.-]"), "-").take(80)
                if (bytes == null || bytes.isEmpty() || bytes.size > 50 * 1024 * 1024) {
                    result.error("EXPORT_UNAVAILABLE", "Nothing to save, or the file is too large.", null)
                    return@setMethodCallHandler
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val fields = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            put(MediaStore.Downloads.MIME_TYPE, "application/json")
                            put(MediaStore.Downloads.RELATIVE_PATH, "Download/OneSpace")
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, fields)
                            ?: throw IllegalStateException("Could not create the file")
                        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            ?: throw IllegalStateException("Could not write the file")
                        contentResolver.update(uri, ContentValues().apply {
                            put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                        result.success("Downloads/OneSpace/$name")
                    } else {
                        val dir = getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
                            ?: throw IllegalStateException("No downloads folder")
                        java.io.File(dir, name).writeBytes(bytes)
                        result.success(java.io.File(dir, name).absolutePath)
                    }
                } catch (e: Exception) {
                    result.error("EXPORT_FAILED", e.message ?: "Could not save the file", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "onespace/scrapbook_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveAndShare") {
                    result.notImplemented()
                } else {
                    val png = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "OneSpace-Scrapbook"
                    if (png == null || png.isEmpty() || png.size > 15 * 1024 * 1024 ||
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.error("EXPORT_UNAVAILABLE",
                            "PNG is too large or this Android version does not support secure export.",
                            null)
                    } else {
                        val safeName = name.replace(Regex("[^a-zA-Z0-9_-]"), "-")
                            .take(55).ifBlank { "OneSpace-Scrapbook" }
                        val fields = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME,
                                safeName + "-" + System.currentTimeMillis() + ".png")
                            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/OneSpace")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                        var savedUri: Uri? = null
                        try {
                            savedUri = contentResolver.insert(
                                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, fields)
                                ?: throw IllegalStateException("Could not create picture")
                            contentResolver.openOutputStream(savedUri)?.use { output ->
                                output.write(png)
                            } ?: throw IllegalStateException("Could not save picture")
                            val finished = ContentValues().apply {
                                put(MediaStore.Images.Media.IS_PENDING, 0)
                            }
                            contentResolver.update(savedUri, finished, null, null)
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "image/png"
                                putExtra(Intent.EXTRA_STREAM, savedUri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(share, "Share scrapbook page"))
                            result.success(true)
                        } catch (e: Exception) {
                            savedUri?.let { try {
                                contentResolver.delete(it, null, null)
                            } catch (_: Exception) { } }
                            result.error("EXPORT_FAILED",
                                e.message ?: "Unable to save scrapbook PNG", null)
                        }
                    }
                }
            }
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

    override fun onPause() {
        checklistVoice?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        checklistVoice?.stop()
        checklistVoice?.shutdown()
        checklistVoice = null
        checklistVoiceReady = false
        super.onDestroy()
    }
}
