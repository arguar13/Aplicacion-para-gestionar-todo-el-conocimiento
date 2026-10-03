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
 * se transcribe un audio de horas o se reconocen las páginas de un libro
 * escaneado, una notificación con el avance, y el sistema no congela ni
 * mata la app por estar en segundo plano —HyperOS lo hacía a los pocos
 * minutos—.
 *
 * Lo comparten varios dueños (F27): el procesamiento y la IA que ordena la
 * biblioteca existente con el cargador. Quién se ve y cuándo se apaga lo
 * decide Dart (`LongWorkCoordinator`); acá llega una sola cosa por vez, con
 * de quién es ([KIND_ORGANIZING] o el procesamiento) para el texto.
 *
 * No hace el trabajo: el trabajo lo hace Dart, en el proceso de la app. El
 * servicio solo mantiene vivo ese proceso y muestra cuánto va. Por eso, si
 * el usuario cierra la app desde "recientes", el servicio se va con ella:
 * sin la app no hay quién trabaje, y lo hecho ya quedó guardado para
 * retomarlo al volver.
 */
class LongWorkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val done = intent?.getIntExtra(EXTRA_DONE, 0) ?: 0
        val total = intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0
        val organizing = intent?.getStringExtra(EXTRA_KIND) == KIND_ORGANIZING
        val notification = buildNotification(organizing, done, total)

        if (!inForeground) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, notification, foregroundType())
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                inForeground = true
            } catch (e: RuntimeException) {
                // Android no deja pasar a primer plano desde segundo plano
                // (12 en adelante) y cada versión lo dice con otra excepción.
                // Sin servicio el trabajo sigue igual, solo sin la garantía.
                Log.w(TAG, "No se pudo pasar a primer plano", e)
                stopSelf()
            }
        } else {
            notificationManager().notify(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        inForeground = false
        super.onDestroy()
    }

    private fun foregroundType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            // Hecho para esto: procesar audio, video o imágenes (Android 15).
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }

    private fun buildNotification(organizing: Boolean, done: Int, total: Int): Notification {
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

        val text = when {
            organizing && total > 0 ->
                getString(R.string.long_work_organizing_progress, done, total)
            organizing -> getString(R.string.long_work_organizing_starting)
            total > 0 -> getString(R.string.long_work_progress, done * 100 / total)
            else -> getString(R.string.long_work_starting)
        }
        val title = getString(
            if (organizing) R.string.long_work_organizing_title else R.string.long_work_title,
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

        /** El trabajo es la IA ordenando la biblioteca (F27). */
        const val KIND_ORGANIZING = "organizing"

        @Volatile private var running = false
        @Volatile private var inForeground = false

        /**
         * Hay trabajo largo en curso: [done] de [total] (0 si no se sabe), de
         * [kind] —el procesamiento o [KIND_ORGANIZING]—.
         */
        fun working(context: Context, kind: String?, done: Int, total: Int) {
            val intent = Intent(context, LongWorkService::class.java)
                .putExtra(EXTRA_KIND, kind)
                .putExtra(EXTRA_DONE, done)
                .putExtra(EXTRA_TOTAL, total)
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
