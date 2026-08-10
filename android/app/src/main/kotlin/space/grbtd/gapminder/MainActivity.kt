package space.grbtd.gapminder

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import com.istornz.live_activities.LiveActivityManager
import com.istornz.live_activities.LiveActivityManagerHolder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class CustomLiveActivityManager(context: Context) : LiveActivityManager(context) {
    override suspend fun buildNotification(
        notification: Notification.Builder,
        event: String,
        data: Map<String, Any>
    ): Notification {
        val title = data["title"] as? String ?: "Train Service"
        val subtitle = data["subtitle"] as? String ?: ""
        val status = data["status"] as? String ?: ""
        val station = data["stationName"] as? String ?: ""

        val contentList = mutableListOf<String>()
        if (station.isNotEmpty()) contentList.add(station)
        if (subtitle.isNotEmpty()) contentList.add(subtitle)
        if (status.isNotEmpty()) contentList.add(status)

        notification
            .setContentTitle(title)
            .setContentText(contentList.joinToString(" • "))
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)

        return notification.build()
    }
}

class MainActivity : FlutterActivity() {
    private val CHANNEL = "space.grbtd.gapminder/live_activity_service"
    private var methodChannel: MethodChannel? = null

    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val serviceUid = intent?.getStringExtra("serviceUid") ?: ""
            val runDate = intent?.getStringExtra("runDate") ?: ""
            methodChannel?.invokeMethod(
                "onNotificationDismissed",
                mapOf("serviceUid" to serviceUid, "runDate" to runDate)
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LiveActivityManagerHolder.instance = CustomLiveActivityManager(applicationContext)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService", "updateForegroundService" -> {
                    val title = call.argument<String>("title") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val status = call.argument<String>("status") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val operator = call.argument<String>("operator") ?: ""
                    val serviceUid = call.argument<String>("serviceUid") ?: ""
                    val runDate = call.argument<String>("runDate") ?: ""

                    val intent = Intent(this, TrainTrackingForegroundService::class.java).apply {
                        action = TrainTrackingForegroundService.ACTION_START
                        putExtra("title", title)
                        putExtra("subtitle", subtitle)
                        putExtra("status", status)
                        putExtra("stationName", stationName)
                        putExtra("operator", operator)
                        putExtra("serviceUid", serviceUid)
                        putExtra("runDate", runDate)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val intent = Intent(this, TrainTrackingForegroundService::class.java).apply {
                        action = TrainTrackingForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val filter = IntentFilter("space.grbtd.gapminder.NOTIFICATION_DISMISSED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(dismissReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
