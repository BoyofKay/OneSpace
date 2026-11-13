package com.onespace.onespace

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
