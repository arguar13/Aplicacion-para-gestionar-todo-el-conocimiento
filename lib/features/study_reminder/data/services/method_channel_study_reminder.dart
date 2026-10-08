import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder.dart';

/// [StudyReminder] en Android, por el canal `app.sinapsis/study_reminder` (ver
/// `StudyReminderChannel`): una alarma del sistema que repite cada día y una
/// notificación, sin dependencias nuevas.
///
/// Del canal hacia Dart llega un solo mensaje, `openReview`, cuando se toca la
/// notificación con la app ya andando. Quien lo escucha tiene que haberse
/// suscripto a [openRequests] antes de que llegue; el toque que abre la app
/// desde cero queda guardado del lado nativo y se recoge con [takePendingOpen].
class MethodChannelStudyReminder implements StudyReminder {
  MethodChannelStudyReminder({
    MethodChannel channel = const MethodChannel('app.sinapsis/study_reminder'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _openRequests = StreamController<void>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Future<void> schedule(ReminderTime time) => _channel.invokeMethod<void>(
    'schedule',
    {'hour': time.hour, 'minute': time.minute},
  );

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Future<bool> isScheduled() async => (await _status())?['scheduled'] == true;

  @override
  Future<ReminderTime?> scheduledTime() async {
    final status = await _status();
    if (status?['scheduled'] != true) return null;
    final hour = status?['hour'];
    final minute = status?['minute'];
    if (hour is! int || minute is! int) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return ReminderTime(hour, minute);
  }

  @override
  Future<bool> hasNotificationPermission() async =>
      (await _status())?['permission'] == true;

  @override
  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<bool> openNotificationSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;

  @override
  Future<void> setStudyCount(int count) =>
      _channel.invokeMethod<void>('setStudyCount', {'count': count});

  @override
  Stream<void> get openRequests => _openRequests.stream;

  @override
  Future<bool> takePendingOpen() async =>
      await _channel.invokeMethod<bool>('takePendingOpen') ?? false;

  Future<Map<String, Object?>?> _status() =>
      _channel.invokeMapMethod<String, Object?>('status');

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'openReview') {
      _openRequests.add(null);
      return null;
    }
    throw MissingPluginException('Método desconocido: ${call.method}');
  }
}
