package org.pictalk.plugin.alarm.models

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/**
 * Custom serializer for nullable Duration that handles both string and numeric millisecond values
 */
object DurationMillisSerializer : KSerializer<Duration?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("DurationMillis", PrimitiveKind.LONG)

    override fun serialize(encoder: Encoder, value: Duration?) {
        if (value == null) {
            encoder.encodeNull()
        } else {
            encoder.encodeLong(value.inWholeMilliseconds)
        }
    }

    override fun deserialize(decoder: Decoder): Duration? {
        return try {
            val millis = decoder.decodeLong()
            millis.milliseconds
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * Custom serializer for non-nullable Duration that handles both string and numeric millisecond values
 */
object DurationMillisNonNullSerializer : KSerializer<Duration> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("DurationMillisNonNull", PrimitiveKind.LONG)

    override fun serialize(encoder: Encoder, value: Duration) {
        encoder.encodeLong(value.inWholeMilliseconds)
    }

    override fun deserialize(decoder: Decoder): Duration {
        val millis = decoder.decodeLong()
        return millis.milliseconds
    }
}

@Serializable
data class VolumeSettings(
    val volume: Double? = null,
    @Serializable(with = DurationMillisSerializer::class)
    val fadeDuration: Duration? = null,
    val fadeSteps: List<VolumeFadeStep> = emptyList(),
    val volumeEnforced: Boolean = false
) {
    companion object {
        /**
         * Creates VolumeSettings from Capacitor data with proper defaults
         */
        fun fromCapacitorData(
            volume: Double? = null,
            fadeDurationMillis: Long? = null,
            fadeSteps: List<VolumeFadeStep> = emptyList(),
            volumeEnforced: Boolean = false
        ): VolumeSettings {
            return VolumeSettings(
                volume = volume,
                fadeDuration = fadeDurationMillis?.milliseconds,
                fadeSteps = fadeSteps,
                volumeEnforced = volumeEnforced
            )
        }
    }
}

@Serializable
data class VolumeFadeStep(
    @Serializable(with = DurationMillisNonNullSerializer::class)
    val time: Duration,
    val volume: Double
) {
    companion object {
        /**
         * Creates VolumeFadeStep from Capacitor data
         */
        fun fromCapacitorData(timeMillis: Long, volume: Double): VolumeFadeStep {
            return VolumeFadeStep(
                time = timeMillis.milliseconds,
                volume = volume
            )
        }
    }
}