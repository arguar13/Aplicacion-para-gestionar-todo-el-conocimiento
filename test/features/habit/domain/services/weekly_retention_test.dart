import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/habit/domain/services/weekly_retention.dart';

/// `weeklyRetention` (F17, D8): pura. Hoy es siempre el 25 de septiembre de
/// 2026 (viernes) en estas pruebas.
void main() {
  final today = DateTime(2026, 9, 25, 14);

  test('sin repasos, las doce semanas aparecen igual, todas en cero', () {
    final weeks = weeklyRetention(const [], today: today);

    expect(weeks, hasLength(12));
    for (final week in weeks) {
      expect(week.total, 0);
      expect(week.retained, 0);
      expect(week.ratio, 0);
    }
    // La última fila es la semana de hoy: del 19 al 25.
    expect(weeks.last.weekStart, DateTime(2026, 9, 19));
    // La primera es la más vieja de las doce, 77 días atrás.
    expect(weeks.first.weekStart, DateTime(2026, 7, 4));
  });

  test('un repaso hoy, retenido, cuenta en la semana de hoy', () {
    final weeks = weeklyRetention([
      (reviewedAt: today, retained: true),
    ], today: today);

    expect(weeks.last.total, 1);
    expect(weeks.last.retained, 1);
    expect(weeks.last.ratio, 1);
  });

  test('un repaso "again" cuenta en el total pero no en lo retenido', () {
    final weeks = weeklyRetention([
      (reviewedAt: today, retained: false),
    ], today: today);

    expect(weeks.last.total, 1);
    expect(weeks.last.retained, 0);
    expect(weeks.last.ratio, 0);
  });

  test('un repaso de hace 8 días va a la semana anterior, no a la de hoy', () {
    final weeks = weeklyRetention([
      (reviewedAt: today.subtract(const Duration(days: 8)), retained: true),
    ], today: today);

    expect(weeks.last.total, 0);
    expect(weeks[weeks.length - 2].total, 1);
  });

  test('un repaso fuera de la ventana no aparece en ninguna semana', () {
    final weeks = weeklyRetention([
      (reviewedAt: today.subtract(const Duration(days: 90)), retained: true),
    ], today: today);

    expect(weeks.fold<int>(0, (sum, w) => sum + w.total), 0);
  });

  test('la hora del día no importa, solo la fecha', () {
    final weeks = weeklyRetention([
      (reviewedAt: DateTime(2026, 9, 25, 23, 59), retained: true),
    ], today: DateTime(2026, 9, 25, 0, 1));

    expect(weeks.last.total, 1);
  });

  test('con weeks: 1, una sola fila, la semana de hoy', () {
    final weeks = weeklyRetention(
      [(reviewedAt: today, retained: true)],
      today: today,
      weeks: 1,
    );

    expect(weeks, hasLength(1));
    expect(weeks.single.total, 1);
  });

  test('varios repasos en la misma semana se suman', () {
    final weeks = weeklyRetention([
      (reviewedAt: today, retained: true),
      (reviewedAt: today, retained: true),
      (reviewedAt: today.subtract(const Duration(days: 1)), retained: false),
    ], today: today);

    expect(weeks.last.total, 3);
    expect(weeks.last.retained, 2);
  });
}
