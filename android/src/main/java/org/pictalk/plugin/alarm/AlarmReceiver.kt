package org.pictalk.plugin.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("alarmId", -1)
        val alarmSettingsJson = intent.getStringExtra("alarmSettings")

        if (alarmId != -1 && alarmSettingsJson != null) {
            val alarmService = AlarmService(context)
            alarmService.onAlarmTriggered(alarmId, alarmSettingsJson)

            // Notify the plugin about the alarm
            notifyAlarmPlugin(context, "alarmRang", alarmId)
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