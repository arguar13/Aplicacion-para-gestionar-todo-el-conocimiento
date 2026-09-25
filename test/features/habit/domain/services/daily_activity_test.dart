import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/habit/domain/services/daily_activity.dart';

/// `dailyActivity` (F17, D8): pura.
void main() {
  final today = DateTime(2026, 9, 25, 14);

  test('sin repasos, los 84 días aparecen igual, todos en cero', () {
    final days = dailyActivity(const [], today: today);

    expect(days, hasLength(kReviewHistoryDays));
    for (final day in days) {
      expect(day.count, 0);
    }
    expect(days.last.day, DateTime(2026, 9, 25));
    // 84 días, hoy incluido: el más viejo es 83 días atrás.
    expect(days.first.day, DateTime(2026, 7, 4));
  });

  test('un repaso hoy cuenta en el día de hoy, al final', () {
    final days = dailyActivity([today], today: today);

    expect(days.last.count, 1);
  });

  test('dos repasos el mismo día se suman', () {
    final days = dailyActivity([
      today,
      today.add(const Duration(hours: 2)),
    ], today: today);

    expect(days.last.count, 2);
  });

  test('un repaso fuera de la ventana no cuenta en ningún día', () {
    final days = dailyActivity([
      today.subtract(const Duration(days: 90)),
    ], today: today);

    expect(days.fold<int>(0, (sum, d) => sum + d.count), 0);
  });

  test('la hora del día no importa, solo la fecha', () {
    final days = dailyActivity([
      DateTime(2026, 9, 25, 23, 59),
    ], today: DateTime(2026, 9, 25, 0, 1));

    expect(days.last.count, 1);
  });

  test('orden cronológico: el día más viejo primero, hoy al final', () {
    final days = dailyActivity(const [], today: today);

    for (var i = 1; i < days.length; i++) {
      expect(days[i].day.isAfter(days[i - 1].day), isTrue);
    }
  });

  test('con days: 1, un solo día, el de hoy', () {
    final days = dailyActivity([today], today: today, days: 1);

    expect(days, hasLength(1));
    expect(days.single.count, 1);
  });
}
