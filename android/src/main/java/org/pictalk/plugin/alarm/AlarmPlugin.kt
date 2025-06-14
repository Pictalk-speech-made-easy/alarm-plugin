package org.pictalk.plugin.alarm

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import androidx.annotation.Nullable
import androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.pictalk.plugin.alarm.alarm.AlarmReceiver
import org.pictalk.plugin.alarm.alarm.AlarmService
import org.pictalk.plugin.alarm.models.AlarmSettings
import org.pictalk.plugin.alarm.services.AlarmStorage
import org.pictalk.plugin.alarm.services.NotificationOnKillService

@CapacitorPlugin(name = "Alarm")
class AlarmPlugin : Plugin() {
    companion object {
        private const val TAG = "AlarmPlugin"
        const val ERROR_UNKNOWN_ERROR = "An unknown error has occurred."
        const val ERROR_INVALID_ALARM_SETTINGS = "Invalid alarm settings provided."
        const val ERROR_ALARM_NOT_FOUND = "Alarm not found."

        var instance: AlarmPlugin? = null
    }

    private val alarmIds: MutableList<Int> = mutableListOf()
    private var notificationOnKillTitle: String = "Your alarms may not ring"
    private var notificationOnKillBody: String =
        "You killed the app. Please reopen so your alarms can be rescheduled."

    private var implementation: AlarmStorage? = null

    override fun load() {
        implementation = AlarmStorage(context)
        instance = this
    }

    @PluginMethod
    override fun checkPermissions(call: PluginCall) {
        val notificationState = getNotificationPermissionState()

        val result = JSObject()
        result.put("notifications", notificationState)
        call.resolve(result)
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ requires explicit notification permission
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                // Permission already granted
                checkPermissions(call)
            } else {
                // Save the call to resolve it later in the permission callback
                bridge.saveCall(call)
                requestPermissionForAlias("notifications", call, "checkPermissionsResult")
            }
        } else {
            // For Android 12 and below, notifications are enabled by default
            // but we still need to check if notifications are disabled in system settings
            checkPermissions(call)
        }
    }

    @PluginMethod
    fun setAlarm(call: PluginCall) {
        try {
            val alarmSettingsData = call.getObject("alarmSettings")
                ?: return rejectCall(call, ERROR_INVALID_ALARM_SETTINGS)

            val alarmSettings = AlarmSettings.fromCapacitorData(alarmSettingsData.toJsonObject())
            setAlarmInternal(alarmSettings)
            resolveCall(call)
        } catch (e: Exception) {
            rejectCall(call, e)
        }
    }

    @PluginMethod
    fun stopAlarm(call: PluginCall) {
        try {
            val alarmId = call.getInt("alarmId") ?: return rejectCall(call, "Missing alarmId")
            stopAlarmInternal(alarmId)
            resolveCall(call)
        } catch (e: Exception) {
            rejectCall(call, e)
        }
    }

    @PluginMethod
    fun stopAll(call: PluginCall) {
        try {
            implementation?.let { storage ->
                for (alarm in storage.getSavedAlarms()) {
                    stopAlarmInternal(alarm.id)
                }
            }
            val alarmIdsCopy = alarmIds.toList()
            for (alarmId in alarmIdsCopy) {
                stopAlarmInternal(alarmId)
            }
            resolveCall(call)
        } catch (e: Exception) {
            rejectCall(call, e)
        }
    }

    @PluginMethod
    fun isRinging(call: PluginCall) {
        try {
            val alarmId = call.getInt("alarmId")
            val ringingAlarmIds = AlarmService.ringingAlarmIds

            val isRinging = if (alarmId == null) {
                ringingAlarmIds.isNotEmpty()
            } else {
                ringingAlarmIds.contains(alarmId)
            }

            val result = JSObject()
            result.put("isRinging", isRinging)
            call.resolve(result)
        } catch (e: Exception) {
            rejectCall(call, e)
        }
    }

    @PluginMethod
    fun getAlarms(call: PluginCall) {
        try {
            implementation?.let { storage ->
                val savedAlarms = storage.getSavedAlarms()
                val alarmsArray = JSArray()

                for (alarm in savedAlarms) {
                    val alarmJson = alarm.toJsonObject()
                    val alarmJSObject = JSObject()
                    for ((key, value) in alarmJson) {
                        alarmJSObject.put(key, value.toString().trim('"'))
                    }
                    alarmsArray.put(alarmJSObject)
                }

                val result = JSObject()
                result.put("alarms", alarmsArray)
                call.resolve(result)
            } ?: run {
                val result = JSObject()
                result.put("alarms", JSArray())
                call.resolve(result)
            }
        } catch (e: Exception) {
            rejectCall(call, e)
        }
    }

    @PluginMethod
    fun setWarningNotificationOnKill(call: PluginCall) {
        try {
            val title = call.getString("title") ?: notificationOnKillTitle
            val body = call.getString("body") ?: notificationOnKillBody

            notificationOnKillTitle = title
            notificationOnKillBody = body

            // Re-create if needed
            turnOffWarningNotificationOnKill()
            updateWarningNotificationState()

            resolveCall(call)
        } catch (e: Exception) {
            rejectCall(call, e)
        }
    }

    // Internal implementation methods
    private fun setAlarmInternal(alarm: AlarmSettings) {
        if (alarmIds.contains(alarm.id)) {
            Logger.warn(TAG, "Stopping alarm with identical ID=${alarm.id} before scheduling a new one.")
            stopAlarmInternal(alarm.id)
        }

        val alarmIntent = createAlarmIntent(alarm)
        val delayInSeconds = (alarm.dateTime.time - System.currentTimeMillis()) / 1000

        alarmIds.add(alarm.id)
        implementation?.saveAlarm(alarm)

        if (delayInSeconds <= 5) {
            handleImmediateAlarm(alarmIntent, delayInSeconds.toInt())
        } else {
            handleDelayedAlarm(alarmIntent, delayInSeconds.toInt(), alarm.id)
        }
    }

    private fun stopAlarmInternal(alarmId: Int) {
        var alarmWasRinging = false
        if (AlarmService.ringingAlarmIds.contains(alarmId)) {
            alarmWasRinging = true
            val stopIntent = Intent(context, AlarmService::class.java)
            stopIntent.action = "STOP_ALARM"
            stopIntent.putExtra("id", alarmId)
            context.stopService(stopIntent)
        }

        // Intent to cancel the future alarm if it's set
        val alarmIntent = Intent(context, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Cancel the future alarm using AlarmManager
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)

        alarmIds.remove(alarmId)
        implementation?.unsaveAlarm(alarmId)
        updateWarningNotificationState()

        // If the alarm was ringing it is the responsibility of the AlarmService to send the stop
        // signal to Capacitor.
        if (!alarmWasRinging) {
            // Notify about the alarm being stopped
            notifyAlarmStopped(alarmId)
        }
    }

    private fun createAlarmIntent(alarm: AlarmSettings): Intent {
        val alarmIntent = Intent(context, AlarmReceiver::class.java)
        alarmIntent.putExtra("id", alarm.id)
        alarmIntent.putExtra("alarmSettings", Json.encodeToString(alarm))
        return alarmIntent
    }

    private fun handleImmediateAlarm(intent: Intent, delayInSeconds: Int) {
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed({
            context.sendBroadcast(intent)
        }, delayInSeconds * 1000L)
    }

    private fun handleDelayedAlarm(intent: Intent, delayInSeconds: Int, id: Int) {
        try {
            val triggerTime = System.currentTimeMillis() + delayInSeconds * 1000L
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: throw IllegalStateException("AlarmManager not available")

            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTime,
                pendingIntent
            )

            updateWarningNotificationState()
        } catch (e: ClassCastException) {
            Logger.error(TAG, "AlarmManager service type casting failed", e)
        } catch (e: IllegalStateException) {
            Logger.error(TAG, "AlarmManager service not available", e)
        } catch (e: Exception) {
            Logger.error(TAG, "Error in handling delayed alarm", e)
        }
    }

    private fun updateWarningNotificationState() {
        implementation?.let { storage ->
            if (storage.getSavedAlarms().any { it.warningNotificationOnKill }) {
                turnOnWarningNotificationOnKill()
            } else {
                turnOffWarningNotificationOnKill()
            }
        }
    }

    private fun turnOnWarningNotificationOnKill() {
        if (NotificationOnKillService.isRunning) {
            Logger.debug(TAG, "Warning notification is already turned on.")
            return
        }

        val serviceIntent = Intent(context, NotificationOnKillService::class.java)
        serviceIntent.putExtra("title", notificationOnKillTitle)
        serviceIntent.putExtra("body", notificationOnKillBody)

        context.startService(serviceIntent)
        Logger.debug(TAG, "Warning notification turned on.")
    }

    private fun turnOffWarningNotificationOnKill() {
        if (!NotificationOnKillService.isRunning) {
            Logger.debug(TAG, "Warning notification is already turned off.")
            return
        }

        val serviceIntent = Intent(context, NotificationOnKillService::class.java)
        context.stopService(serviceIntent)
        Logger.debug(TAG, "Warning notification turned off.")
    }

    // Public methods for service callbacks
    fun notifyAlarmRang(alarmId: Int) {
        val data = JSObject()
        data.put("alarmId", alarmId)
        notifyListeners("alarmRang", data)
    }

    fun notifyAlarmStopped(alarmId: Int) {
        val data = JSObject()
        data.put("alarmId", alarmId)
        notifyListeners("alarmStopped", data)
    }

    // Helper methods
    private fun resolveCall(call: PluginCall) {
        call.resolve()
    }

    private fun rejectCall(call: PluginCall, message: String) {
        Logger.error(message)
        call.reject(message)
    }

    private fun rejectCall(call: PluginCall, exception: Exception) {
        val message = exception.message ?: ERROR_UNKNOWN_ERROR
        Logger.error(TAG, message, exception)
        call.reject(message)
    }

    private fun JSObject.toJsonObject(): JsonObject {
        val jsonString = this.toString()
        return Json.parseToJsonElement(jsonString).jsonObject
    }

    private fun getNotificationPermissionState(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ - check POST_NOTIFICATIONS permission
            when (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)) {
                PackageManager.PERMISSION_GRANTED -> {
                    // Also check if notifications are enabled in system settings
                    if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                        "granted"
                    } else {
                        "denied"
                    }
                }
                PackageManager.PERMISSION_DENIED -> {
                    // Check if we should show rationale
                    val activity = this.activity
                    if (activity != null && activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
                        "prompt-with-rationale"
                    } else {
                        "prompt"
                    }
                }
                else -> "prompt"
            }
        } else {
            // Android 12 and below - check system notification settings
            if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                "granted"
            } else {
                "denied"
            }
        }
    }

}