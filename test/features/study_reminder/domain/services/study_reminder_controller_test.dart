import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_controller.dart';

import '../../../../support/fake_study_reminder.dart';
import '../../../../support/silent_logger.dart';

void main() {
  late FakeStudyReminder platform;
  late FakeSettings settings;
  late StudyReminderController controller;

  void build({bool supported = true, bool permission = false}) {
    platform = FakeStudyReminder(supported: supported, permission: permission);
    settings = FakeSettings();
    controller = StudyReminderController(
      platform: platform,
      settings: settings,
      logger: const SilentLogger(),
    );
  }

  setUp(build);

  group('prender', () {
    test('pide el permiso en ese momento, programa y guarda', () async {
      final result = await controller.enable(time: const ReminderTime(8, 30));

      expect(result, StudyReminderEnableResult.enabled);
      expect(platform.permissionRequests, 1);
      expect(platform.scheduled, const ReminderTime(8, 30));
      expect(settings.enabled, isTrue);
      expect(settings.time, const ReminderTime(8, 30));
    });

    test('si ya tiene el permiso no lo vuelve a pedir', () async {
      build(permission: true);

      await controller.enable();

      expect(platform.permissionRequests, 0);
      expect(platform.scheduled, ReminderTime.standard);
    });

    test('sin permiso no queda prendido nada', () async {
      platform.grantsWhenAsked = false;

      final result = await controller.enable();

      expect(result, StudyReminderEnableResult.permissionDenied);
      expect(platform.scheduled, isNull);
      expect(platform.scheduleCalls, isEmpty);
      expect(settings.enabled, isFalse);
      expect(settings.saves, 0);
    });

    test('en una plataforma sin aviso no hace nada', () async {
      build(supported: false);

      final result = await controller.enable();

      expect(result, StudyReminderEnableResult.unsupported);
      expect(platform.permissionRequests, 0);
      expect(settings.enabled, isFalse);
    });

    test('con la cantidad, el primer texto ya la tiene', () async {
      await controller.enable(studyCount: 12);

      expect(platform.counts, [12]);
    });

    test('sin ella, no se manda ninguna', () async {
      await controller.enable();

      expect(platform.counts, isEmpty);
    });

    test('apagado por defecto', () async {
      final state = await controller.load();

      expect(state.enabled, isFalse);
      expect(state.time, ReminderTime.standard);
      expect(state.scheduled, isFalse);
      expect(state.needsAttention, isFalse);
    });
  });

  group('cambiar la hora y apagar', () {
    test('con el aviso prendido, reprograma', () async {
      await controller.enable(time: const ReminderTime(9, 0));
      platform.scheduleCalls.clear();

      await controller.changeTime(const ReminderTime(21, 15));

      expect(platform.scheduleCalls, [const ReminderTime(21, 15)]);
      expect(settings.time, const ReminderTime(21, 15));
      expect(settings.enabled, isTrue);
    });

    test('con el aviso apagado, solo la elige', () async {
      await controller.changeTime(const ReminderTime(7, 0));

      expect(platform.scheduleCalls, isEmpty);
      expect(settings.time, const ReminderTime(7, 0));
      expect(settings.enabled, isFalse);
    });

    test('apagar cancela, y conserva la hora elegida', () async {
      await controller.enable(time: const ReminderTime(9, 0));

      await controller.disable();

      expect(platform.cancelCalls, 1);
      expect(platform.scheduled, isNull);
      expect(settings.enabled, isFalse);
      expect(settings.time, const ReminderTime(9, 0));
    });

    test('apagar sin plataforma tampoco rompe', () async {
      build(supported: false);

      await controller.disable();

      expect(platform.cancelCalls, 0);
      expect(settings.enabled, isFalse);
    });
  });

  group('el estado', () {
    test('prendido y programado, con permiso: todo bien', () async {
      await controller.enable();

      final state = await controller.load();

      expect(state.supported, isTrue);
      expect(state.enabled, isTrue);
      expect(state.scheduled, isTrue);
      expect(state.permissionGranted, isTrue);
      expect(state.needsAttention, isFalse);
    });

    test('si quitaron el permiso en ajustes, pide atención', () async {
      await controller.enable();
      platform.permission = false;

      final state = await controller.load();

      expect(state.enabled, isTrue);
      expect(state.needsAttention, isTrue);
    });

    test('prendido pero sin programación, pide atención', () async {
      await controller.enable();
      platform.scheduled = null;

      expect((await controller.load()).needsAttention, isTrue);
    });

    test(
      'en una plataforma sin aviso, no soportado y nunca prendido',
      () async {
        build(supported: false);
        settings.enabled = true;

        final state = await controller.load();

        expect(state.supported, isFalse);
        expect(state.enabled, isFalse);
        expect(state.needsAttention, isFalse);
      },
    );

    test('dos estados iguales son iguales', () async {
      expect(await controller.load(), await controller.load());
    });
  });

  group('restaurar al abrir la app', () {
    test(
      'si está prendido y programado con la misma hora, no toca nada',
      () async {
        await controller.enable(time: const ReminderTime(9, 0));
        platform.scheduleCalls.clear();

        await controller.restore();

        expect(platform.scheduleCalls, isEmpty);
      },
    );

    test('si se perdió la programación, la vuelve a poner', () async {
      await controller.enable(time: const ReminderTime(9, 0));
      platform.scheduled = null;
      platform.scheduleCalls.clear();

      await controller.restore();

      expect(platform.scheduleCalls, [const ReminderTime(9, 0)]);
    });

    test('si quedó con otra hora, la corrige', () async {
      await controller.enable(time: const ReminderTime(9, 0));
      platform.scheduled = const ReminderTime(3, 0);
      platform.scheduleCalls.clear();

      await controller.restore();

      expect(platform.scheduleCalls, [const ReminderTime(9, 0)]);
    });

    test('apagado, no programa nada', () async {
      await controller.restore();

      expect(platform.scheduleCalls, isEmpty);
    });

    test('en una plataforma sin aviso, no hace nada', () async {
      build(supported: false);
      settings.enabled = true;

      await controller.restore();

      expect(platform.scheduleCalls, isEmpty);
    });
  });

  group('la cantidad de tarjetas', () {
    test('la manda, y no repite la misma', () async {
      await controller.updateStudyCount(5);
      await controller.updateStudyCount(5);
      await controller.updateStudyCount(7);
      await controller.updateStudyCount(0);
      await controller.updateStudyCount(0);

      expect(platform.counts, [5, 7, 0]);
    });

    test(
      'un fallo del sistema no llega a quien llama, y se reintenta',
      () async {
        platform.failOnCount = PlatformException(code: 'x');

        await controller.updateStudyCount(5);
        expect(platform.counts, isEmpty);

        platform.failOnCount = null;
        await controller.updateStudyCount(5);
        expect(platform.counts, [5]);
      },
    );

    test('que no haya nadie del otro lado tampoco', () async {
      platform.failOnCount = MissingPluginException();

      await controller.updateStudyCount(5);

      expect(platform.counts, isEmpty);
    });

    test('un error que no es del sistema sí se propaga', () async {
      platform.failOnCount = StateError('un bug');

      await expectLater(controller.updateStudyCount(5), throwsStateError);
    });

    test('sin plataforma no manda nada', () async {
      build(supported: false);

      await controller.updateStudyCount(5);

      expect(platform.counts, isEmpty);
    });
  });
}
