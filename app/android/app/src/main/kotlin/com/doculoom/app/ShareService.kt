package com.doculoom.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps the share server alive while the app is minimised or closed. Android would otherwise freeze the app and
 * put Wi-Fi to sleep, and people opening the link would only see "site can't be reached".
 */
class ShareService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        ShareRegistry.listener = { main.post { refresh() } }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A started foreground service must show its notification right away, even if it is about to stop.
        startInForeground(ShareRegistry.list())
        if (intent?.action == ACTION_STOP_ALL) ShareRegistry.stopAll()
        refresh()
        return START_NOT_STICKY
    }

    // Android 15 caps data-sync services at about 6 hours a day; it must stop at once or the system ends the app.
    override fun onTimeout(startId: Int, fgsType: Int) {
        ShareRegistry.stopAll()
        releaseLocks()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        ShareRegistry.listener = null
        releaseLocks()
        super.onDestroy()
    }

    private fun refresh() {
        val live = ShareRegistry.list()
        if (live.isEmpty()) {
            releaseLocks()
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        acquireLocks(live.maxOf { it.server.expiresAt })
        startInForeground(live)
    }

    private fun startInForeground(live: List<ShareRegistry.Entry>) {
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(live), type)
    }

    private fun notification(live: List<ShareRegistry.Entry>): Notification {
        val open = PendingIntent.getActivity(
            this, 0, packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, ShareService::class.java).setAction(ACTION_STOP_ALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_share)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, if (live.size > 1) "Stop all" else "Stop sharing", stop)
        if (live.isEmpty()) return builder.setContentTitle("Doculoom").setContentText("Sharing has ended").build()

        val downloads = live.sumOf { it.server.downloads }
        val soonest = live.minOf { it.server.expiresAt }
        builder
            .setContentTitle(if (live.size == 1) "Sharing ${live[0].fileName}" else "Sharing ${live.size} files")
            .setContentText("${if (downloads == 1) "1 download" else "$downloads downloads"} so far. Tap to open Doculoom.")
            .setWhen(soonest)
            .setShowWhen(true)
            .setUsesChronometer(true)
        if (Build.VERSION.SDK_INT >= 24) builder.setChronometerCountDown(true)
        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "File sharing", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shown while a file is shared by QR code, so the link keeps working."
            setShowBadge(false)
        })
    }

    private fun acquireLocks(until: Long) {
        releaseLocks()
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        wifiLock = wifi?.createWifiLock(
            if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else @Suppress("DEPRECATION") WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "doculoom:share",
        )?.apply {
            setReferenceCounted(false)
            acquire()
        }
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val timeout = (until - System.currentTimeMillis()).coerceIn(60_000L, 6L * 3_600_000L) + 60_000L
        wakeLock = power?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "doculoom:share")?.apply {
            setReferenceCounted(false)
            acquire(timeout)
        }
    }

    private fun releaseLocks() {
        runCatching { if (wifiLock?.isHeld == true) wifiLock?.release() }
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
        wifiLock = null
        wakeLock = null
    }

    companion object {
        const val ACTION_STOP_ALL = "com.doculoom.app.STOP_SHARING"
        private const val CHANNEL_ID = "sharing"
        private const val NOTIFICATION_ID = 4101
    }
}
