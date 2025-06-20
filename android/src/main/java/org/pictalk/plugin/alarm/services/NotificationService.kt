package org.pictalk.plugin.alarm.services

import android.annotation.SuppressLint
import org.pictalk.plugin.alarm.models.NotificationSettings
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import com.getcapacitor.plugin.util.AssetUtil
import org.pictalk.plugin.alarm.R
import org.pictalk.plugin.alarm.alarm.AlarmReceiver

class NotificationHandler(private val context: Context) {
    companion object {
        private const val CHANNEL_ID = "alarm_plugin_channel"
        private const val CHANNEL_NAME = "Alarm Notification"
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)
                enableLights(true)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun getLargeIcon(imagePath: String): Bitmap? {
        return try {
            val assets = AssetUtil.getInstance(context)
            val uri = assets.parse(imagePath)
            if (uri != Uri.EMPTY) {
                val bitmap = assets.getIconFromUri(uri)
                // Scale for big image (notification expanded view)
                Bitmap.createScaledBitmap(bitmap, 128, 128, true)
            } else {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    // We need to use [Resources.getIdentifier] because resources are registered by the app.
    @SuppressLint("DiscouragedApi")
    fun buildNotification(
        notificationSettings: NotificationSettings,
        fullScreen: Boolean,
        pendingIntent: PendingIntent,
        fullScreenIntent: PendingIntent? = null,
        alarmId: Int
    ): Notification {
        val defaultIconResId =
            context.packageManager.getApplicationInfo(context.packageName, 0).icon

        val iconResId = if (notificationSettings.icon != null) {
            val resId = context.resources.getIdentifier(
                notificationSettings.icon,
                "drawable",
                context.packageName
            )
            if (resId != 0) resId else defaultIconResId
        } else {
            defaultIconResId
        }

        val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_ALARM_STOP
            putExtra("id", alarmId)
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(iconResId)
            .setContentTitle(notificationSettings.title)
            .setContentText(notificationSettings.body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(false)
            .setWhen(0)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setDeleteIntent(stopPendingIntent)
            .setSound(null)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (fullScreen) {
            notificationBuilder.setFullScreenIntent(fullScreenIntent, true)
        }

        notificationSettings.let {
            if (it.stopButton != null) {
                notificationBuilder.addAction(R.drawable.ic_action_dismiss, it.stopButton, stopPendingIntent)
            }

            if (it.iconColor != null) {
                notificationBuilder.setColor(it.iconColor)
            }

            if (it.image != null) {
                val largeIcon = getLargeIcon(it.image)
                if (largeIcon != null) {
                    notificationBuilder.setLargeIcon(largeIcon)
                }
            }
        }

        return notificationBuilder.build()
    }
}