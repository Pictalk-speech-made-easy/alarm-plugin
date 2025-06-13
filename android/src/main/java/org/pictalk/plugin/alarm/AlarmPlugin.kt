package org.pictalk.plugin.alarm

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

@CapacitorPlugin(name = "Alarm")
class AlarmPlugin : Plugin() {
    
    private lateinit var alarmManager: AlarmService
    private val CHANNEL_ID = "alarm_channel"
    private val REQUEST_CODE_BASE = 1000
    
    override fun load() {
        super.load()
        alarmManager = AlarmService(context)
        createNotificationChannel()
    }
    
    @PluginMethod
    fun init(call: PluginCall) {
        try {
            alarmManager.init()
            call.resolve()
        } catch (e: Exception) {
            call.reject("Failed to initialize alarm service", e)
        }
    }
    
    @PluginMethod
    fun setAlarm(call: PluginCall) {
        try {
            val alarmSettingsObj = call.getObject("alarmSettings")
                ?: return call.reject("alarmSettings is required")
            
            val alarmSettings = parseAlarmSettings(alarmSettingsObj)
            alarmManager.setAlarm(alarmSettings)
            call.resolve()
        } catch (e: Exception) {
            call.reject("Failed to set alarm", e)
        }
    }
    
    @PluginMethod
    fun stopAlarm(call: PluginCall) {
        try {
            val alarmId = call.getInt("alarmId") ?: return call.reject("alarmId is required")
            alarmManager.stopAlarm(alarmId)
            call.resolve()
        } catch (e: Exception) {
            call.reject("Failed to stop alarm", e)
        }
    }
    
    @PluginMethod
    fun stopAll(call: PluginCall) {
        try {
            alarmManager.stopAll()
            call.resolve()
        } catch (e: Exception) {
            call.reject("Failed to stop all alarms", e)
        }
    }
    
    @PluginMethod
    fun isRinging(call: PluginCall) {
        try {
            val alarmId = call.getInt("alarmId")
            val isRinging = alarmManager.isRinging(alarmId)
            
            val result = JSObject()
            result.put("isRinging", isRinging)
            call.resolve(result)
        } catch (e: Exception) {
            call.reject("Failed to check ringing status", e)
        }
    }
    
    @PluginMethod
    fun getAlarms(call: PluginCall) {
        try {
            val alarms = alarmManager.getAlarms()
            val alarmsArray = JSONArray()
            
            for (alarm in alarms) {
                alarmsArray.put(alarmSettingsToJson(alarm))
            }
            
            val result = JSObject()
            result.put("alarms", alarmsArray)
            call.resolve(result)
        } catch (e: Exception) {
            call.reject("Failed to get alarms", e)
        }
    }
    
    @PluginMethod
    fun setWarningNotificationOnKill(call: PluginCall) {
        try {
            val title = call.getString("title") ?: return call.reject("title is required")
            val body = call.getString("body") ?: return call.reject("body is required")
            
            alarmManager.setWarningNotificationOnKill(title, body)
            call.resolve()
        } catch (e: Exception) {
            call.reject("Failed to set warning notification", e)
        }
    }
    
    @PluginMethod
    fun checkAlarm(call: PluginCall) {
        try {
            alarmManager.checkAlarms()
            call.resolve()
        } catch (e: Exception) {
            call.reject("Failed to check alarms", e)
        }
    }
    
    private fun parseAlarmSettings(obj: JSObject): AlarmSettings {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.getDefault())
        
        return AlarmSettings(
            id = obj.getInteger("id") ?: throw IllegalArgumentException("id is required"),
            dateTime = dateFormat.parse(obj.getString("dateTime") ?: throw IllegalArgumentException("dateTime is required"))
                ?: throw IllegalArgumentException("Invalid dateTime format"),
            assetAudioPath = obj.getString("assetAudioPath") ?: throw IllegalArgumentException("assetAudioPath is required"),
            volumeSettings = parseVolumeSettings(obj.getJSObject("volumeSettings") ?: JSObject()),
            notificationSettings = parseNotificationSettings(obj.getJSObject("notificationSettings") ?: JSObject()),
            loopAudio = obj.getBoolean("loopAudio", true) ?: true,
            vibrate = obj.getBoolean("vibrate", true) ?: true,
            warningNotificationOnKill = obj.getBoolean("warningNotificationOnKill", true) ?: true,
            androidFullScreenIntent = obj.getBoolean("androidFullScreenIntent", true) ?: true,
            allowAlarmOverlap = obj.getBoolean("allowAlarmOverlap", false) ?: false,
            androidStopAlarmOnTermination = obj.getBoolean("androidStopAlarmOnTermination", true) ?: true,
            payload = obj.getString("payload")
        )
    }
    
    private fun parseVolumeSettings(obj: JSObject): VolumeSettings {
        val fadeSteps = mutableListOf<VolumeFadeStep>()
        val fadeStepsArray = obj.getJSONArray("fadeSteps")

        for (i in 0 until fadeStepsArray.length()) {
            val step = fadeStepsArray.getJSONObject(i)
            fadeSteps.add(
                VolumeFadeStep(
                    time = step.getInt("time"),
                    volume = step.getDouble("volume").toFloat()
                )
            )
        }
        
        return VolumeSettings(
            volume = obj.getDouble("volume").toFloat(),
            fadeDuration = obj.getInteger("fadeDuration"),
            fadeSteps = fadeSteps,
            volumeEnforced = obj.getBoolean("volumeEnforced", false) ?: false
        )
    }
    
    private fun parseNotificationSettings(obj: JSObject): NotificationSettings {
        return NotificationSettings(
            title = obj.getString("title") ?: "Alarm",
            body = obj.getString("body") ?: "Your alarm is ringing",
            stopButton = obj.getString("stopButton"),
            icon = obj.getString("icon"),
            iconColor = obj.getString("iconColor")
        )
    }
    
    private fun alarmSettingsToJson(alarm: AlarmSettings): JSONObject {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.getDefault())
        
        return JSONObject().apply {
            put("id", alarm.id)
            put("dateTime", dateFormat.format(alarm.dateTime))
            put("assetAudioPath", alarm.assetAudioPath)
            put("loopAudio", alarm.loopAudio)
            put("vibrate", alarm.vibrate)
            put("warningNotificationOnKill", alarm.warningNotificationOnKill)
            put("androidFullScreenIntent", alarm.androidFullScreenIntent)
            put("allowAlarmOverlap", alarm.allowAlarmOverlap)
            put("androidStopAlarmOnTermination", alarm.androidStopAlarmOnTermination)
            alarm.payload?.let { put("payload", it) }
            
            // Add volume settings
            put("volumeSettings", JSONObject().apply {
                alarm.volumeSettings.volume?.let { put("volume", it) }
                alarm.volumeSettings.fadeDuration?.let { put("fadeDuration", it) }
                put("volumeEnforced", alarm.volumeSettings.volumeEnforced)
                put("fadeSteps", JSONArray().apply {
                    alarm.volumeSettings.fadeSteps.forEach { step ->
                        put(JSONObject().apply {
                            put("time", step.time)
                            put("volume", step.volume)
                        })
                    }
                })
            })
            
            // Add notification settings
            put("notificationSettings", JSONObject().apply {
                put("title", alarm.notificationSettings.title)
                put("body", alarm.notificationSettings.body)
                alarm.notificationSettings.stopButton?.let { put("stopButton", it) }
                alarm.notificationSettings.icon?.let { put("icon", it) }
                alarm.notificationSettings.iconColor?.let { put("iconColor", it) }
            })
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
            }
            
            val notificationManager: NotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    // Method to be called from AlarmReceiver when alarm triggers
    fun onAlarmRing(alarmId: Int) {
        val data = JSObject()
        data.put("alarmId", alarmId)
        notifyListeners("alarmRang", data)
    }
    
    // Method to be called when alarm stops
    fun onAlarmStop(alarmId: Int) {
        val data = JSObject()
        data.put("alarmId", alarmId)
        notifyListeners("alarmStopped", data)
    }
}

// Data classes
data class AlarmSettings(
    val id: Int,
    val dateTime: Date,
    val assetAudioPath: String,
    val volumeSettings: VolumeSettings,
    val notificationSettings: NotificationSettings,
    val loopAudio: Boolean = true,
    val vibrate: Boolean = true,
    val warningNotificationOnKill: Boolean = true,
    val androidFullScreenIntent: Boolean = true,
    val allowAlarmOverlap: Boolean = false,
    val androidStopAlarmOnTermination: Boolean = true,
    val payload: String? = null
)

data class VolumeSettings(
    val volume: Float? = null,
    val fadeDuration: Int? = null,
    val fadeSteps: List<VolumeFadeStep> = emptyList(),
    val volumeEnforced: Boolean = false
)

data class VolumeFadeStep(
    val time: Int,
    val volume: Float
)

data class NotificationSettings(
    val title: String,
    val body: String,
    val stopButton: String? = null,
    val icon: String? = null,
    val iconColor: String? = null
)