import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';

void main() {
  group('ReminderTime', () {
    test('la hora de siempre es las 20:00', () {
      expect(ReminderTime.standard.format24(), '20:00');
    });

    test('minutos desde la medianoche, en las dos direcciones', () {
      expect(const ReminderTime(0, 0).minutesOfDay, 0);
      expect(const ReminderTime(7, 5).minutesOfDay, 425);
      expect(const ReminderTime(23, 59).minutesOfDay, 1439);
      for (final minutes in [0, 1, 59, 60, 425, 1200, 1439]) {
        expect(ReminderTime.fromMinutesOfDay(minutes).minutesOfDay, minutes);
      }
    });

    test('unos minutos que no son de un día se rechazan', () {
      expect(() => ReminderTime.fromMinutesOfDay(-1), throwsRangeError);
      expect(() => ReminderTime.fromMinutesOfDay(1440), throwsRangeError);
    });

    test('se muestra con dos cifras', () {
      expect(const ReminderTime(7, 5).format24(), '07:05');
      expect(ReminderTime.standard.format24(), '20:00');
      expect(const ReminderTime(0, 0).format24(), '00:00');
    });

    test('igualdad por hora y minuto', () {
      expect(const ReminderTime(9, 30), const ReminderTime(9, 30));
      expect(const ReminderTime(9, 30), isNot(const ReminderTime(9, 31)));
      expect(
        const ReminderTime(9, 30).hashCode,
        const ReminderTime(9, 30).hashCode,
      );
    });

    group('nextOccurrence', () {
      const eight = ReminderTime(8, 0);

      test('si todavía no pasó hoy, es hoy', () {
        expect(
          eight.nextOccurrence(DateTime(2026, 3, 10, 7, 59, 59)),
          DateTime(2026, 3, 10, 8),
        );
      });

      test('si es justo ahora, es mañana', () {
        expect(
          eight.nextOccurrence(DateTime(2026, 3, 10, 8)),
          DateTime(2026, 3, 11, 8),
        );
      });

      test('si ya pasó, es mañana', () {
        expect(
          eight.nextOccurrence(DateTime(2026, 3, 10, 21, 30)),
          DateTime(2026, 3, 11, 8),
        );
      });

      test('cruza el fin de mes y de año', () {
        expect(
          eight.nextOccurrence(DateTime(2026, 12, 31, 23)),
          DateTime(2027, 1, 1, 8),
        );
        expect(
          eight.nextOccurrence(DateTime(2028, 2, 28, 9)),
          DateTime(2028, 2, 29, 8),
        );
      });

      test('a medianoche', () {
        const midnight = ReminderTime(0, 0);
        expect(
          midnight.nextOccurrence(DateTime(2026, 3, 10, 12)),
          DateTime(2026, 3, 11),
        );
        expect(
          midnight.nextOccurrence(DateTime(2026, 3, 10)),
          DateTime(2026, 3, 11),
        );
      });
    });
  });
}
