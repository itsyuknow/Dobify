package com.yuknow.ironly

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                val channelId = "ironxpress_notifications"
                val channelName = "Dobify Notifications"
                val importance = NotificationManager.IMPORTANCE_HIGH

                val channel = NotificationChannel(channelId, channelName, importance).apply {
                    description = "Notifications for Dobify app"
                    enableLights(true)
                    enableVibration(true)
                    setShowBadge(true)
                }

                notificationManager.createNotificationChannel(channel)

                val defaultChannel = NotificationChannel(
                    "default",
                    "Default Notifications",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Default notification channel"
                }

                notificationManager.createNotificationChannel(defaultChannel)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}