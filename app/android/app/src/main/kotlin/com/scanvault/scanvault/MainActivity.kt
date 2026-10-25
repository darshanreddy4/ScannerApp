package com.scanvault.scanvault

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.IntentCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Receives files from "Open with" and "Share to" and hands copies of them to Dart.
 * Content URIs cannot be read by path, so each file is copied into the cache first.
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var cameraAccess: CameraAccessPlugin? = null
    private var dartReady = false
    private val pending = mutableListOf<Map<String, String>>()
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private val counter = AtomicInteger()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scanvault/incoming")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "takePending") {
                dartReady = true
                result.success(ArrayList(pending))
                pending.clear()
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        SharePlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        cameraAccess = CameraAccessPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        handle(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        cameraAccess?.onPermissionResult(requestCode)
    }

    // The address of an opened file must not become the first route.
    override fun getInitialRoute(): String? = "/"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(source: Intent?) {
        val i = source ?: return
        val uris = when (i.action) {
            Intent.ACTION_VIEW -> listOfNotNull(i.data)
            Intent.ACTION_SEND -> listOfNotNull(IntentCompat.getParcelableExtra(i, Intent.EXTRA_STREAM, Uri::class.java))
            Intent.ACTION_SEND_MULTIPLE -> IntentCompat.getParcelableArrayListExtra(i, Intent.EXTRA_STREAM, Uri::class.java) ?: emptyList<Uri>()
            else -> return
        }
        // Handled once: a recreated activity must not reopen the same file.
        setIntent(Intent())
        if (uris.isEmpty()) return

        io.execute {
            val files = uris.mapNotNull { copyToCache(it) }
            ui.post {
                val payload = if (files.isEmpty()) listOf(mapOf("error" to "unreadable")) else files
                if (dartReady) {
                    channel?.invokeMethod("incoming", payload)
                } else {
                    pending.addAll(payload)
                }
            }
        }
    }

    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val mime = contentResolver.getType(uri) ?: ""
            var name = displayName(uri) ?: uri.lastPathSegment ?: "file"
            name = File(name).name.replace(Regex("[^\\w.\\- ]"), "_").ifBlank { "file" }
            if (!name.contains('.')) {
                val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
                if (ext != null) name = "$name.$ext"
            }
            val dir = File(cacheDir, "incoming/${System.currentTimeMillis()}-${counter.incrementAndGet()}")
            dir.mkdirs()
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            mapOf("path" to out.absolutePath, "mime" to mime, "name" to name)
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme != "content") return null
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }
}
