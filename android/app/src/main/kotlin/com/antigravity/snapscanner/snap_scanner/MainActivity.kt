package com.antigravity.snapscanner.snap_scanner

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives PDFs opened with / shared to Snap Scanner and hands them to
 * Flutter as a local file path (content:// URIs are copied into the cache,
 * because the source app's read permission is only temporary).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Cold start: Flutter asks once it is ready.
                    "getInitialPdf" -> {
                        result.success(pendingPath)
                        pendingPath = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        pendingPath = copyPdfFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App already running: push the file straight to Flutter.
        copyPdfFrom(intent)?.let { channel?.invokeMethod("onPdf", it) }
    }

    private fun copyPdfFrom(intent: Intent?): String? {
        val uri: Uri = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        } ?: return null

        return try {
            val dir = File(cacheDir, "incoming/${System.currentTimeMillis()}").apply { mkdirs() }
            val target = File(dir, sanitize(displayName(uri)))
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            // Consume the intent so a rotation/recreate doesn't re-open it.
            intent?.action = null
            target.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) c.getString(0)?.let { return it } }
            } catch (_: Exception) {
            }
        }
        return uri.lastPathSegment ?: "Document.pdf"
    }

    private fun sanitize(name: String): String {
        val clean = name.substringAfterLast('/').replace(Regex("[\\\\:*?\"<>|]"), "_").ifBlank { "Document" }
        return if (clean.lowercase().endsWith(".pdf")) clean else "$clean.pdf"
    }

    companion object {
        private const val CHANNEL = "snap_scanner/incoming_pdf"
    }
}
