import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study_reminder/data/services/method_channel_study_reminder.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';

/// El lado Android del canal es Kotlin (`StudyReminderChannel`) y no se corre
/// acá: se prueba que Dart le habla con los nombres y argumentos que el
/// nativo espera, y que entiende lo que contesta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.sinapsis/study_reminder');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];
  var status = <String, Object?>{};
  var permissionAnswer = true;
  var pendingOpen = false;

  late MethodChannelStudyReminder reminder;

  setUp(() {
    calls.clear();
    status = {'scheduled': false, 'hour': 20, 'minute': 0, 'permission': false};
    permissionAnswer = true;
    pendingOpen = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'status':
          return status;
        case 'requestPermission':
          return permissionAnswer;
        case 'openNotificationSettings':
          return true;
        case 'takePendingOpen':
          final value = pendingOpen;
          pendingOpen = false;
          return value;
        default:
          return null;
      }
    });
    reminder = MethodChannelStudyReminder();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('está soportado', () {
    expect(reminder.isSupported, isTrue);
  });

  test('schedule manda la hora y el minuto', () async {
    await reminder.schedule(const ReminderTime(7, 45));

    expect(calls.single.method, 'schedule');
    expect(calls.single.arguments, {'hour': 7, 'minute': 45});
  });

  test('cancel', () async {
    await reminder.cancel();

    expect(calls.single.method, 'cancel');
  });

  test('isScheduled y scheduledTime leen el estado nativo', () async {
    expect(await reminder.isScheduled(), isFalse);
    expect(await reminder.scheduledTime(), isNull);

    status = {'scheduled': true, 'hour': 6, 'minute': 5, 'permission': true};

    expect(await reminder.isScheduled(), isTrue);
    expect(await reminder.scheduledTime(), const ReminderTime(6, 5));
  });

  test('una hora que no es una hora no se inventa', () async {
    status = {'scheduled': true, 'hour': 25, 'minute': 0};
    expect(await reminder.scheduledTime(), isNull);

    status = {'scheduled': true, 'hour': 'x', 'minute': 0};
    expect(await reminder.scheduledTime(), isNull);

    status = {'scheduled': true, 'hour': 10, 'minute': 60};
    expect(await reminder.scheduledTime(), isNull);
  });

  test('sin respuesta del nativo, nada está programado ni permitido', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(await reminder.isScheduled(), isFalse);
    expect(await reminder.hasNotificationPermission(), isFalse);
    expect(await reminder.requestNotificationPermission(), isFalse);
    expect(await reminder.takePendingOpen(), isFalse);
  });

  test('el permiso: consultarlo y pedirlo', () async {
    expect(await reminder.hasNotificationPermission(), isFalse);

    status = {...status, 'permission': true};
    expect(await reminder.hasNotificationPermission(), isTrue);

    permissionAnswer = false;
    expect(await reminder.requestNotificationPermission(), isFalse);
    permissionAnswer = true;
    expect(await reminder.requestNotificationPermission(), isTrue);
    expect(calls.where((c) => c.method == 'requestPermission'), hasLength(2));
  });

  test('abrir los ajustes de notificaciones', () async {
    expect(await reminder.openNotificationSettings(), isTrue);
    expect(calls.single.method, 'openNotificationSettings');
  });

  test('setStudyCount manda la cantidad', () async {
    await reminder.setStudyCount(14);
    await reminder.setStudyCount(0);
    await reminder.setStudyCount(-1);

    expect(calls.map((c) => c.method), everyElement('setStudyCount'));
    expect(calls.map((c) => (c.arguments as Map)['count']), [14, 0, -1]);
  });

  test('takePendingOpen devuelve true una sola vez', () async {
    pendingOpen = true;

    expect(await reminder.takePendingOpen(), isTrue);
    expect(await reminder.takePendingOpen(), isFalse);
  });

  test('el toque a la notificación llega como un pedido de abrir', () async {
    final received = <void>[];
    final subscription = reminder.openRequests.listen(received.add);
    addTearDown(subscription.cancel);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('openReview')),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('openReview')),
      (_) {},
    );

    expect(received, hasLength(2));
  });

  test('un mensaje del nativo que no se conoce no se atiende', () async {
    final replies = Completer<ByteData?>();

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('otraCosa')),
      replies.complete,
    );

    // El canal contesta «no implementado» (sin cuerpo) y no confunde el
    // mensaje con un pedido de abrir.
    expect(await replies.future, isNull);
  });
}
