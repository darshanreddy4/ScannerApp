package com.doculoom.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** The home-screen widget: Scan, ID photo, Read PDF and QR scan, one tap each. */
class QuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick)
            views.setOnClickPendingIntent(R.id.qa_scan, QuickActions.pendingIntent(context, QuickActions.SCAN))
            views.setOnClickPendingIntent(R.id.qa_id, QuickActions.pendingIntent(context, QuickActions.ID_PHOTO))
            views.setOnClickPendingIntent(R.id.qa_pdf, QuickActions.pendingIntent(context, QuickActions.READ_PDF))
            views.setOnClickPendingIntent(R.id.qa_qr, QuickActions.pendingIntent(context, QuickActions.QR_SCAN))
            manager.updateAppWidget(id, views)
        }
    }
}
