package org.pictalk.plugin.alarm.models

import android.graphics.Color
import kotlinx.serialization.Serializable

@Serializable
data class NotificationSettings(
    val title: String,
    val body: String,
    val stopButton: String? = null,
    val icon: String? = null,
    val iconColor: Int? = null,
    val image: String? = null

) {
    companion object {
        /**
         * Creates NotificationSettings from Capacitor data (handles hex color strings)
         */
        fun fromCapacitorData(
            title: String,
            body: String,
            stopButton: String? = null,
            icon: String? = null,
            iconColorHex: String? = null,
            image: String? = null
        ): NotificationSettings {
            val iconColor = iconColorHex?.let { hex ->
                try {
                    Color.parseColor(hex)
                } catch (e: IllegalArgumentException) {
                    null // Invalid color format, ignore
                }
            }

            return NotificationSettings(
                title = title,
                body = body,
                stopButton = stopButton,
                icon = icon,
                iconColor = iconColor,
                image = image
            )
        }
    }
}