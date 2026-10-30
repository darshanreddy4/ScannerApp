package com.doculoom.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * One-tap entries to the app: home-screen shortcuts, the widget and the quick-settings tiles all start MainActivity with
 * an action id, which Dart turns into the right screen.
 */
object QuickActions {
    const val ACTION = "com.doculoom.app.QUICK_ACTION"
    const val EXTRA = "doculoom_quick"

    const val SCAN = "scan"
    const val ID_PHOTO = "id_photo"
    const val READ_PDF = "read_pdf"
    const val QR_SCAN = "qr_scan"

    fun intent(context: Context, id: String): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    /** Each action has its own request code, because pending intents that differ only in extras would be mixed up. */
    fun pendingIntent(context: Context, id: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            id.hashCode(),
            intent(context, id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
}
