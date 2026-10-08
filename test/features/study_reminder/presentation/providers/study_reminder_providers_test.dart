import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_controller.dart';
import 'package:sinapsis/features/study_reminder/presentation/providers/study_reminder_providers.dart';

import '../../../../support/fake_study_reminder.dart';
import '../../../../support/silent_logger.dart';

void main() {
  late FakeStudyReminder platform;
  late FakeSettings settings;
  late ProviderContainer container;

  setUp(() {
    platform = FakeStudyReminder();
    settings = FakeSettings();
    container = ProviderContainer(
      overrides: [
        studyReminderProvider.overrideWithValue(platform),
        studyReminderSettingsProvider.overrideWithValue(settings),
        appLoggerProvider.overrideWithValue(const SilentLogger()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('arranca apagado', () async {
    final state = await container.read(studyReminderStateProvider.future);

    expect(state.enabled, isFalse);
    expect(state.supported, isTrue);
  });

  test('prender cambia el estado que ve la pantalla', () async {
    await container.read(studyReminderStateProvider.future);
    final notifier = container.read(studyReminderStateProvider.notifier);

    final result = await notifier.enable(time: const ReminderTime(8, 0));

    expect(result, StudyReminderEnableResult.enabled);
    final state = container.read(studyReminderStateProvider).requireValue;
    expect(state.enabled, isTrue);
    expect(state.time, const ReminderTime(8, 0));
    expect(state.scheduled, isTrue);
  });

  test('si no se concede el permiso, el estado sigue apagado', () async {
    platform.grantsWhenAsked = false;
    await container.read(studyReminderStateProvider.future);
    final notifier = container.read(studyReminderStateProvider.notifier);

    final result = await notifier.enable();

    expect(result, StudyReminderEnableResult.permissionDenied);
    expect(
      container.read(studyReminderStateProvider).requireValue.enabled,
      isFalse,
    );
  });

  test('cambiar la hora y apagar', () async {
    await container.read(studyReminderStateProvider.future);
    final notifier = container.read(studyReminderStateProvider.notifier);
    await notifier.enable(time: const ReminderTime(8, 0));

    await notifier.changeTime(const ReminderTime(9, 15));
    expect(
      container.read(studyReminderStateProvider).requireValue.time,
      const ReminderTime(9, 15),
    );
    expect(platform.scheduled, const ReminderTime(9, 15));

    await notifier.disable();
    final state = container.read(studyReminderStateProvider).requireValue;
    expect(state.enabled, isFalse);
    expect(state.scheduled, isFalse);
    expect(state.time, const ReminderTime(9, 15));
  });

  test(
    'refresh ve el permiso que se concedió en los ajustes del sistema',
    () async {
      await container.read(studyReminderStateProvider.future);
      final notifier = container.read(studyReminderStateProvider.notifier);
      await notifier.enable();
      platform.permission = false;
      await notifier.refresh();
      expect(
        container.read(studyReminderStateProvider).requireValue.needsAttention,
        isTrue,
      );

      platform.permission = true;
      await notifier.refresh();

      expect(
        container.read(studyReminderStateProvider).requireValue.needsAttention,
        isFalse,
      );
    },
  );

  test('el controlador de los providers cuenta las tarjetas', () async {
    await container.read(studyReminderControllerProvider).updateStudyCount(9);

    expect(platform.counts, [9]);
  });

  test('abrir los ajustes de notificaciones pasa por la plataforma', () async {
    await container.read(studyReminderStateProvider.future);

    expect(
      await container
          .read(studyReminderStateProvider.notifier)
          .openNotificationSettings(),
      isTrue,
    );
  });

  test('en una plataforma sin aviso: no soportado', () async {
    final unsupported = ProviderContainer(
      overrides: [
        studyReminderProvider.overrideWithValue(
          FakeStudyReminder(supported: false),
        ),
        studyReminderSettingsProvider.overrideWithValue(FakeSettings()),
        appLoggerProvider.overrideWithValue(const SilentLogger()),
      ],
    );
    addTearDown(unsupported.dispose);

    final state = await unsupported.read(studyReminderStateProvider.future);

    expect(state.supported, isFalse);
  });
}
