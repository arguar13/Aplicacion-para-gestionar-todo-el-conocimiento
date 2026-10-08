import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_settings.dart';

/// [StudyReminderSettings] en `SharedPreferences`: dos claves, si está prendido
/// y la hora como minutos desde la medianoche.
class PrefsStudyReminderSettings implements StudyReminderSettings {
  const PrefsStudyReminderSettings(this._prefs);

  static const enabledKey = 'study_reminder_enabled';
  static const minutesKey = 'study_reminder_minutes';

  final SharedPreferences _prefs;

  @override
  bool get enabled => _prefs.getBool(enabledKey) ?? false;

  @override
  ReminderTime get time {
    final minutes = _prefs.getInt(minutesKey);
    // Un valor que ya no es una hora (un dato viejo o a mano) vuelve a la
    // hora de siempre en vez de romper la pantalla de ajustes.
    if (minutes == null || minutes < 0 || minutes >= 24 * 60) {
      return ReminderTime.standard;
    }
    return ReminderTime.fromMinutesOfDay(minutes);
  }

  @override
  Future<void> save({required bool enabled, required ReminderTime time}) async {
    await _prefs.setInt(minutesKey, time.minutesOfDay);
    await _prefs.setBool(enabledKey, enabled);
  }
}
