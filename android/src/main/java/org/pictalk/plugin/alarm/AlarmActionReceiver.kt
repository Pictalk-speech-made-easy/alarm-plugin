package org.pictalk.plugin.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "STOP_ALARM" -> {
                val alarmId = intent.getIntExtra("alarmId", -1)
                if (alarmId != -1) {
                    val alarmService = AlarmService(context)
                    alarmService.stopAlarm(alarmId)

                    // Notify the plugin about the alarm stop
                    notifyAlarmPlugin(context, "alarmStopped", alarmId)
                }
            }
        }
    }

    private fun notifyAlarmPlugin(context: Context, event: String, alarmId: Int) {
        val intent = Intent("com.yourcompany.alarm.ALARM_EVENT").apply {
            putExtra("event", event)
            putExtra("alarmId", alarmId)
        }
        context.sendBroadcast(intent)
    }
}