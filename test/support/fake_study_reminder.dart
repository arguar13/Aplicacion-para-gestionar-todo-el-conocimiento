import 'dart:async';

import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_settings.dart';

/// Un [StudyReminder] que recuerda lo que se le pide, sin sistema operativo.
class FakeStudyReminder implements StudyReminder {
  FakeStudyReminder({this.supported = true, this.permission = false});

  final bool supported;
  bool permission;

  /// Qué responde el sistema cuando se le pide el permiso.
  bool grantsWhenAsked = true;

  ReminderTime? scheduled;
  final scheduleCalls = <ReminderTime>[];
  int cancelCalls = 0;
  int permissionRequests = 0;
  final counts = <int>[];
  Object? failOnCount;

  /// Los toques de la notificación con la app abierta: `add` simula uno.
  final openController = StreamController<void>.broadcast();

  /// Si la app se abrió desde la notificación y nadie lo atendió todavía.
  bool pendingOpen = false;

  @override
  bool get isSupported => supported;

  @override
  Future<void> schedule(ReminderTime time) async {
    scheduleCalls.add(time);
    scheduled = time;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    scheduled = null;
  }

  @override
  Future<bool> isScheduled() async => scheduled != null;

  @override
  Future<ReminderTime?> scheduledTime() async => scheduled;

  @override
  Future<bool> hasNotificationPermission() async => permission;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    return permission = grantsWhenAsked;
  }

  @override
  Future<bool> openNotificationSettings() async => true;

  @override
  Future<void> setStudyCount(int count) async {
    final failure = failOnCount;
    // Tira lo que la prueba pida, sea una excepción o un error.
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    counts.add(count);
  }

  @override
  Stream<void> get openRequests => openController.stream;

  @override
  Future<bool> takePendingOpen() async {
    final pending = pendingOpen;
    pendingOpen = false;
    return pending;
  }
}

class FakeSettings implements StudyReminderSettings {
  @override
  bool enabled = false;

  @override
  ReminderTime time = ReminderTime.standard;

  int saves = 0;

  @override
  Future<void> save({required bool enabled, required ReminderTime time}) async {
    saves++;
    this.enabled = enabled;
    this.time = time;
  }
}
