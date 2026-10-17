package com.example.pacegasus

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pacegasus/run_tracking")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        prepareRunChannel()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (notificationResult != null) {
                                result.success(false)
                            } else {
                                notificationResult = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
                            }
                        } else {
                            result.success(notificationsEnabled())
                        }
                    }
                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, RUN_CHANNEL)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepareRunChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Use geolocator_android 4.6.2's channel so the permission/settings
            // check can run before tracking starts. Android promotes its FGS
            // notification to LOW unless the user has disabled this channel.
            if (manager.getNotificationChannel(RUN_CHANNEL) == null) {
                val channel = NotificationChannel(RUN_CHANNEL, "การติดตามการวิ่ง", NotificationManager.IMPORTANCE_LOW)
                channel.description = "แจ้งว่าการวิ่งยังทำงานเมื่อดับหน้าจอหรือสลับแอป"
                channel.setShowBadge(false)
                channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun notificationsEnabled(): Boolean {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(RUN_CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) {
            notificationResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && notificationsEnabled())
            notificationResult = null
        }
    }

    override fun onDestroy() {
        notificationResult?.success(false)
        notificationResult = null
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_REQUEST = 7724
        private const val RUN_CHANNEL = "geolocator_channel_01"
    }
}
