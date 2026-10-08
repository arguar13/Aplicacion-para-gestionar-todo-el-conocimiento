package app.sinapsis

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import java.util.Calendar

/**
 * El aviso diario para repasar (F31): una alarma del sistema a la hora que la
 * persona eligió y una notificación que la lleva a la pestaña Repasar.
 *
 * **Sin Dart.** El aviso suena con la app cerrada y el teléfono dormido, así
 * que no puede preguntarle a la base cuántas tarjetas hay: eso lo cuenta la
 * app y lo deja en las preferencias nativas ([setStudyCount]) cada vez que
 * cambia; el aviso dice lo último que se guardó. También guarda acá, por la
 * misma razón, si está prendido y a qué hora, para poder reprogramarse solo al
 * reiniciar el teléfono y al abrir la app ([StudyReminderReceiver],
 * [rearm]). La verdad de lo elegido sigue siendo la de Dart
 * (`StudyReminderSettings`), que corrige esta copia con `restore`.
 *
 * **La alarma** es `setAndAllowWhileIdle`: inexacta —el sistema puede
 * correrla unos minutos— y que suena aunque el teléfono esté en reposo
 * profundo (Doze), sin el permiso de alarmas exactas, que Android 12 en
 * adelante reserva para despertadores y calendarios y Play no concede a una
 * app de estudio. No es una alarma repetida del sistema (`setInexactRepeating`
 * no suena en Doze): cada vez que suena programa la del día siguiente, y
 * también lo hace al reiniciar, al abrir la app y cuando cambian la hora o la
 * zona horaria.
 *
 * **Qué dice.** Con N > 0 tarjetas: «Tenés N tarjetas para repasar». Con 0 no
 * se muestra nada ese día: la app avisó que no hay nada para repasar y una
 * notificación vacía solo molesta. Con la cantidad desconocida (nunca se
 * guardó una) se muestra un texto sin número: la persona pidió el aviso y
 * callarlo en silencio por un olvido de la app sería peor que uno de más.
 */
object StudyReminder {
    private const val TAG = "StudyReminder"
    private const val PREFS = "study_reminder"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_COUNT = "count"

    private const val CHANNEL_ID = "repaso"
    private const val NOTIFICATION_ID = 31
    private const val ALARM_REQUEST = 31
    private const val OPEN_REQUEST = 32

    /** Cuántas tarjetas hay: aún no se guardó ninguna. */
    const val COUNT_UNKNOWN = -1

    const val ACTION_ALARM = "app.sinapsis.STUDY_REMINDER"

    /** El extra del intent de la notificación que pide abrir Repasar. */
    const val EXTRA_OPEN_REVIEW = "app.sinapsis.OPEN_REVIEW"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

    fun hour(context: Context): Int = prefs(context).getInt(KEY_HOUR, 20)

    fun minute(context: Context): Int = prefs(context).getInt(KEY_MINUTE, 0)

    fun studyCount(context: Context): Int = prefs(context).getInt(KEY_COUNT, COUNT_UNKNOWN)

    /** Guarda cuántas tarjetas hay. Con 0, quita el aviso que ya esté a la vista. */
    fun setStudyCount(context: Context, count: Int) {
        prefs(context).edit().putInt(KEY_COUNT, count).apply()
        if (count == 0) notificationManager(context).cancel(NOTIFICATION_ID)
    }

    /** Prende el aviso a las [hour]:[minute] y programa la próxima alarma. */
    fun schedule(context: Context, hour: Int, minute: Int) {
        prefs(context).edit()
            .putBoolean(KEY_ENABLED, true)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .apply()
        armAlarm(context)
    }

    /** Apaga el aviso: cancela la alarma y la notificación que haya. */
    fun cancel(context: Context) {
        prefs(context).edit().putBoolean(KEY_ENABLED, false).apply()
        val pending = alarmIntent(context, PendingIntent.FLAG_UPDATE_CURRENT)
        alarmManager(context).cancel(pending)
        // Sin esto el PendingIntent seguiría existiendo y `isArmed` diría que
        // la alarma está puesta.
        pending.cancel()
        notificationManager(context).cancel(NOTIFICATION_ID)
    }

    /**
     * Si el sistema tiene la alarma puesta. Android no deja leer las alarmas
     * de una app sin un permiso especial; lo que sí deja es preguntar si existe
     * el `PendingIntent` de la alarma sin crearlo (`FLAG_NO_CREATE`), que nace
     * al programarla y desaparece al cancelarla, al reiniciar el teléfono y al
     * forzar la detención de la app: las tres cosas que dejan sin alarma.
     */
    fun isArmed(context: Context): Boolean = PendingIntent.getBroadcast(
        context,
        ALARM_REQUEST,
        alarmBaseIntent(context),
        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
    ) != null

    /**
     * Vuelve a poner la alarma si el aviso está prendido. Se llama al abrir la
     * app, al reiniciar el teléfono, al actualizar la app y al cambiar la hora
     * o la zona horaria: en todos esos casos la alarma pudo perderse o quedar
     * a la hora de antes. Poner la misma alarma dos veces la reemplaza, no la
     * duplica.
     */
    fun rearm(context: Context) {
        if (isEnabled(context)) armAlarm(context)
    }

    /** Suena la alarma: muestra el aviso si corresponde y programa el de mañana. */
    fun onAlarm(context: Context) {
        if (!isEnabled(context)) return
        try {
            if (shouldShow(studyCount(context))) show(context, studyCount(context))
        } finally {
            // Pase lo que pase con la notificación, mañana tiene que volver a
            // sonar.
            armAlarm(context)
        }
    }

    /** Si con [count] tarjetas hay algo que avisar. Ver la explicación arriba. */
    internal fun shouldShow(count: Int): Boolean = count != 0

    /**
     * La próxima vez que ocurre [hour]:[minute] después de [now]: hoy si falta,
     * mañana si ya pasó o es justo ahora. Con la hora de la pared del reloj,
     * así que un cambio de horario no la corre.
     */
    internal fun nextTriggerMillis(now: Long, hour: Int, minute: Int): Long {
        val calendar = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (calendar.timeInMillis <= now) calendar.add(Calendar.DAY_OF_YEAR, 1)
        return calendar.timeInMillis
    }

    /** Si el sistema deja mostrar notificaciones de la app (permiso y ajustes). */
    fun notificationsAllowed(context: Context): Boolean =
        notificationManager(context).areNotificationsEnabled()

    private fun armAlarm(context: Context) {
        val trigger = nextTriggerMillis(System.currentTimeMillis(), hour(context), minute(context))
        try {
            alarmManager(context).setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                trigger,
                alarmIntent(context, PendingIntent.FLAG_UPDATE_CURRENT),
            )
        } catch (e: SecurityException) {
            // Algunos fabricantes restringen las alarmas de las apps; el aviso
            // no es lo bastante importante para romper lo que lo pidió.
            Log.w(TAG, "No se pudo programar el aviso de repaso", e)
        }
    }

    private fun alarmBaseIntent(context: Context): Intent =
        Intent(context, StudyReminderReceiver::class.java).setAction(ACTION_ALARM)

    private fun alarmIntent(context: Context, flag: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            alarmBaseIntent(context),
            flag or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun show(context: Context, count: Int) {
        if (!notificationsAllowed(context)) return
        ensureChannel(context)

        val open = PendingIntent.getActivity(
            context,
            OPEN_REQUEST,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(EXTRA_OPEN_REVIEW, true),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val text = if (count > 0) {
            context.resources.getQuantityString(R.plurals.study_reminder_text, count, count)
        } else {
            context.getString(R.string.study_reminder_text_unknown)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(context.getString(R.string.study_reminder_title))
            .setContentText(text)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        notificationManager(context).notify(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager(context)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.study_reminder_channel),
                // Normal: con su sonido, pero sin asomarse sobre lo que se esté
                // haciendo. Es un recordatorio, no una urgencia.
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun notificationManager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
