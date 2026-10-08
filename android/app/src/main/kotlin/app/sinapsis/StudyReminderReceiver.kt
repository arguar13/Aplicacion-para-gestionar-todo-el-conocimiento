package app.sinapsis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Quien recibe las llamadas del sistema para el aviso de repaso (F31):
 *
 * - la alarma diaria ([StudyReminder.ACTION_ALARM]): muestra el aviso y
 *   programa el de mañana;
 * - el teléfono que arranca, la app que se actualiza, y la hora o la zona
 *   horaria que cambian: el sistema borra las alarmas o las deja a la hora de
 *   antes, así que se vuelve a programar.
 *
 * Corre con la app cerrada y sin Dart: ver [StudyReminder].
 */
class StudyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            StudyReminder.ACTION_ALARM -> StudyReminder.onAlarm(context)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> StudyReminder.rearm(context)
        }
    }
}
