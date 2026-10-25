package com.scanvault.scanvault

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Lets the Dart side start, list and stop shares that run in [ShareService]. */
class SharePlugin(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private val context: Context = activity.applicationContext

    init {
        ShareRegistry.init(File(context.noBackupFilesDir, "shares"))
        MethodChannel(messenger, "scanvault/share").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "stop" -> {
                ShareRegistry.stop(call.argument<String>("id").orEmpty())
                result.success(null)
            }
            "stopAll" -> {
                ShareRegistry.stopAll()
                result.success(null)
            }
            "list" -> result.success(ShareRegistry.list().map { describe(it) })
            "info" -> {
                val entry = ShareRegistry.get(call.argument<String>("id").orEmpty())
                result.success(mapOf("live" to (entry != null && !entry.server.ended), "downloads" to (entry?.server?.downloads ?: 0)))
            }
            else -> result.notImplemented()
        }
    }

    private fun describe(e: ShareRegistry.Entry) = mapOf(
        "id" to e.id,
        "url" to e.url,
        "fileName" to e.fileName,
        "expiresAt" to e.server.expiresAt,
        "downloads" to e.server.downloads,
        "protected" to e.server.isProtected,
    )

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("filePath").orEmpty()
        val name = call.argument<String>("fileName").orEmpty()
        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
        val ttl = (call.argument<Number>("ttlMs") ?: 300_000).toLong()
        val password = call.argument<String>("password")
        askForNotifications()
        io.execute {
            try {
                val source = File(path)
                val host = ShareRegistry.lanAddress()
                when {
                    !source.exists() -> fail(result, "missing_file", "The file to share could not be found.")
                    host == null -> fail(result, "no_network", "Connect to Wi-Fi (or turn on a hotspot) to share with a QR code.")
                    else -> {
                        val entry = ShareRegistry.start(source, name, mime, ttl, password, host)
                        ui.post {
                            ContextCompat.startForegroundService(context, Intent(context, ShareService::class.java))
                            result.success(describe(entry))
                        }
                    }
                }
            } catch (e: Exception) {
                fail(result, "start_failed", "Sharing could not be started on this network.", e.toString())
            }
        }
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String, details: String? = null) {
        ui.post { result.error(code, message, details) }
    }

    /** Android 13+ hides the notification until allowed; sharing works either way, so this never blocks. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT < 33) return
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4401)
    }
}
