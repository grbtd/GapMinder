package space.grbtd.gapminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

class NotificationDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceUid = intent.getStringExtra("serviceUid") ?: ""
        val runDate = intent.getStringExtra("runDate") ?: ""
        val dismissIntent = Intent("space.grbtd.gapminder.NOTIFICATION_DISMISSED").apply {
            putExtra("serviceUid", serviceUid)
            putExtra("runDate", runDate)
        }
        context.sendBroadcast(dismissIntent)
    }
}

class TrainTrackingForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "live_activities"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra("title") ?: "Tracking Train Service"
        val subtitle = intent?.getStringExtra("subtitle") ?: ""
        val status = intent?.getStringExtra("status") ?: ""
        val station = intent?.getStringExtra("stationName") ?: ""
        val operator = intent?.getStringExtra("operator") ?: ""
        val serviceUid = intent?.getStringExtra("serviceUid") ?: ""
        val runDate = intent?.getStringExtra("runDate") ?: ""

        createNotificationChannel()

        // Content tap intent (open app)
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Delete intent (swipe away)
        val deleteIntent = Intent(this, NotificationDismissReceiver::class.java).apply {
            putExtra("serviceUid", serviceUid)
            putExtra("runDate", runDate)
        }
        val deletePendingIntent = PendingIntent.getBroadcast(
            this,
            serviceUid.hashCode(),
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Stop tracking action intent
        val stopIntent = Intent(this, TrainTrackingForegroundService::class.java).apply {
            setAction(ACTION_STOP)
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val shortSummaryList = mutableListOf<String>()
        if (station.isNotEmpty()) shortSummaryList.add(station)
        if (subtitle.isNotEmpty()) shortSummaryList.add(subtitle)
        if (status.isNotEmpty()) shortSummaryList.add(status)
        val shortContentText = shortSummaryList.joinToString(" • ")

        val expandedTextBuilder = StringBuilder()
        if (station.isNotEmpty()) expandedTextBuilder.append("Station: ").append(station).append("\n")
        if (subtitle.isNotEmpty()) expandedTextBuilder.append(subtitle).append("\n")
        if (status.isNotEmpty()) expandedTextBuilder.append("Status: ").append(status).append("\n")
        if (operator.isNotEmpty()) expandedTextBuilder.append("Operator: ").append(operator)
        val expandedText = expandedTextBuilder.toString().trim()

        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        notificationBuilder
            .setContentTitle(title)
            .setContentText(shortContentText)
            .setSubText("Live Update")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(openAppPendingIntent)
            .setDeleteIntent(deletePendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && expandedText.isNotEmpty()) {
            notificationBuilder.setStyle(
                Notification.BigTextStyle().bigText(expandedText)
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val stopAction = Notification.Action.Builder(
                null,
                "Stop Tracking",
                stopPendingIntent
            ).build()
            notificationBuilder.addAction(stopAction)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            notificationBuilder.setCategory(Notification.CATEGORY_STATUS)
            notificationBuilder.setVisibility(Notification.VISIBILITY_PUBLIC)
        }

        val notification = notificationBuilder.build()

        startForeground(NOTIFICATION_ID, notification)

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live Train Updates",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing live update notifications for tracked train services"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager?.createNotificationChannel(channel)
        }
    }
}
