import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/study_reminder/data/services/method_channel_study_reminder.dart';
import 'package:sinapsis/features/study_reminder/data/services/null_study_reminder.dart';
import 'package:sinapsis/features/study_reminder/data/services/prefs_study_reminder_settings.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_controller.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_settings.dart';

/// El aviso del sistema: en Android, la alarma y la notificación; en el
/// resto, uno que no hace nada ([StudyReminder.isSupported] es `false`).
final studyReminderProvider = Provider<StudyReminder>(
  (ref) => kIsWeb || defaultTargetPlatform != TargetPlatform.android
      ? const NullStudyReminder()
      : MethodChannelStudyReminder(),
);

final studyReminderSettingsProvider = Provider<StudyReminderSettings>(
  (ref) => PrefsStudyReminderSettings(ref.watch(sharedPreferencesProvider)),
);

/// El aviso de punta a punta. Llamar a `updateStudyCount` cuando cambie cuántas
/// tarjetas hay para repasar, y a `restore` al abrir la app.
final studyReminderControllerProvider = Provider<StudyReminderController>(
  (ref) => StudyReminderController(
    platform: ref.watch(studyReminderProvider),
    settings: ref.watch(studyReminderSettingsProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// El estado del aviso para la pantalla de ajustes, con las acciones que lo
/// cambian. Cada acción vuelve a leer el estado al terminar.
class StudyReminderNotifier extends AsyncNotifier<StudyReminderState> {
  StudyReminderController get _controller =>
      ref.read(studyReminderControllerProvider);

  @override
  Future<StudyReminderState> build() => _controller.load();

  /// Prende el aviso (pide el permiso de notificaciones). Devuelve cómo
  /// terminó, para que la pantalla explique si no se pudo.
  Future<StudyReminderEnableResult> enable({
    ReminderTime? time,
    int? studyCount,
  }) async {
    final result = await _controller.enable(time: time, studyCount: studyCount);
    state = AsyncData(await _controller.load());
    return result;
  }

  Future<void> changeTime(ReminderTime time) async {
    await _controller.changeTime(time);
    state = AsyncData(await _controller.load());
  }

  Future<void> disable() async {
    await _controller.disable();
    state = AsyncData(await _controller.load());
  }

  /// Vuelve a leer el estado: al volver de los ajustes del sistema, donde se
  /// pudo conceder o quitar el permiso.
  Future<void> refresh() async {
    state = AsyncData(await _controller.load());
  }

  Future<bool> openNotificationSettings() =>
      ref.read(studyReminderProvider).openNotificationSettings();
}

final studyReminderStateProvider =
    AsyncNotifierProvider<StudyReminderNotifier, StudyReminderState>(
      StudyReminderNotifier.new,
    );

/// Cada vez que la persona toca la notificación con la app abierta. Quien
/// lo escuche lleva a la pestaña Repasar. Al arrancar desde cero, además,
/// hay que preguntar `takePendingOpen` una vez.
final studyReminderOpenRequestsProvider = StreamProvider<void>(
  (ref) => ref.watch(studyReminderProvider).openRequests,
);
