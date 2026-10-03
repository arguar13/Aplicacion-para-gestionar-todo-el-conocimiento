package app.sinapsis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * El servicio en primer plano del trabajo largo (F21, decisión C): mientras
 * se transcribe un audio de horas, se reconocen las páginas de un libro
 * escaneado o se baja un modelo de gigas, una notificación con el avance, y
 * el sistema no congela ni mata la app por estar en segundo plano —HyperOS
 * lo hacía a los pocos minutos—.
 *
 * Lo comparten varios trabajos (F27): el procesamiento, las descargas de
 * modelos y del audio de YouTube, la IA que ordena la biblioteca. Quién se
 * ve y cuándo se apaga lo decide Dart (`LongWorkCoordinator`); acá llega una
 * sola cosa por vez, con de quién es ([EXTRA_KIND]) y qué se hace
 * ([EXTRA_DETAIL]) para el texto, y con qué tipos de servicio
 * ([EXTRA_TYPES]) tiene que correr.
 *
 * No hace el trabajo: el trabajo lo hace Dart, en el proceso de la app. El
 * servicio solo mantiene vivo ese proceso y muestra cuánto va. Por eso, si
 * el usuario cierra la app desde "recientes", el servicio se va con ella:
 * sin la app no hay quién trabaje, y lo hecho ya quedó guardado para
 * retomarlo al volver.
 */
class LongWorkService : Service() {
    /** Con qué tipos corre ahora el servicio; 0 sin primer plano. */
    private var currentType = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val done = intent?.getIntExtra(EXTRA_DONE, 0) ?: 0
        val total = intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0
        val notification = buildNotification(
            intent?.getStringExtra(EXTRA_KIND),
            intent?.getStringExtra(EXTRA_DETAIL),
            done,
            total,
        )
        val type = foregroundType(intent?.getStringArrayExtra(EXTRA_TYPES))

        if (!inForeground) {
            try {
                startInForeground(notification, type)
                inForeground = true
            } catch (e: RuntimeException) {
                // Android no deja pasar a primer plano desde segundo plano
                // (12 en adelante), ni con un tipo cuyo tope de horas ya se
                // gastó (15 en adelante), y cada versión lo dice con otra
                // excepción. Sin servicio el trabajo sigue igual, solo sin la
                // garantía.
                Log.w(TAG, "No se pudo pasar a primer plano", e)
                stopSelf()
            }
        } else if (type != currentType) {
            // Empezó o terminó un trabajo de otra clase —una transcripción
            // mientras se baja un modelo—: el servicio pasa a contar en los
            // tipos de lo que hay ahora.
            try {
                startInForeground(notification, type)
            } catch (e: RuntimeException) {
                // Sigue con los tipos que tenía: no protege menos que antes.
                Log.w(TAG, "No se pudo cambiar el tipo del servicio", e)
                notificationManager().notify(NOTIFICATION_ID, notification)
            }
        } else {
            notificationManager().notify(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun startInForeground(notification: Notification, type: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        currentType = type
    }

    /**
     * Android 15 en adelante: `dataSync` y `mediaProcessing` tienen cada uno
     * un tope de 6 horas cada 24. Al llegar, el sistema llama acá y le da al
     * servicio unos segundos para soltarse; si no lo hace, la app se cae.
     *
     * Se suelta entero —no se puede seguir con el otro tipo: volver a pasar a
     * primer plano desde segundo plano está prohibido— y se le avisa a Dart,
     * que deja de creerse protegido y lo vuelve a pedir cuando la persona
     * traiga la app al frente (ahí el tope vuelve a contar desde cero). El
     * trabajo en sí sigue mientras el sistema lo deje, y lo que quede a
     * medias se retoma al volver.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "Se acabaron las horas del servicio en primer plano (tipo $fgsType)")
        stopSelf()
        onStoppedBySystem?.invoke(typeName(fgsType))
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        inForeground = false
        currentType = 0
        super.onDestroy()
    }

    /**
     * El tipo de servicio para los trabajos en curso: `mediaProcessing` para
     * transcribir y reconocer páginas, `dataSync` para las descargas y la IA.
     *
     * Antes de Android 15 `mediaProcessing` no existe y todo va como
     * `dataSync`, el único tipo de entonces para trabajo largo sin
     * interacción.
     */
    private fun foregroundType(types: Array<String>?): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            return ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        var type = 0
        if (types?.contains(TYPE_MEDIA_PROCESSING) == true) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
        }
        if (types == null || types.contains(TYPE_DATA_SYNC) || type == 0) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        return type
    }

    private fun typeName(fgsType: Int): String = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
            (fgsType and ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING) != 0 ->
            TYPE_MEDIA_PROCESSING
        else -> TYPE_DATA_SYNC
    }

    private fun buildNotification(
        kind: String?,
        detail: String?,
        done: Int,
        total: Int,
    ): Notification {
        ensureChannel()

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val percent = if (total > 0) done * 100 / total else -1
        val text = when (kind) {
            KIND_ORGANIZING -> organizingText(detail, done, total)
            KIND_MODEL_DOWNLOAD -> {
                val model = getString(
                    when (detail) {
                        DETAIL_RELATIONS_MODEL -> R.string.long_work_model_relations
                        DETAIL_TRANSCRIPTION_MODEL -> R.string.long_work_model_transcription
                        else -> R.string.long_work_model_language
                    },
                )
                if (percent >= 0) {
                    getString(R.string.long_work_model_progress, model, percent)
                } else {
                    getString(R.string.long_work_model_starting, model)
                }
            }
            KIND_AUDIO_DOWNLOAD ->
                if (percent >= 0) {
                    getString(R.string.long_work_audio_progress, percent)
                } else {
                    getString(R.string.long_work_audio_starting)
                }
            KIND_SAMPLE_LIBRARY ->
                if (total > 0) {
                    getString(R.string.long_work_sample_library_progress, done, total)
                } else {
                    getString(R.string.long_work_starting)
                }
            else ->
                if (percent >= 0) {
                    getString(R.string.long_work_progress, percent)
                } else {
                    getString(R.string.long_work_starting)
                }
        }
        val title = getString(
            when (kind) {
                KIND_ORGANIZING -> R.string.long_work_organizing_title
                KIND_MODEL_DOWNLOAD -> R.string.long_work_model_title
                KIND_AUDIO_DOWNLOAD -> R.string.long_work_audio_title
                KIND_SAMPLE_LIBRARY -> R.string.long_work_sample_library_title
                else -> R.string.long_work_title
            },
        )

        return builder
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setProgress(total.coerceAtLeast(0), done.coerceIn(0, total.coerceAtLeast(0)), total <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .build()
    }

    /** La IA: con el cargador, la biblioteca que ya existía; si no, lo nuevo. */
    private fun organizingText(detail: String?, done: Int, total: Int): String =
        if (detail == DETAIL_WHILE_CHARGING) {
            if (total > 0) {
                getString(R.string.long_work_organizing_progress, done, total)
            } else {
                getString(R.string.long_work_organizing_starting)
            }
        } else {
            if (total > 0) {
                getString(R.string.long_work_organizing_new_progress, done, total)
            } else {
                getString(R.string.long_work_starting)
            }
        }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.long_work_channel),
                // Baja: sin sonido ni vibración, pero visible.
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun notificationManager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        private const val TAG = "LongWorkService"
        private const val CHANNEL_ID = "trabajo_largo"
        private const val NOTIFICATION_ID = 21
        private const val EXTRA_DONE = "done"
        private const val EXTRA_TOTAL = "total"
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_DETAIL = "detail"
        private const val EXTRA_TYPES = "types"

        /** El trabajo es la IA ordenando la biblioteca (F27). */
        const val KIND_ORGANIZING = "organizing"

        /** El trabajo es bajar un modelo; [EXTRA_DETAIL] dice cuál. */
        const val KIND_MODEL_DOWNLOAD = "model_download"

        /** El trabajo es bajar el audio de un video de YouTube (F24). */
        const val KIND_AUDIO_DOWNLOAD = "audio_download"

        /** El trabajo es cargar la biblioteca de ejemplo (solo en desarrollo). */
        const val KIND_SAMPLE_LIBRARY = "sample_library"

        private const val DETAIL_RELATIONS_MODEL = "relations_model"
        private const val DETAIL_TRANSCRIPTION_MODEL = "transcription_model"
        private const val DETAIL_WHILE_CHARGING = "while_charging"

        const val TYPE_DATA_SYNC = "data_sync"
        const val TYPE_MEDIA_PROCESSING = "media_processing"

        @Volatile private var running = false
        @Volatile private var inForeground = false

        /**
         * A quién avisarle que el sistema cortó el servicio ([onTimeout]),
         * con el tipo que se agotó. Lo pone la actividad, que tiene el canal
         * con Dart; sin actividad no hay Dart a quien avisarle.
         */
        @Volatile var onStoppedBySystem: ((String) -> Unit)? = null

        /**
         * Hay trabajo largo en curso: [done] de [total] (0 si no se sabe), de
         * [kind], con [detail] para el texto y los tipos de servicio [types]
         * ([TYPE_DATA_SYNC], [TYPE_MEDIA_PROCESSING]).
         */
        fun working(
            context: Context,
            kind: String?,
            detail: String?,
            done: Int,
            total: Int,
            types: List<String>?,
        ) {
            val intent = Intent(context, LongWorkService::class.java)
                .putExtra(EXTRA_KIND, kind)
                .putExtra(EXTRA_DETAIL, detail)
                .putExtra(EXTRA_DONE, done)
                .putExtra(EXTRA_TOTAL, total)
                .putExtra(EXTRA_TYPES, types?.toTypedArray())
            try {
                if (!running && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: RuntimeException) {
                // Pedido desde segundo plano, cuando Android ya no lo deja:
                // el trabajo sigue igual.
                Log.w(TAG, "No se pudo arrancar el servicio", e)
            }
        }

        /** Ya no hay trabajo largo: se va la notificación. */
        fun idle(context: Context) {
            if (!running) return
            context.stopService(Intent(context, LongWorkService::class.java))
        }
    }
}
