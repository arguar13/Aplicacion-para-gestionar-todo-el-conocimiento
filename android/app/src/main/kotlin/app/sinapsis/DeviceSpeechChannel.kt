package app.sinapsis

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.UUID

/**
 * Las voces del teléfono, a un archivo (F47, pasos 5 y 6): lo que dice el
 * motor de texto a voz del sistema, guardado en un WAV para armar un podcast
 * o el audio de un documento.
 *
 * **Con un [TextToSpeech] propio, aparte del del lector** (`flutter_tts`). El
 * de `flutter_tts` es uno solo para toda la app, y:
 *
 * - avisa el fin de un archivo con el mismo «terminó» que el de una oración
 *   leída: el lector pasaría a la oración siguiente cada vez que se termina
 *   un tramo del podcast;
 * - si el lector corta lo que dice (`stop`, o un `speak` que vacía la cola),
 *   el archivo en curso se descarta y la espera de `flutter_tts` no se
 *   completa nunca.
 *
 * El sistema lleva una cola por cada [TextToSpeech], así que este y el del
 * lector no se pisan: se puede escuchar un documento mientras se genera un
 * podcast.
 */
class DeviceSpeechChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "app.sinapsis/device_speech"
    }

    private val main = Handler(Looper.getMainLooper())
    private var engine: TextToSpeech? = null

    /** `null` mientras arranca; `true` listo. */
    private var ready: Boolean? = null
    private val waiting = mutableListOf<(Boolean) -> Unit>()

    /** Lo que se está escribiendo, por su id, con a quién avisarle. */
    private val pending = HashMap<String, MethodChannel.Result>()

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {}

        override fun onDone(utteranceId: String) {
            main.post { pending.remove(utteranceId)?.success(null) }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) {
            main.post { pending.remove(utteranceId)?.error("synthesize", "El motor falló.", null) }
        }

        override fun onError(utteranceId: String, errorCode: Int) {
            main.post { pending.remove(utteranceId)?.error("synthesize", "El motor falló ($errorCode).", null) }
        }

        override fun onStop(utteranceId: String, interrupted: Boolean) {
            main.post { pending.remove(utteranceId)?.error("synthesize", "Se cortó.", null) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "synthesize" -> {
                val text = call.argument<String>("text")
                val locale = call.argument<String>("locale")
                val voice = call.argument<String>("voice") ?: ""
                val output = call.argument<String>("output")
                if (text == null || locale == null || output == null) {
                    result.error("arguments", "Faltan text, locale y output.", null)
                    return
                }
                withEngine { ok ->
                    if (!ok) {
                        result.error("engine", "El motor de voz del teléfono no arrancó.", null)
                    } else {
                        synthesize(engine!!, text, locale, voice, output, result)
                    }
                }
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun withEngine(action: (Boolean) -> Unit) {
        when (ready) {
            true -> action(true)
            else -> {
                waiting += action
                if (engine == null) start()
            }
        }
    }

    private fun start() {
        ready = null
        engine = TextToSpeech(context) { status ->
            main.post {
                val ok = status == TextToSpeech.SUCCESS
                if (ok) {
                    engine?.setOnUtteranceProgressListener(listener)
                    ready = true
                } else {
                    // Sin motor no queda nada armado: el próximo pedido vuelve
                    // a intentar.
                    engine?.shutdown()
                    engine = null
                    ready = null
                }
                val actions = waiting.toList()
                waiting.clear()
                actions.forEach { it(ok) }
            }
        }
    }

    private fun synthesize(
        engine: TextToSpeech,
        text: String,
        localeTag: String,
        voiceName: String,
        output: String,
        result: MethodChannel.Result,
    ) {
        val voice = if (voiceName.isEmpty()) null else engine.voices?.firstOrNull { it.name == voiceName }
        if (voiceName.isNotEmpty() && voice == null) {
            result.error("voice", "La voz $voiceName no está en el teléfono.", null)
            return
        }
        if (voice != null) {
            engine.voice = voice
        } else {
            val code = engine.setLanguage(Locale.forLanguageTag(localeTag))
            if (code == TextToSpeech.LANG_MISSING_DATA || code == TextToSpeech.LANG_NOT_SUPPORTED) {
                result.error("voice", "El teléfono no tiene voz para $localeTag.", null)
                return
            }
        }
        // La velocidad se elige al escuchar, no al generar.
        engine.setSpeechRate(1f)
        engine.setPitch(1f)
        val file = File(output)
        file.parentFile?.mkdirs()
        val id = UUID.randomUUID().toString()
        pending[id] = result
        if (engine.synthesizeToFile(text, Bundle(), file, id) != TextToSpeech.SUCCESS) {
            pending.remove(id)
            result.error("synthesize", "El motor no aceptó el pedido.", null)
        }
    }

    /** Suelta el motor; lo que estaba en curso termina con error. */
    private fun release() {
        engine?.stop()
        engine?.shutdown()
        engine = null
        ready = null
        val left = pending.values.toList()
        pending.clear()
        left.forEach { it.error("synthesize", "Se soltó el motor.", null) }
    }
}
