import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/study_reminder/data/services/prefs_study_reminder_settings.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';

void main() {
  Future<PrefsStudyReminderSettings> settingsWith(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    return PrefsStudyReminderSettings(await SharedPreferences.getInstance());
  }

  test('apagado y a la hora de siempre cuando nunca se tocó', () async {
    final settings = await settingsWith({});

    expect(settings.enabled, isFalse);
    expect(settings.time, ReminderTime.standard);
  });

  test('guarda si está prendido y la hora, y los vuelve a leer', () async {
    final prefs = await settingsWith({});

    await prefs.save(enabled: true, time: const ReminderTime(6, 45));

    expect(prefs.enabled, isTrue);
    expect(prefs.time, const ReminderTime(6, 45));

    // Con otra instancia sobre los mismos datos, como al reabrir la app.
    final reopened = PrefsStudyReminderSettings(
      await SharedPreferences.getInstance(),
    );
    expect(reopened.enabled, isTrue);
    expect(reopened.time, const ReminderTime(6, 45));
  });

  test('apagar conserva la hora', () async {
    final settings = await settingsWith({});
    await settings.save(enabled: true, time: const ReminderTime(6, 45));

    await settings.save(enabled: false, time: settings.time);

    expect(settings.enabled, isFalse);
    expect(settings.time, const ReminderTime(6, 45));
  });

  test('la medianoche y el último minuto del día son horas válidas', () async {
    final settings = await settingsWith({});

    await settings.save(enabled: true, time: const ReminderTime(0, 0));
    expect(settings.time, const ReminderTime(0, 0));

    await settings.save(enabled: true, time: const ReminderTime(23, 59));
    expect(settings.time, const ReminderTime(23, 59));
  });

  test(
    'un valor guardado que ya no es una hora vuelve a la de siempre',
    () async {
      for (final bad in [-5, 1440, 99999]) {
        final settings = await settingsWith({
          PrefsStudyReminderSettings.minutesKey: bad,
        });
        expect(settings.time, ReminderTime.standard, reason: '$bad');
      }
    },
  );

  test('usa claves propias, sin pisar otras', () {
    expect(PrefsStudyReminderSettings.enabledKey, 'study_reminder_enabled');
    expect(PrefsStudyReminderSettings.minutesKey, 'study_reminder_minutes');
  });
}
