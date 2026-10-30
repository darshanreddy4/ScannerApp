package com.doculoom.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Shows a reminder when its alarm goes off. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(Reminders.EXTRA_ID, 0)
        Reminders.show(context, id, intent.getStringExtra(Reminders.EXTRA_TITLE) ?: return, intent.getStringExtra(Reminders.EXTRA_TEXT) ?: return)
        Reminders.forget(context, id)
    }
}

/** Sets the reminders again after the phone restarts or the app is updated. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in BOOT_ACTIONS) Reminders.restore(context)
    }

    private companion object {
        // The QUICKBOOT actions are what some phones (HTC, Xiaomi) send after a fast restart.
        val BOOT_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
    }
}
