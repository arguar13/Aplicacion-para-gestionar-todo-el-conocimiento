package app.sinapsis

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * El canal `app.sinapsis/study_reminder` (F31): lo que Dart le pide al aviso
 * diario para repasar. Ver [StudyReminder] y, del lado de Dart,
 * `MethodChannelStudyReminder`.
 *
 * Métodos:
 * - `schedule {hour, minute}`: prende el aviso a esa hora.
 * - `cancel`: lo apaga.
 * - `status`: `{scheduled, hour, minute, permission}`. `scheduled` es si el
 *   sistema tiene la alarma puesta de verdad, no lo que se guardó.
 * - `requestPermission`: pide el permiso de notificaciones (Android 13 en
 *   adelante) y contesta, ya con la respuesta, si quedó concedido.
 * - `openNotificationSettings`: abre los ajustes de notificaciones de la app.
 * - `setStudyCount {count}`: cuántas tarjetas hay para el texto del aviso.
 * - `takePendingOpen`: si la app se abrió desde la notificación y todavía no
 *   se atendió.
 *
 * Hacia Dart: `openReview`, cuando se toca la notificación con la app andando.
 */
class StudyReminderChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> {
                val hour = call.argument<Int>("hour")
                val minute = call.argument<Int>("minute")
                if (hour == null || minute == null || hour !in 0..23 || minute !in 0..59) {
                    result.error("arguments", "Hace falta una hora de 0 a 23 y un minuto de 0 a 59.", null)
                    return
                }
                StudyReminder.schedule(context, hour, minute)
                result.success(null)
            }
            "cancel" -> {
                StudyReminder.cancel(context)
                result.success(null)
            }
            "status" -> result.success(
                mapOf(
                    "scheduled" to (StudyReminder.isEnabled(context) && StudyReminder.isArmed(context)),
                    "hour" to StudyReminder.hour(context),
                    "minute" to StudyReminder.minute(context),
                    "permission" to StudyReminder.notificationsAllowed(context),
                ),
            )
            "requestPermission" -> requestPermission(result)
            "openNotificationSettings" -> result.success(openNotificationSettings())
            "setStudyCount" -> {
                val count = call.argument<Int>("count")
                if (count == null) {
                    result.error("arguments", "Falta count.", null)
                    return
                }
                StudyReminder.setStudyCount(context, count)
                result.success(null)
            }
            "takePendingOpen" -> {
                val pending = pendingOpen
                pendingOpen = false
                result.success(pending)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        // Antes de Android 13 no hay permiso que pedir: lo que cuenta es si la
        // persona silenció las notificaciones de la app en los ajustes.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(StudyReminder.notificationsAllowed(context))
            return
        }
        val activity = SinapsisEngine.currentActivity()
        if (activity == null) {
            // Sin pantalla no hay dónde preguntar.
            result.success(StudyReminder.notificationsAllowed(context))
            return
        }
        if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(StudyReminder.notificationsAllowed(context))
            return
        }
        // Dos pedidos a la vez no se pueden: el primero se contesta como negado.
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST,
        )
    }

    private fun openNotificationSettings(): Boolean {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "No hay una pantalla de ajustes de notificaciones", e)
            false
        }
    }

    companion object {
        const val CHANNEL = "app.sinapsis/study_reminder"
        const val PERMISSION_REQUEST = 22
        private const val TAG = "StudyReminderChannel"

        /** El canal hacia Dart; lo pone [SinapsisEngine] al instalar los canales. */
        @Volatile private var channel: MethodChannel? = null

        @Volatile private var pendingOpen = false
        @Volatile private var pendingPermission: MethodChannel.Result? = null

        fun install(channel: MethodChannel) {
            this.channel = channel
        }

        /**
         * La actividad recibió un intent: si viene de tocar la notificación, hay
         * que mostrar Repasar. Con Dart escuchando se le avisa; en cualquier caso
         * queda pendiente hasta que lo recoja ([takePendingOpen] en Dart), así
         * un toque que abre la app desde cero no se pierde.
         */
        fun onIntent(intent: Intent?) {
            if (intent?.getBooleanExtra(StudyReminder.EXTRA_OPEN_REVIEW, false) != true) return
            // Se consume: la actividad se recrea con el mismo intent al girar la
            // pantalla y no tiene que abrir Repasar otra vez.
            intent.removeExtra(StudyReminder.EXTRA_OPEN_REVIEW)
            pendingOpen = true
            // Si Dart estaba escuchando, el toque queda atendido; si todavía no
            // (arranque en frío) o no hay nadie del otro lado, sigue pendiente
            // para `takePendingOpen`.
            channel?.invokeMethod(
                "openReview",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        pendingOpen = false
                    }

                    override fun error(code: String, message: String?, details: Any?) = Unit

                    override fun notImplemented() = Unit
                },
            )
        }

        /** La respuesta del diálogo del permiso de notificaciones. */
        fun onPermissionsResult(requestCode: Int, grantResults: IntArray) {
            if (requestCode != PERMISSION_REQUEST) return
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }
}
