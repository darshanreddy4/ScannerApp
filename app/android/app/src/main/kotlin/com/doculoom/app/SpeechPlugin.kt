package com.doculoom.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Reads text aloud with the phone's own text-to-speech engine. Nothing leaves the phone.
 * Dart sends the text in short pieces; this reports which piece is being spoken and when the last one ends.
 */
class SpeechPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "doculoom/speech")
    private val ui = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready = false
    private var failed = false
    private val waiting = mutableListOf<() -> Unit>()

    // Every request gets a number so that late reports of an earlier one are ignored.
    private var session = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> withEngine({ result.success(it) }, { result.success(true) })
                "speak" -> {
                    val chunks = (call.argument<List<*>>("chunks") ?: emptyList<Any>()).map { it.toString() }
                    val from = call.argument<Int>("from") ?: 0
                    val language = call.argument<String>("language")
                    val rate = call.argument<Double>("rate") ?: 1.0
                    withEngine({ result.success("unavailable") }, { speak(chunks, from, language, rate, result) })
                }
                "stop" -> {
                    session++
                    tts?.stop()
                    result.success(null)
                }
                "openSettings" -> result.success(openSettings())
                else -> result.notImplemented()
            }
        }
    }

    /** Runs [ready] once the engine is up, or [unavailable] with false when the phone has none. */
    private fun withEngine(unavailable: (Boolean) -> Unit, ready: () -> Unit) {
        if (failed) {
            unavailable(false)
            return
        }
        if (this.ready) {
            ready()
            return
        }
        waiting.add { if (failed) unavailable(false) else ready() }
        if (tts == null) {
            tts = TextToSpeech(activity.applicationContext) { status ->
                ui.post {
                    if (status == TextToSpeech.SUCCESS) this.ready = true else failed = true
                    val run = waiting.toList()
                    waiting.clear()
                    run.forEach { it() }
                }
            }
        }
    }

    private fun speak(chunks: List<String>, from: Int, language: String?, rate: Double, result: MethodChannel.Result) {
        val engine = tts ?: return result.success("unavailable")
        session++
        val mine = session
        engine.stop()
        val locale = if (language.isNullOrEmpty()) Locale.getDefault() else Locale.forLanguageTag(language)
        val set = engine.setLanguage(locale)
        if (set == TextToSpeech.LANG_MISSING_DATA || set == TextToSpeech.LANG_NOT_SUPPORTED) {
            result.success("language")
            return
        }
        engine.setSpeechRate(rate.toFloat().coerceIn(0.25f, 3f))
        val last = chunks.size - 1
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                val index = utteranceId?.toIntOrNull() ?: return
                ui.post { if (mine == session) channel.invokeMethod("chunk", index) }
            }

            override fun onDone(utteranceId: String?) {
                if (utteranceId?.toIntOrNull() != last) return
                ui.post { if (mine == session) channel.invokeMethod("done", null) }
            }

            @Deprecated("Replaced by onError(String, Int)")
            override fun onError(utteranceId: String?) {
                ui.post { if (mine == session) channel.invokeMethod("error", "The phone's voice stopped working.") }
            }
        })
        for (i in from.coerceAtLeast(0) until chunks.size) {
            engine.speak(chunks[i], TextToSpeech.QUEUE_ADD, null, i.toString())
        }
        result.success("ok")
    }

    private fun openSettings(): Boolean {
        for (action in listOf("com.android.settings.TTS_SETTINGS", Settings.ACTION_SETTINGS)) {
            try {
                activity.startActivity(Intent(action))
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the general settings next.
            }
        }
        return false
    }

    fun shutdown() {
        session++
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false
    }
}
