package com.doculoom.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Tells Dart whether the camera may be used, asks when Android still allows asking, and opens the app's settings.
 * "blocked" means Android will not show the question again, so only Settings can turn the camera on.
 */
class CameraAccessPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val prefs = activity.getSharedPreferences("camera_access", Context.MODE_PRIVATE)
    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "doculoom/camera_access").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "request" -> request(result)
                "openSettings" -> result.success(openSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun status(): String {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) return "granted"
        val asked = prefs.getBoolean(ASKED, false)
        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.CAMERA)
        return if (asked && !canAskAgain) "blocked" else "denied"
    }

    private fun request(result: MethodChannel.Result) {
        val now = status()
        // Nothing to ask, or a question is already on screen.
        if (now != "denied" || pending != null) {
            result.success(now)
            return
        }
        pending = result
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), REQUEST_CODE)
    }

    /** Called from the activity; returns true when the answer was for this plugin. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        prefs.edit().putBoolean(ASKED, true).apply()
        pending?.success(status())
        pending = null
        return true
    }

    private fun openSettings(): Boolean = try {
        activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null)))
        true
    } catch (e: Exception) {
        false
    }

    private companion object {
        const val REQUEST_CODE = 4711
        const val ASKED = "asked"
    }
}
