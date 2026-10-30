package com.doculoom.app

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
    private var reminders: ReminderPlugin? = null
    private var speech: SpeechPlugin? = null
    private var wifi: WifiPlugin? = null
    private var dartReady = false
    private val pending = mutableListOf<Map<String, String>>()
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private val counter = AtomicInteger()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "doculoom/incoming")
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
        reminders = ReminderPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        ContactsPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        speech = SpeechPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        wifi = WifiPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        ScreenPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        handle(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        cameraAccess?.onPermissionResult(requestCode)
        reminders?.onPermissionResult(requestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        wifi?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        speech?.shutdown()
        super.onDestroy()
    }

    // The address of an opened file must not become the first route.
    override fun getInitialRoute(): String? = "/"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun deliver(payload: List<Map<String, String>>) {
        if (dartReady) {
            channel?.invokeMethod("incoming", payload)
        } else {
            pending.addAll(payload)
        }
    }

    private fun handle(source: Intent?) {
        val i = source ?: return
        // A shortcut, the widget or a quick-settings tile: Dart opens the matching screen.
        val quick = i.getStringExtra(QuickActions.EXTRA)
        if (quick != null) {
            setIntent(Intent())
            deliver(listOf(mapOf("action" to quick)))
            return
        }
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
                deliver(payload)
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
