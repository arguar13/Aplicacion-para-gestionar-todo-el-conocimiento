package app.sinapsis

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * El canal `app.sinapsis/home_widgets` (F47, paso 7): los toques a los widgets
 * de la pantalla de inicio. Del lado de Dart, `AndroidHomeScreenWidgets`.
 *
 * Métodos:
 * - `takePendingOpen`: el widget que abrió la app y todavía no se atendió
 *   (`dueToday`, `quickCapture`, `continueListening`), o `null`.
 *
 * Hacia Dart: `open` con el nombre del widget, cuando se toca uno con Dart
 * andando.
 *
 * Es el mismo camino que el toque a la notificación del aviso diario
 * ([StudyReminderChannel]), y por lo mismo: el motor de Dart vive más que la
 * actividad (F29). Un toque con la app cerrada abre una actividad nueva, quizá
 * sobre un Dart que ya andaba —se le avisa por el canal— o sobre uno que
 * recién arranca —lo recoge con `takePendingOpen`—.
 */
class HomeWidgetsChannel : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingOpen" -> {
                val pending = pendingOpen
                pendingOpen = null
                result.success(pending)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.sinapsis/home_widgets"

        /** El canal hacia Dart; lo pone [SinapsisEngine] al instalar los canales. */
        @Volatile private var channel: MethodChannel? = null

        @Volatile private var pendingOpen: String? = null

        fun install(channel: MethodChannel) {
            this.channel = channel
        }

        /**
         * La actividad recibió un intent: si viene de tocar un widget, queda
         * pendiente y, si Dart escucha, se le avisa —y deja de estar
         * pendiente cuando contesta—.
         */
        fun onIntent(intent: Intent?) {
            val widget = intent?.getStringExtra(HomeWidgets.EXTRA_OPEN) ?: return
            // Se consume: la actividad se recrea con el mismo intent al girar
            // la pantalla, y no tiene que volver a abrir lo mismo.
            intent.removeExtra(HomeWidgets.EXTRA_OPEN)
            pendingOpen = widget
            channel?.invokeMethod(
                "open",
                widget,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (pendingOpen == widget) pendingOpen = null
                    }

                    override fun error(code: String, message: String?, details: Any?) = Unit

                    override fun notImplemented() = Unit
                },
            )
        }
    }
}
