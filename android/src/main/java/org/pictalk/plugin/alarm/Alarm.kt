package org.pictalk.plugin.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == Intent.ACTION_PACKAGE_REPLACED) {

            // Reschedule alarms after device boot or app update
            val alarmService = AlarmService(context)
            alarmService.init()
            alarmService.checkAlarms()
        }
    }
}