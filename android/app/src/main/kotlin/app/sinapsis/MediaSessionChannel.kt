package app.sinapsis

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * La tarjeta de lo que suena (F47, paso 2b), del lado de Android: Dart dice
 * qué mostrar (`update`) y cuándo ya no suena nada (`end`); Android le cuenta
 * lo que se tocó en la tarjeta, los auriculares o el reloj (`command`) y lo
 * que pasó en el teléfono —una llamada, otra app, los auriculares
 * desconectados— (`interruption`). Ver [MediaPlaybackService].
 *
 * Es la sesión de medios del propio Android, sin dependencias nuevas: la
 * alternativa a `audio_service` de la decisión J de F47. `audio_service` se
 * adueña del motor de Flutter —lo crea con su propio nombre y lo destruye
 * cuando su servicio se va y no hay actividad—, y el motor de esta app es el
 * del proceso ([SinapsisEngine], F29), que tiene que sobrevivir para que el
 * trabajo largo siga con la app cerrada: con `audio_service`, cerrar la app
 * desde "recientes" mataba la cola de procesamiento.
 */
class MediaSessionChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                MediaPlaybackService.show(context, MediaCard.from(call))
                result.success(null)
            }
            "end" -> {
                MediaPlaybackService.end()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.sinapsis/media_session"

        /** El toque a la tarjeta: abre la app, y Dart lo sabe. */
        const val ACTION_OPEN = "app.sinapsis.media.OPEN"

        private var channel: MethodChannel? = null

        /** El canal con Dart, del motor del proceso. */
        fun install(channel: MethodChannel) {
            this.channel = channel
        }

        /** Lo que se tocó: `play`, `pause`, `skip` (con [ms]), `next`, `seek` (con [ms]), `stop` u `open`. */
        fun command(name: String, ms: Long? = null) {
            channel?.invokeMethod("command", mapOf("name" to name, "ms" to ms))
        }

        /** Lo que pasó: `began`, `lost`, `ended` o `noisy`. */
        fun interruption(kind: String) {
            channel?.invokeMethod("interruption", mapOf("kind" to kind))
        }

        /** La actividad se abrió, o volvió al frente, con [intent]: si fue tocando la tarjeta, Dart lo sabe. */
        fun onIntent(intent: Intent?) {
            if (intent?.action == ACTION_OPEN) command("open")
        }
    }
}

/** Lo que muestra la tarjeta: ver `MediaSessionState` en Dart. */
data class MediaCard(
    val title: String,
    val subtitle: String?,
    val positionMs: Long,
    val durationMs: Long,
    val playing: Boolean,
    val hasNext: Boolean,
    val focus: Boolean,
    val artwork: ByteArray?,
) {
    /** Si se ve igual en la tarjeta, salvo por dónde va. */
    fun looksLike(other: MediaCard?): Boolean =
        other != null &&
            other.title == title &&
            other.subtitle == subtitle &&
            other.playing == playing &&
            other.hasNext == hasNext &&
            other.artwork.contentEquals(artwork)

    companion object {
        fun from(call: MethodCall) = MediaCard(
            title = call.argument<String>("title") ?: "",
            subtitle = call.argument<String>("subtitle"),
            positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L,
            durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L,
            playing = call.argument<Boolean>("playing") ?: false,
            hasNext = call.argument<Boolean>("hasNext") ?: false,
            focus = call.argument<Boolean>("focus") ?: true,
            artwork = call.argument<ByteArray>("artwork"),
        )
    }
}
