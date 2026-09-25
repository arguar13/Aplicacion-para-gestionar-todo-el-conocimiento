import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/habit/domain/services/month_of_weekly_consolidation.dart';

/// La insignia «un mes de consolidación semanal» (F17, D7): pura.
void main() {
  test('el día 1 del mes, sin ninguna actividad, no alcanza', () {
    final result = hasMonthOfWeeklyConsolidation(
      const {},
      today: DateTime(2026, 9),
    );

    expect(result, isFalse);
  });

  test('el día 1 del mes, con actividad ese mismo día, ya alcanza', () {
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9),
    }, today: DateTime(2026, 9));

    expect(result, isTrue);
  });

  test('con una actividad en cada semana ya empezada, alcanza', () {
    // Semana 1: días 1-7. Semana 2: días 8-14 (hoy es el 10, así que solo
    // hasta ahí).
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9, 3),
      DateTime(2026, 9, 9),
    }, today: DateTime(2026, 9, 10));

    expect(result, isTrue);
  });

  test('la semana 1 con actividad, pero la 2 sin nada hasta hoy: no '
      'alcanza', () {
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9, 3),
    }, today: DateTime(2026, 9, 10));

    expect(result, isFalse);
  });

  test('tres semanas, la del medio sin actividad: no alcanza', () {
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9, 2), // semana 1 (1-7)
      // semana 2 (8-14): nada
      DateTime(2026, 9, 18), // semana 3 (15-20, hasta hoy)
    }, today: DateTime(2026, 9, 20));

    expect(result, isFalse);
  });

  test('una semana a medio empezar solo exige actividad en lo que ya '
      'pasó de ella', () {
    // Hoy es el día 8: la semana 2 recién empieza, alcanza con el propio
    // día 8.
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9, 3), // semana 1
      DateTime(2026, 9, 8), // semana 2, hasta hoy
    }, today: DateTime(2026, 9, 8));

    expect(result, isTrue);
  });

  test('una semana que todavía no llegó no cuenta en contra', () {
    // Hoy es el día 5: la semana 2 (8-14) ni empezó, no se le exige nada.
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9, 2),
    }, today: DateTime(2026, 9, 5));

    expect(result, isTrue);
  });

  test('actividad de otro mes no cuenta', () {
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 8, 3), // mes anterior
    }, today: DateTime(2026, 9, 3));

    expect(result, isFalse);
  });

  test('la hora del día no importa, solo la fecha', () {
    final result = hasMonthOfWeeklyConsolidation({
      DateTime(2026, 9, 1, 23, 59),
    }, today: DateTime(2026, 9, 1, 0, 1));

    expect(result, isTrue);
  });
}
