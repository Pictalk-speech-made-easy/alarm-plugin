package org.pictalk.plugin.alarm.models

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.*
import java.util.Date
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

@Serializable
data class AlarmSettings(
    val id: Int,
    @Serializable(with = DateSerializer::class)
    val dateTime: Date,
    val assetAudioPath: String,
    val volumeSettings: VolumeSettings,
    val notificationSettings: NotificationSettings,
    val loopAudio: Boolean,
    val vibrate: Boolean,
    val warningNotificationOnKill: Boolean,
    val androidFullScreenIntent: Boolean,
    val allowAlarmOverlap: Boolean = false, // Defaults to false for backward compatibility
    val androidStopAlarmOnTermination: Boolean = true, // Defaults to true for backward compatibility
    val payload: String? = null // Optional payload data
) {
    companion object {
        /**
         * Creates AlarmSettings from Capacitor plugin call data (JSObject/JSON)
         */
        fun fromCapacitorData(json: JsonObject): AlarmSettings {
            val id = json.primitiveInt("id") ?: throw SerializationException("Missing 'id'")

            // Handle dateTime as ISO string from Capacitor
            val dateTimeString = json.primitiveString("dateTime") ?: throw SerializationException("Missing 'dateTime'")
            val dateTime = try {
                // Parse ISO 8601 date string manually for API 23+ compatibility
                val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val isoFormatNoMillis = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }

                when {
                    dateTimeString.contains('.') -> isoFormat.parse(dateTimeString)
                    else -> isoFormatNoMillis.parse(dateTimeString)
                } ?: throw Exception("Failed to parse date")
            } catch (e: Exception) {
                throw SerializationException("Invalid dateTime format: $dateTimeString")
            }

            val assetAudioPath = json.primitiveString("assetAudioPath") ?: throw SerializationException("Missing 'assetAudioPath'")
            val notificationSettings = json["notificationSettings"]?.let {
                Json.decodeFromJsonElement<NotificationSettings>(it)
            } ?: throw SerializationException("Missing 'notificationSettings'")
            val loopAudio = json.primitiveBoolean("loopAudio") ?: true
            val vibrate = json.primitiveBoolean("vibrate") ?: true
            val warningNotificationOnKill = json.primitiveBoolean("warningNotificationOnKill") ?: true
            val androidFullScreenIntent = json.primitiveBoolean("androidFullScreenIntent") ?: true
            val allowAlarmOverlap = json.primitiveBoolean("allowAlarmOverlap") ?: false
            val androidStopAlarmOnTermination = json.primitiveBoolean("androidStopAlarmOnTermination") ?: true
            val payload = json.primitiveString("payload")

            // Handle volumeSettings with defaults
            val volumeSettings = json["volumeSettings"]?.let {
                Json.decodeFromJsonElement<VolumeSettings>(it)
            } ?: VolumeSettings(
                volume = 1.0,
                fadeDuration = null,
                fadeSteps = emptyList(),
                volumeEnforced = false
            )

            return AlarmSettings(
                id = id,
                dateTime = dateTime,
                assetAudioPath = assetAudioPath,
                volumeSettings = volumeSettings,
                notificationSettings = notificationSettings,
                loopAudio = loopAudio,
                vibrate = vibrate,
                warningNotificationOnKill = warningNotificationOnKill,
                androidFullScreenIntent = androidFullScreenIntent,
                allowAlarmOverlap = allowAlarmOverlap,
                androidStopAlarmOnTermination = androidStopAlarmOnTermination,
                payload = payload
            )
        }

        /**
         * Handles backward compatibility for missing fields like `volumeSettings` and `allowAlarmOverlap`.
         */
        fun fromJson(json: String): AlarmSettings {
            val jsonObject = Json.parseToJsonElement(json).jsonObject
            return fromCapacitorData(jsonObject)
        }
    }

    /**
     * Converts AlarmSettings to JsonObject for sending back to Capacitor
     */
    fun toJsonObject(): JsonObject {
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        return buildJsonObject {
            put("id", id)
            put("dateTime", isoFormat.format(dateTime))
            put("assetAudioPath", assetAudioPath)
            put("volumeSettings", Json.encodeToJsonElement(volumeSettings))
            put("notificationSettings", Json.encodeToJsonElement(notificationSettings))
            put("loopAudio", loopAudio)
            put("vibrate", vibrate)
            put("warningNotificationOnKill", warningNotificationOnKill)
            put("androidFullScreenIntent", androidFullScreenIntent)
            put("allowAlarmOverlap", allowAlarmOverlap)
            put("androidStopAlarmOnTermination", androidStopAlarmOnTermination)
            payload?.let { put("payload", it) }
        }
    }
}

/**
 * Custom serializer for Java's `Date` type.
 */
object DateSerializer : KSerializer<Date> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("Date", PrimitiveKind.LONG)
    override fun serialize(encoder: Encoder, value: Date) = encoder.encodeLong(value.time)
    override fun deserialize(decoder: Decoder): Date = Date(decoder.decodeLong())
}

// Extension functions for safer primitive extraction from JsonObject
private fun JsonObject.primitiveInt(key: String): Int? = this[key]?.jsonPrimitive?.content?.toIntOrNull()
private fun JsonObject.primitiveLong(key: String): Long? = this[key]?.jsonPrimitive?.content?.toLongOrNull()
private fun JsonObject.primitiveDouble(key: String): Double? = this[key]?.jsonPrimitive?.content?.toDoubleOrNull()
private fun JsonObject.primitiveString(key: String): String? = this[key]?.jsonPrimitive?.content
private fun JsonObject.primitiveBoolean(key: String): Boolean? = this[key]?.jsonPrimitive?.content?.toBooleanStrictOrNull()