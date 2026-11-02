package org.pictalk.plugin.alarm.services

import android.content.Context
import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.getcapacitor.Logger
import org.pictalk.plugin.alarm.models.SpeechSettings
import java.util.Locale

class SpeechService(context: Context, private val settings: SpeechSettings) {
    companion object {
        private const val TAG = "SpeechService"
        // An engine that never answers must not keep the alarm silent.
        private const val TIMEOUT_MS = 15_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var ready: Boolean? = null
    private var onDone: (() -> Unit)? = null
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        handler.post { onInit(status) }
    }

    /** Speaks the text, then calls [done] on the main thread, also when speech fails. */
    fun speak(done: () -> Unit) {
        if (ready == false) return done()
        onDone = done
        handler.postDelayed({ finish() }, TIMEOUT_MS)
        if (ready == true) say()
    }

    fun shutdown() {
        handler.removeCallbacksAndMessages(null)
        onDone = null
        tts.stop()
        tts.shutdown()
    }

    private fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Logger.error(TAG, "No text-to-speech engine ($status)", null)
            ready = false
            finish()
            return
        }
        ready = true
        settings.locale?.takeIf { it.isNotEmpty() }?.let { tts.language = Locale.forLanguageTag(it) }
        tts.setSpeechRate(settings.rate.toFloat().coerceIn(0.1f, 3f))
        tts.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = Unit
            override fun onDone(utteranceId: String?) { handler.post { finish() } }
            @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
            override fun onError(utteranceId: String?) { handler.post { finish() } }
            override fun onError(utteranceId: String?, errorCode: Int) { handler.post { finish() } }
        })
        if (onDone != null) say()
    }

    private fun say() {
        tts.speak(settings.text, TextToSpeech.QUEUE_FLUSH, null, "alarm")
    }

    private fun finish() {
        handler.removeCallbacksAndMessages(null)
        val done = onDone ?: return
        onDone = null
        done()
    }
}
