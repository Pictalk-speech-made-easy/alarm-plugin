package org.pictalk.plugin.alarm

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File
import java.util.*
import java.util.concurrent.ConcurrentHashMap


class AlarmService(private val context: Context) {

    private val alarmManager: AlarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val audioManager: AudioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
        vibratorManager.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    private val notificationManager: NotificationManagerCompat = NotificationManagerCompat.from(context)

    private val prefs: SharedPreferences = context.getSharedPreferences("alarm_plugin", Context.MODE_PRIVATE)
    private val gson = Gson()

    private val activeAlarms = ConcurrentHashMap<Int, AlarmRuntimeInfo>()
    private val mediaPlayers = ConcurrentHashMap<Int, MediaPlayer>()

    companion object {
        const val CHANNEL_ID = "alarm_channel"
        const val FOREGROUND_SERVICE_ID = 1001
        const val REQUEST_CODE_BASE = 1000
        private const val ALARM_STORAGE_KEY = "stored_alarms"
        private const val WARNING_NOTIFICATION_TITLE_KEY = "warning_title"
        private const val WARNING_NOTIFICATION_BODY_KEY = "warning_body"
    }

    data class AlarmRuntimeInfo(
        val settings: AlarmSettings,
        val mediaPlayer: MediaPlayer? = null,
        val isRinging: Boolean = false,
        val originalVolume: Int? = null
    )

    fun init() {
        createNotificationChannel()
        loadStoredAlarms()
    }

    fun setAlarm(alarmSettings: AlarmSettings) {
        // Store alarm persistently
        storeAlarm(alarmSettings)

        // Schedule with AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("alarmId", alarmSettings.id)
            putExtra("alarmSettings", gson.toJson(alarmSettings))
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE_BASE + alarmSettings.id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = alarmSettings.dateTime.time

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerTime,
            pendingIntent
        )
    }

    fun stopAlarm(alarmId: Int) {
        // Cancel the scheduled alarm
        val intent = Intent(context, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE_BASE + alarmId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )

        pendingIntent?.let {
            alarmManager.cancel(it)
            it.cancel()
        }

        // Stop any currently ringing alarm
        stopRingingAlarm(alarmId)

        // Remove from storage
        removeStoredAlarm(alarmId)
    }

    fun stopAll() {
        val alarms = getAlarms()
        for (alarm in alarms) {
            stopAlarm(alarm.id)
        }
    }

    fun isRinging(alarmId: Int?): Boolean {
        return if (alarmId != null) {
            activeAlarms[alarmId]?.isRinging ?: false
        } else {
            activeAlarms.values.any { it.isRinging }
        }
    }

    fun getAlarms(): List<AlarmSettings> {
        val alarmsJson = prefs.getString(ALARM_STORAGE_KEY, "[]") ?: "[]"
        val type = object : TypeToken<List<AlarmSettings>>() {}.type
        return gson.fromJson(alarmsJson, type) ?: emptyList()
    }

    fun setWarningNotificationOnKill(title: String, body: String) {
        prefs.edit()
            .putString(WARNING_NOTIFICATION_TITLE_KEY, title)
            .putString(WARNING_NOTIFICATION_BODY_KEY, body)
            .apply()
    }

    fun checkAlarms() {
        val currentTime = System.currentTimeMillis()
        val alarms = getAlarms().toMutableList()
        var alarmsChanged = false

        val iterator = alarms.iterator()
        while (iterator.hasNext()) {
            val alarm = iterator.next()
            if (alarm.dateTime.time <= currentTime) {
                // Alarm time has passed, remove it
                iterator.remove()
                alarmsChanged = true

                // Check if this alarm should be ringing
                if (alarm.dateTime.time > currentTime - 60000) { // Within last minute
                    startRingingAlarm(alarm)
                }
            } else {
                // Reschedule future alarms
                setAlarm(alarm)
            }
        }

        if (alarmsChanged) {
            storeAlarms(alarms)
        }
    }

    // Called by AlarmReceiver when alarm triggers
    fun onAlarmTriggered(alarmId: Int, alarmSettingsJson: String) {
        val alarmSettings = gson.fromJson(alarmSettingsJson, AlarmSettings::class.java)
        startRingingAlarm(alarmSettings)
        removeStoredAlarm(alarmId)
    }

    private fun startRingingAlarm(alarmSettings: AlarmSettings) {
        if (!alarmSettings.allowAlarmOverlap && activeAlarms.values.any { it.isRinging }) {
            return
        }

        try {
            // Set volume if specified
            val originalVolume = if (alarmSettings.volumeSettings.volume != null) {
                val current = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                val targetVolume = (alarmSettings.volumeSettings.volume * maxVolume).toInt()
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, targetVolume, 0)
                current
            } else null

            // Start media player
            val mediaPlayer = createMediaPlayer(alarmSettings)
            mediaPlayers[alarmSettings.id] = mediaPlayer

            // Start vibration
            if (alarmSettings.vibrate) {
                startVibration()
            }

            // Show notification
            showAlarmNotification(alarmSettings)

            // Update runtime info
            activeAlarms[alarmSettings.id] = AlarmRuntimeInfo(
                settings = alarmSettings,
                mediaPlayer = mediaPlayer,
                isRinging = true,
                originalVolume = originalVolume
            )

            // Handle fade effects
            handleVolumeEffects(alarmSettings, mediaPlayer)

            mediaPlayer.start()

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopRingingAlarm(alarmId: Int) {
        val runtimeInfo = activeAlarms[alarmId] ?: return

        // Stop media player
        mediaPlayers[alarmId]?.let { mediaPlayer ->
            if (mediaPlayer.isPlaying) {
                mediaPlayer.stop()
            }
            mediaPlayer.release()
            mediaPlayers.remove(alarmId)
        }

        // Stop vibration
        vibrator.cancel()

        // Restore original volume
        runtimeInfo.originalVolume?.let { originalVolume ->
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, originalVolume, 0)
        }

        // Cancel notification
        notificationManager.cancel(alarmId)

        // Remove from active alarms
        activeAlarms.remove(alarmId)
    }

    private fun createMediaPlayer(alarmSettings: AlarmSettings): MediaPlayer {
        val mediaPlayer = MediaPlayer()

        val uri = if (alarmSettings.assetAudioPath.startsWith("android.resource://")) {
            Uri.parse(alarmSettings.assetAudioPath)
        } else if (alarmSettings.assetAudioPath.startsWith("public/")) {
            // Handle Capacitor public assets
            val assetPath = alarmSettings.assetAudioPath
            Uri.parse("file:///android_asset/$assetPath")
        } else {
            // Handle absolute paths or document directory files
            Uri.fromFile(File(alarmSettings.assetAudioPath))
        }

        mediaPlayer.setDataSource(context, uri)
        mediaPlayer.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
        )
        mediaPlayer.isLooping = alarmSettings.loopAudio
        mediaPlayer.prepare()

        return mediaPlayer
    }

    private fun startVibration() {
        val pattern = longArrayOf(0, 1000, 1000) // Vibrate for 1 second, pause 1 second, repeat

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
    }

    private fun showAlarmNotification(alarmSettings: AlarmSettings) {
        val stopIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = "STOP_ALARM"
            putExtra("alarmId", alarmSettings.id)
        }

        val stopPendingIntent = PendingIntent.getBroadcast(
            context,
            alarmSettings.id,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(getNotificationIcon(alarmSettings.notificationSettings.icon))
            .setContentTitle(alarmSettings.notificationSettings.title)
            .setContentText(alarmSettings.notificationSettings.body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(stopPendingIntent, alarmSettings.androidFullScreenIntent)

        // Add stop button if specified
        alarmSettings.notificationSettings.stopButton?.let { stopButtonText ->
            notificationBuilder.addAction(
                android.R.drawable.ic_media_pause,
                stopButtonText,
                stopPendingIntent
            )
        }

        // Set icon color if specified (Android only)
        alarmSettings.notificationSettings.iconColor?.let { colorHex ->
            try {
                val color = android.graphics.Color.parseColor(colorHex)
                notificationBuilder.setColor(color)
            } catch (e: Exception) {
                // Ignore invalid color
            }
        }

        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            try {
                notificationManager.notify(alarmSettings.id, notificationBuilder.build())
            } catch (e: SecurityException) {
                e.printStackTrace()
            }
        }
    }

    private fun handleVolumeEffects(alarmSettings: AlarmSettings, mediaPlayer: MediaPlayer) {
        val volumeSettings = alarmSettings.volumeSettings

        // Handle fade duration
        volumeSettings.fadeDuration?.let { fadeDuration ->
            if (fadeDuration > 0) {
                // Implement volume fade
                val handler = android.os.Handler(android.os.Looper.getMainLooper())
                val startVolume = 0f
                val targetVolume = volumeSettings.volume ?: 1f
                val steps = 20
                val stepDuration = fadeDuration / steps

                for (i in 0..steps) {
                    val volume = startVolume + (targetVolume - startVolume) * (i.toFloat() / steps)
                    handler.postDelayed({
                        if (mediaPlayer.isPlaying) {
                            mediaPlayer.setVolume(volume, volume)
                        }
                    }, (i * stepDuration).toLong())
                }
            }
        }

        // Handle custom fade steps
        if (volumeSettings.fadeSteps.isNotEmpty()) {
            val handler = android.os.Handler(android.os.Looper.getMainLooper())
            volumeSettings.fadeSteps.forEach { step ->
                handler.postDelayed({
                    if (mediaPlayer.isPlaying) {
                        mediaPlayer.setVolume(step.volume, step.volume)
                    }
                }, step.time.toLong())
            }
        }

        // Handle volume enforcement
        if (volumeSettings.volumeEnforced && volumeSettings.volume != null) {
            // Start a background task to monitor and enforce volume
            enforceVolume(alarmSettings)
        }
    }

    private fun enforceVolume(alarmSettings: AlarmSettings) {
        val targetVolume = alarmSettings.volumeSettings.volume ?: return
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val targetVolumeInt = (targetVolume * maxVolume).toInt()

        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val checkVolumeRunnable = object : Runnable {
            override fun run() {
                if (activeAlarms[alarmSettings.id]?.isRinging == true) {
                    val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                    if (currentVolume != targetVolumeInt) {
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, targetVolumeInt, 0)
                    }
                    handler.postDelayed(this, 1000) // Check every second
                }
            }
        }
        handler.post(checkVolumeRunnable)
    }

    private fun getNotificationIcon(iconName: String?): Int {
        return if (iconName != null) {
            val resourceId = context.resources.getIdentifier(iconName, "drawable", context.packageName)
            if (resourceId != 0) resourceId else android.R.drawable.ic_dialog_alert
        } else {
            android.R.drawable.ic_dialog_alert
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Alarm Notifications"
            val descriptionText = "Notifications for alarm alerts"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(true)
                enableLights(true)
                enableVibration(true)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun storeAlarm(alarmSettings: AlarmSettings) {
        val alarms = getAlarms().toMutableList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            alarms.removeIf { it.id == alarmSettings.id }
        } else {
            alarms.removeAll { it.id == alarmSettings.id }
        }
        alarms.add(alarmSettings)
        storeAlarms(alarms)
    }

    private fun removeStoredAlarm(alarmId: Int) {
        val alarms = getAlarms().toMutableList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            alarms.removeIf { it.id == alarmId }
        } else {
            alarms.removeAll { it.id == alarmId }
        }
        storeAlarms(alarms)
    }

    private fun storeAlarms(alarms: List<AlarmSettings>) {
        val alarmsJson = gson.toJson(alarms)
        prefs.edit().putString(ALARM_STORAGE_KEY, alarmsJson).apply()
    }

    private fun loadStoredAlarms() {
        // This is called during init to restore alarms after app restart
        checkAlarms()
    }
}