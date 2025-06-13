package org.pictalk.plugin.alarm.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.pictalk.plugin.alarm.models.AlarmSettings
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import com.getcapacitor.Logger
import org.pictalk.plugin.alarm.services.AlarmStorage

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Logger.debug(TAG, "Device rebooted, rescheduling alarms")
            rescheduleAlarms(context)
        }
    }

    private fun rescheduleAlarms(context: Context) {
        val alarmStorage = AlarmStorage(context)
        val storedAlarms = alarmStorage.getSavedAlarms()

        Logger.info(TAG, "Rescheduling ${storedAlarms.size} alarms")

        for (alarm in storedAlarms) {
            try {
                Logger.debug(TAG, "Rescheduling alarm with ID: ${alarm.id}")
                Logger.debug(TAG, "Alarm details: $alarm")

                // Create a temporary plugin instance for rescheduling
                val tempPlugin = createTemporaryPlugin(context)
                tempPlugin.setAlarmInternal(alarm)

                Logger.debug(TAG, "Alarm rescheduled successfully for ID: ${alarm.id}")
            } catch (e: Exception) {
                Logger.error(TAG, "Exception while rescheduling alarm: $alarm", e)
            }
        }
    }

    /**
     * Creates a temporary plugin instance for boot rescheduling
     * This allows us to reuse the alarm scheduling logic without full plugin initialization
     */
    private fun createTemporaryPlugin(context: Context): AlarmPluginHelper {
        return AlarmPluginHelper(context)
    }
}

/**
 * Helper class that provides access to alarm scheduling functionality
 * without requiring full Capacitor plugin initialization
 */
class AlarmPluginHelper(private val context: Context) {
    private val alarmIds: MutableList<Int> = mutableListOf()
    private val implementation = AlarmStorage(context)

    fun setAlarmInternal(alarm: AlarmSettings) {
        if (alarmIds.contains(alarm.id)) {
            Logger.warn("BootReceiver", "Stopping alarm with identical ID=${alarm.id} before scheduling a new one.")
            stopAlarmInternal(alarm.id)
        }

        val alarmIntent = createAlarmIntent(alarm)
        val delayInSeconds = (alarm.dateTime.time - System.currentTimeMillis()) / 1000

        // Skip alarms that are in the past
        if (delayInSeconds <= 0) {
            Logger.warn("BootReceiver", "Skipping alarm ${alarm.id} as it's in the past")
            implementation.unsaveAlarm(alarm.id)
            return
        }

        alarmIds.add(alarm.id)
        implementation.saveAlarm(alarm)

        if (delayInSeconds <= 5) {
            handleImmediateAlarm(alarmIntent, delayInSeconds.toInt())
        } else {
            handleDelayedAlarm(alarmIntent, delayInSeconds.toInt(), alarm.id)
        }
    }

    private fun stopAlarmInternal(alarmId: Int) {
        val alarmIntent = Intent(context, AlarmReceiver::class.java)
        val pendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            alarmId,
            alarmIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        alarmManager.cancel(pendingIntent)

        alarmIds.remove(alarmId)
        implementation.unsaveAlarm(alarmId)
    }

    private fun createAlarmIntent(alarm: AlarmSettings): Intent {
        val alarmIntent = Intent(context, AlarmReceiver::class.java)
        alarmIntent.putExtra("id", alarm.id)
        alarmIntent.putExtra("alarmSettings", Json.encodeToString(alarm))
        return alarmIntent
    }

    private fun handleImmediateAlarm(intent: Intent, delayInSeconds: Int) {
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed({
            context.sendBroadcast(intent)
        }, delayInSeconds * 1000L)
    }

    private fun handleDelayedAlarm(intent: Intent, delayInSeconds: Int, id: Int) {
        try {
            val triggerTime = System.currentTimeMillis() + delayInSeconds * 1000L
            val pendingIntent = android.app.PendingIntent.getBroadcast(
                context,
                id,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? android.app.AlarmManager
                ?: throw IllegalStateException("AlarmManager not available")

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    android.app.AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                alarmManager.setExact(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            } else {
                alarmManager.set(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            }
        } catch (e: ClassCastException) {
            Logger.error("BootReceiver", "AlarmManager service type casting failed", e)
        } catch (e: IllegalStateException) {
            Logger.error("BootReceiver", "AlarmManager service not available", e)
        } catch (e: Exception) {
            Logger.error("BootReceiver", "Error in handling delayed alarm", e)
        }
    }
}