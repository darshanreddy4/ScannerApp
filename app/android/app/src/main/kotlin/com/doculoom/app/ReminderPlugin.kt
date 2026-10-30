package com.doculoom.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Lets Dart schedule document-expiry reminders and ask for the notification permission (Android 13 and newer).
 * Status is "granted", "denied" (the question can still be shown) or "blocked" (only Settings can turn it on).
 */
class ReminderPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val prefs = activity.getSharedPreferences("reminder_access", Context.MODE_PRIVATE)
    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "doculoom/reminders").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "request" -> request(result)
                "schedule" -> {
                    val items = (call.arguments as? List<*>).orEmpty().mapNotNull { item ->
                        val m = item as? Map<*, *> ?: return@mapNotNull null
                        Reminder(
                            (m["id"] as Number).toInt(),
                            (m["at"] as Number).toLong(),
                            m["title"] as? String ?: return@mapNotNull null,
                            m["text"] as? String ?: return@mapNotNull null,
                        )
                    }
                    Reminders.replaceAll(activity, items)
                    result.success(items.size)
                }
                "showNow" -> {
                    val m = call.arguments as? Map<*, *>
                    val title = m?.get("title") as? String
                    val text = m?.get("text") as? String
                    if (m == null || title == null || text == null) {
                        result.success(null)
                    } else {
                        Reminders.show(activity, (m["id"] as Number).toInt(), title, text)
                        result.success(null)
                    }
                }
                "cancelAll" -> {
                    Reminders.cancelAll(activity)
                    result.success(null)
                }
                "openSettings" -> result.success(openSettings())
                "scheduleTest" -> {
                    Reminders.scheduleTest(activity)
                    result.success(true)
                }
                "openBatterySettings" -> result.success(openBatterySettings())
                "openAutostartSettings" -> result.success(openAutostartSettings())
                "maker" -> result.success(Build.MANUFACTURER.lowercase())
                else -> result.notImplemented()
            }
        }
    }

    private fun status(): String {
        if (NotificationManagerCompat.from(activity).areNotificationsEnabled()) return "granted"
        // Before Android 13 notifications are on unless the person switched them off in Settings.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return "blocked"
        val asked = prefs.getBoolean(ASKED, false)
        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.POST_NOTIFICATIONS)
        return if (asked && !canAskAgain) "blocked" else "denied"
    }

    private fun request(result: MethodChannel.Result) {
        val now = status()
        if (now != "denied" || pending != null || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(now)
            return
        }
        pending = result
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
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
        activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
        true
    } catch (e: Exception) {
        false
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    /** The list of apps that the phone may put to sleep; the person picks Doculoom and chooses not to optimise it. */
    private fun openBatterySettings(): Boolean =
        start(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) || openAppDetails()

    private fun openAppDetails(): Boolean =
        start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(android.net.Uri.fromParts("package", activity.packageName, null)))

    /**
     * Several makers keep a separate "autostart" or "background activity" screen that decides whether an app may run alarms and start
     * after a restart. Each screen is tried in turn; the app's own settings page is the fallback.
     */
    private fun openAutostartSettings(): Boolean {
        for ((pkg, cls) in AUTOSTART_SCREENS) {
            if (start(Intent().setClassName(pkg, cls))) return true
        }
        return openAppDetails()
    }

    private companion object {
        val AUTOSTART_SCREENS = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
            "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
        )
        const val REQUEST_CODE = 4712
        const val ASKED = "asked"
    }
}
