package app.sinapsis

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Habla a texto con el reconocedor de voz del sistema (F42): el 🎤 del campo
 * del chat. Ver, del lado de Dart, `MethodChannelDictation`.
 *
 * Sin paquetes: `SpeechRecognizer` ya está en el teléfono, y así se puede
 * preguntar si hay uno sin pedir el permiso del micrófono —el 🎤 se muestra o
 * no al abrir el chat— y pedirlo recién la primera vez que se toca.
 *
 * El canal `app.sinapsis/dictation`:
 * - `isAvailable`: si el teléfono tiene un servicio de reconocimiento. Sin
 *   permisos.
 * - `requestPermission`: pide el permiso del micrófono si hace falta y
 *   contesta, ya con la respuesta, si quedó concedido.
 * - `stop`: deja de escuchar; lo dicho hasta ahí llega como final.
 *
 * El canal de eventos `app.sinapsis/dictation/events`: escucharlo arranca el
 * reconocedor (con `{locale}`), y dejar de escucharlo lo cancela. Cada evento
 * es `{type: heard, text, final}` o `{type: level, value}` (0 a 1); termina
 * cuando el reconocedor termina la frase, y con un error `permission`,
 * `busy`, `network`, `audio`, `server`, `client` o `unavailable` si falla.
 * Que no se haya oído nada no es un error: termina sin texto.
 *
 * Todo corre en el hilo principal, que es donde `SpeechRecognizer` exige que
 * se lo use y donde Flutter entrega los mensajes de los canales.
 */
class DictationChannel(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var recognizer: SpeechRecognizer? = null
    private var sink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(SpeechRecognizer.isRecognitionAvailable(context))
            "requestPermission" -> requestPermission(result)
            "stop" -> {
                recognizer?.stopListening()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        // Una escucha a la vez: la nueva reemplaza a la que hubiera.
        release()
        if (!granted()) {
            events.error("permission", "Sin permiso para usar el micrófono.", null)
            events.endOfStream()
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            events.error("unavailable", "No hay reconocimiento de voz en este teléfono.", null)
            events.endOfStream()
            return
        }
        val locale = (arguments as? Map<*, *>)?.get("locale") as? String
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            if (locale != null) putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        }
        val created = SpeechRecognizer.createSpeechRecognizer(context)
        created.setRecognitionListener(Listener(created))
        recognizer = created
        sink = events
        created.startListening(intent)
    }

    override fun onCancel(arguments: Any?) {
        release()
    }

    /** Suelta el reconocedor sin dar más nada: quien escuchaba ya no está. */
    private fun release() {
        sink = null
        recognizer?.let {
            it.cancel()
            it.destroy()
        }
        recognizer = null
    }

    /** Termina la escucha de [owner], si sigue siendo la de ahora. */
    private fun finish(owner: SpeechRecognizer) {
        if (recognizer !== owner) return
        val events = sink
        sink = null
        recognizer = null
        owner.destroy()
        events?.endOfStream()
    }

    private fun granted(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (granted()) {
            result.success(true)
            return
        }
        val activity = SinapsisEngine.currentActivity()
        if (activity == null) {
            // Sin pantalla no hay dónde preguntar.
            result.success(false)
            return
        }
        // Dos pedidos a la vez no se pueden: el primero se contesta como negado.
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
    }

    /** Lo que avisa el reconocedor [owner]; se ignora si ya no es el de ahora. */
    private inner class Listener(private val owner: SpeechRecognizer) : RecognitionListener {
        private fun send(event: Map<String, Any>) {
            if (recognizer === owner) sink?.success(event)
        }

        private fun heard(results: Bundle?, isFinal: Boolean) {
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?: return
            send(mapOf("type" to "heard", "text" to text, "final" to isFinal))
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit

        override fun onBeginningOfSpeech() = Unit

        // El volumen llega en decibeles, de unos -2 (silencio) a 10 (voz
        // fuerte): se pasa a 0..1 para el latido del 🎤.
        override fun onRmsChanged(rmsdB: Float) {
            val level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
            send(mapOf("type" to "level", "value" to level.toDouble()))
        }

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() = Unit

        override fun onPartialResults(partialResults: Bundle?) = heard(partialResults, isFinal = false)

        override fun onResults(results: Bundle?) {
            heard(results, isFinal = true)
            finish(owner)
        }

        override fun onError(error: Int) {
            if (recognizer !== owner) return
            val code = when (error) {
                // Silencio, o nada que se entienda: termina sin texto.
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> null
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
                SpeechRecognizer.ERROR_AUDIO -> "audio"
                SpeechRecognizer.ERROR_SERVER -> "server"
                else -> "client"
            }
            if (code != null) sink?.error(code, "El reconocimiento de voz falló ($error).", null)
            finish(owner)
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    companion object {
        const val CHANNEL = "app.sinapsis/dictation"
        const val EVENTS = "app.sinapsis/dictation/events"
        const val PERMISSION_REQUEST = 23

        @Volatile private var pendingPermission: MethodChannel.Result? = null

        /** La respuesta del diálogo del permiso del micrófono. */
        fun onPermissionsResult(requestCode: Int, grantResults: IntArray) {
            if (requestCode != PERMISSION_REQUEST) return
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }
}
