import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder.dart';

/// [StudyReminder] de las plataformas sin aviso (escritorio, web): no está
/// soportado y no hace nada.
class NullStudyReminder implements StudyReminder {
  const NullStudyReminder();

  @override
  bool get isSupported => false;

  @override
  Future<void> schedule(ReminderTime time) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<bool> isScheduled() async => false;

  @override
  Future<ReminderTime?> scheduledTime() async => null;

  @override
  Future<bool> hasNotificationPermission() async => false;

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<bool> openNotificationSettings() async => false;

  @override
  Future<void> setStudyCount(int count) async {}

  @override
  Stream<void> get openRequests => const Stream.empty();

  @override
  Future<bool> takePendingOpen() async => false;
}
