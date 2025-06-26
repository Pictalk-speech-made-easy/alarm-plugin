package org.pictalk.plugin.alarm.services

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat

/**
 * Helper class for managing USE_FULL_SCREEN_INTENT permissions
 * Compatible with older SDK versions and addresses Play Store requirements
 */
class FullScreenIntentPermissionHelper {
    companion object {
        private fun canUseFullScreenIntent(context: Context): Boolean {
            return when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                    val notificationManager = NotificationManagerCompat.from(context)
                    try {
                        val method = notificationManager.javaClass.getMethod("canUseFullScreenIntent")
                        method.invoke(notificationManager) as Boolean
                    } catch (e: Exception) {
                        true
                    }
                }
                else -> true
            }
        }

        private fun requestFullScreenIntentPermission(activity: Activity) {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                    openFullScreenIntentSettings(activity)
                }
            }
        }

        fun checkAndRequestPermission(activity: Activity): Boolean {
            return if (canUseFullScreenIntent(activity)) {
                true
            } else {
                requestFullScreenIntentPermission(activity)
                false
            }
        }

        fun getPermissionStatus(context: Context): String {
            return when {
                canUseFullScreenIntent(context) -> "granted"
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> "denied"
                else -> "granted"
            }
        }

        private fun openFullScreenIntentSettings(activity: Activity) {
            try {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                        // Android 14+ - Direct to full screen intent settings
                        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                            data = Uri.parse("package:${activity.packageName}")
                        }
                        activity.startActivity(intent)
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                        // Android 6+ - System alert window permission
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                            data = Uri.parse("package:${activity.packageName}")
                        }
                        activity.startActivity(intent)
                    }
                    else -> {
                        // Older versions - General app settings
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:${activity.packageName}")
                        }
                        activity.startActivity(intent)
                    }
                }
            } catch (e: Exception) {
                // Fallback to general app settings
                try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:${activity.packageName}")
                    }
                    activity.startActivity(intent)
                } catch (ex: Exception) {
                    // Last resort - general settings
                    val intent = Intent(Settings.ACTION_SETTINGS)
                    activity.startActivity(intent)
                }
            }
        }
    }
}