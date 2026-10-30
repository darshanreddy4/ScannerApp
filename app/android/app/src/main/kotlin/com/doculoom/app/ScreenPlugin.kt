package com.doculoom.app

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Full brightness and a screen that stays on while a card code is shown to a scanner. */
class ScreenPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "doculoom/screen").setMethodCallHandler { call, result ->
            if (call.method == "boost") {
                val on = call.arguments as? Boolean ?: false
                activity.runOnUiThread {
                    val window = activity.window
                    val attrs = window.attributes
                    attrs.screenBrightness = if (on) 1f else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = attrs
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
