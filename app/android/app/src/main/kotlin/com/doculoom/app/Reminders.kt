package com.doculoom.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

/** One notification to show at [at] (milliseconds since 1970). */
data class Reminder(val id: Int, val at: Long, val title: String, val text: String)

/**
 * Keeps the document-expiry reminders: remembers them, sets one alarm for each, and shows them.
 * The list is saved so the alarms can be set again after the phone restarts.
 */
object Reminders {
    private const val PREFS = "reminders"
    private const val KEY = "list"
    const val CHANNEL = "expiry_reminders"
    const val EXTRA_ID = "id"
    private const val MISSED_MS = 24L * 60 * 60 * 1000
    private const val TEST_ID = 7
    private const val TEST_DELAY_MS = 2L * 60 * 1000
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"

    private fun intentFor(context: Context, r: Reminder) = Intent(context, ReminderReceiver::class.java)
        .putExtra(EXTRA_ID, r.id)
        .putExtra(EXTRA_TITLE, r.title)
        .putExtra(EXTRA_TEXT, r.text)

    private fun pending(context: Context, r: Reminder): PendingIntent =
        PendingIntent.getBroadcast(context, r.id, intentFor(context, r), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun load(context: Context): List<Reminder> {
        val text = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(text)
            (0 until array.length()).map {
                val o = array.getJSONObject(it)
                Reminder(o.getInt("id"), o.getLong("at"), o.getString("title"), o.getString("text"))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun save(context: Context, list: List<Reminder>) {
        val array = JSONArray()
        list.forEach { array.put(JSONObject().put("id", it.id).put("at", it.at).put("title", it.title).put("text", it.text)) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, array.toString()).apply()
    }

    private fun cancelAlarms(context: Context, list: List<Reminder>) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        list.forEach { alarms.cancel(pending(context, it)) }
    }

    private fun setAlarms(context: Context, list: List<Reminder>) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        list.filter { it.at > now }.forEach {
            // Not exact: a reminder a few minutes late is fine, and it needs no special permission.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it.at, pending(context, it))
        }
    }

    /** Replaces every reminder with [list]. */
    fun replaceAll(context: Context, list: List<Reminder>) {
        cancelAlarms(context, load(context))
        val future = list.filter { it.at > System.currentTimeMillis() }
        save(context, future)
        setAlarms(context, future)
    }

    fun cancelAll(context: Context) = replaceAll(context, emptyList())

    /**
     * After a restart or an app update the alarms are gone, so they are set again. A reminder that came due while the phone was off
     * is shown now, if it is less than a day late.
     */
    fun restore(context: Context) {
        val now = System.currentTimeMillis()
        val (due, ahead) = load(context).partition { it.at <= now }
        due.filter { now - it.at <= MISSED_MS }.forEach { show(context, it.id, it.title, it.text) }
        if (due.isNotEmpty()) save(context, ahead)
        setAlarms(context, ahead)
    }

    /** A shown reminder is dropped from the saved list so a restart cannot show it twice. */
    fun forget(context: Context, id: Int) {
        val list = load(context)
        if (list.any { it.id == id }) save(context, list.filter { it.id != id })
    }

    /** One alarm a couple of minutes from now, to let the person see that their phone shows reminders when the app is closed. */
    fun scheduleTest(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val test = Reminder(TEST_ID, System.currentTimeMillis() + TEST_DELAY_MS, "Test reminder", "Doculoom reminders reach this phone while the app is closed.")
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, test.at, pending(context, test))
    }

    fun show(context: Context, id: Int, title: String, text: String) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.let { PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(open)
            // Names of documents stay off the lock screen unless the person chose to show them.
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
        manager.notify(id, notification)
    }
}
