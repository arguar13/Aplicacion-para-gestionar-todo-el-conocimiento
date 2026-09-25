import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/habit/domain/services/streak_calculator.dart';

/// La racha (F17, D6): pura, sin base ni bindings.
void main() {
  final today = DateTime(2026, 9, 25);

  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  group('sin actividad', () {
    test('ninguna racha, y hoy no tuvo nada', () {
      final streak = calculateStreak(const {}, today: today);

      expect(streak.days, 0);
      expect(streak.activeToday, isFalse);
    });
  });

  group('días consecutivos', () {
    test('solo hoy: 1 día, hoy cuenta', () {
      final streak = calculateStreak({today}, today: today);

      expect(streak.days, 1);
      expect(streak.activeToday, isTrue);
    });

    test('hoy y los tres días anteriores: 4 días seguidos', () {
      final streak = calculateStreak({
        today,
        daysAgo(1),
        daysAgo(2),
        daysAgo(3),
      }, today: today);

      expect(streak.days, 4);
      expect(streak.activeToday, isTrue);
    });

    test('solo ayer, hoy todavía no: cuenta desde ayer, sin cortar', () {
      final streak = calculateStreak({daysAgo(1), daysAgo(2)}, today: today);

      expect(streak.days, 2);
      expect(streak.activeToday, isFalse);
    });

    test('hoy no, y ayer tampoco, pero con gracia la racha sigue viva', () {
      // Justo para esto existe la gracia: el hueco de ayer se perdona
      // igual que cualquier otro hueco en medio de la racha.
      final streak = calculateStreak({daysAgo(2), daysAgo(3)}, today: today);

      expect(streak.days, 2);
      expect(streak.activeToday, isFalse);
    });

    test('sin gracia disponible, un hueco ayer sí corta la racha', () {
      final streak = calculateStreak(
        {daysAgo(2), daysAgo(3)},
        today: today,
        graceDaysPerWeek: 0,
      );

      expect(streak.days, 0);
      expect(streak.activeToday, isFalse);
    });
  });

  group('gracia (D6, hasta 2 por semana por defecto)', () {
    test('un hueco de un día en medio no corta la racha', () {
      // Activo hoy, ayer no (hueco), antes de ayer y el resto sí.
      final streak = calculateStreak({
        today,
        daysAgo(2),
        daysAgo(3),
        daysAgo(4),
      }, today: today);

      // 4 días activos + el hueco de gracia cuentan para la LONGITUD de la
      // racha —el hueco no rompe la cadena, pero tampoco es un día que
      // "sumó" actividad—: la racha sigue siendo la cadena completa.
      expect(streak.days, 4);
    });

    test('dos huecos sueltos, dentro del cupo, no cortan nada', () {
      final streak = calculateStreak({
        today,
        daysAgo(2),
        daysAgo(4),
        daysAgo(5),
      }, today: today);

      expect(streak.days, 4);
    });

    test('un tercer hueco en la misma semana corta ahí la racha', () {
      final streak = calculateStreak({
        today,
        daysAgo(2),
        daysAgo(4),
        // Tiene actividad, pero la racha corta ANTES de llegar acá: no
        // "salta" un hueco sin gracia para ir a buscar días más viejos.
        daysAgo(7),
      }, today: today);

      // hoy (día 0, activo) → gracia en el día 1 (cupo 1/2) →
      // daysAgo(2) (activo) → gracia en el día 3 (cupo 2/2) →
      // daysAgo(4) (activo) → el día 5 ya no tiene gracia —los huecos de
      // los días 1 y 3 siguen dentro de la ventana de 7 días que termina
      // en el día 5—: corta ahí. Racha = días 0, 2 y 4 activos.
      expect(streak.days, 3);
    });

    test('con 1 día de gracia por semana, un solo hueco ya alcanza el '
        'límite', () {
      final streak = calculateStreak(
        {today, daysAgo(2)},
        today: today,
        graceDaysPerWeek: 1,
      );

      // hoy (1) + gracia en 1 (con cupo de 1) + daysAgo(2) (2): el
      // siguiente hueco ya no tiene gracia.
      expect(streak.days, 2);
    });

    test('con 0 días de gracia, cualquier hueco corta al toque', () {
      final streak = calculateStreak(
        {today, daysAgo(2)},
        today: today,
        graceDaysPerWeek: 0,
      );

      expect(streak.days, 1);
    });

    test('un hueco viejo —hace más de una semana— no gasta el cupo de hoy', () {
      // Actividad reciente sin huecos, y un hueco solitario de hace
      // mucho que no debería sumarse al cupo de la ventana actual.
      final streak = calculateStreak({
        today,
        daysAgo(1),
        daysAgo(2),
        daysAgo(3),
        daysAgo(4),
        daysAgo(5),
        daysAgo(6),
        // daysAgo(7) falta —primer hueco de la ventana reciente—.
        daysAgo(8),
        daysAgo(9),
      }, today: today);

      // 7 días activos seguidos + un hueco con gracia + 2 más: la
      // ventana de gracia se calcula sobre el hueco real, no sobre
      // nada más viejo que no existe todavía en el recorrido.
      expect(streak.days, 9);
    });
  });

  group('normaliza la hora: solo importa el día', () {
    test('una marca de horas distintas el mismo día es un solo día', () {
      final streak = calculateStreak({
        DateTime(2026, 9, 25, 23, 59),
        DateTime(2026, 9, 24, 0, 1),
      }, today: DateTime(2026, 9, 25, 8));

      expect(streak.days, 2);
      expect(streak.activeToday, isTrue);
    });
  });
}
