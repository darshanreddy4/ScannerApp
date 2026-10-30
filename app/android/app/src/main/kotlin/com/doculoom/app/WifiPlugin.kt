package com.doculoom.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Adds a Wi-Fi network read from a QR code. On Android 11 and newer the system shows its own "add network" sheet, so the
 * person confirms it and this app needs no Wi-Fi permission. Older phones, and WEP networks (which that sheet does not
 * support), are sent to Wi-Fi settings instead.
 */
class WifiPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "doculoom/wifi").setMethodCallHandler { call, result ->
            if (call.method == "join") {
                join(call.arguments as? Map<*, *> ?: emptyMap<String, Any>(), result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun join(a: Map<*, *>, result: MethodChannel.Result) {
        val ssid = (a["ssid"] as? String)?.takeIf { it.isNotEmpty() }
        if (ssid == null) {
            result.success("failed")
            return
        }
        val password = a["password"] as? String ?: ""
        val security = a["security"] as? String ?: "WPA"
        val hidden = a["hidden"] as? Boolean ?: false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || security == "WEP" || pending != null) {
            result.success(openSettings())
            return
        }
        val suggestion = WifiNetworkSuggestion.Builder().setSsid(ssid).setIsHiddenSsid(hidden).apply {
            if (security != "nopass" && password.isNotEmpty()) setWpa2Passphrase(password)
        }.build()
        val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).putParcelableArrayListExtra(
            Settings.EXTRA_WIFI_NETWORK_LIST,
            arrayListOf(suggestion),
        )
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.success(openSettings())
        }
    }

    private fun openSettings(): String = try {
        activity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
        "settings"
    } catch (e: ActivityNotFoundException) {
        "failed"
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST) return
        val result = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            result.success("cancelled")
            return
        }
        val first = data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST)?.firstOrNull()
        result.success(if (first == Settings.ADD_WIFI_RESULT_ADD_OR_UPDATE_FAILED) "failed" else "added")
    }

    private companion object {
        const val REQUEST = 7311
    }
}
