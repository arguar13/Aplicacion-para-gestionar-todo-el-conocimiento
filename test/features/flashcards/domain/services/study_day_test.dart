import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';

/// El día de estudio (F31, decisión 69): de las 4:00 a las 4:00, en hora local.
void main() {
  const day = StudyDay();

  group('startOf', () {
    test('de día, el día empezó a las 4:00 de hoy', () {
      expect(
        day.startOf(DateTime(2026, 10, 8, 15, 30)),
        DateTime(2026, 10, 8, 4),
      );
    });

    test('de madrugada, antes de las 4:00, sigue siendo el día de ayer', () {
      expect(
        day.startOf(DateTime(2026, 10, 8, 0, 30)),
        DateTime(2026, 10, 7, 4),
      );
      expect(
        day.startOf(DateTime(2026, 10, 8, 3, 59, 59)),
        DateTime(2026, 10, 7, 4),
      );
    });

    test('a las 4:00 en punto ya es el día nuevo', () {
      expect(day.startOf(DateTime(2026, 10, 8, 4)), DateTime(2026, 10, 8, 4));
    });

    test('a medianoche NO cambia el día', () {
      final beforeMidnight = DateTime(2026, 10, 7, 23, 59);
      final afterMidnight = DateTime(2026, 10, 8, 0, 1);

      expect(day.isSameDay(beforeMidnight, afterMidnight), isTrue);
    });

    test('cruza el fin de mes y el de año', () {
      expect(day.startOf(DateTime(2026, 11, 1, 2)), DateTime(2026, 10, 31, 4));
      expect(day.startOf(DateTime(2027, 1, 1, 3)), DateTime(2026, 12, 31, 4));
      expect(
        day.startOf(DateTime(2028, 3, 1, 1)),
        DateTime(2028, 2, 29, 4),
        reason: '2028 es bisiesto',
      );
    });
  });

  group('endOf', () {
    test('es el comienzo del día siguiente', () {
      expect(day.endOf(DateTime(2026, 10, 8, 15)), DateTime(2026, 10, 9, 4));
      expect(day.endOf(DateTime(2026, 10, 8, 1)), DateTime(2026, 10, 8, 4));
    });

    test('un instante que es justo el fin pertenece al día nuevo', () {
      final end = day.endOf(DateTime(2026, 10, 8, 15));

      expect(day.startOf(end), end);
      expect(day.endOf(end), DateTime(2026, 10, 10, 4));
    });

    test('un día entero va de startOf a endOf sin huecos ni solapes', () {
      var cursor = DateTime(2026, 12, 28, 10);
      for (var i = 0; i < 400; i++) {
        final end = day.endOf(cursor);
        expect(end.isAfter(cursor), isTrue);
        // El día siguiente empieza exactamente donde terminó este.
        expect(day.startOf(end), end);
        // Y un instante antes del fin todavía es este día.
        expect(
          day.startOf(end.subtract(const Duration(seconds: 1))),
          day.startOf(cursor),
        );
        cursor = end;
      }
    });

    test('mide un día de calendario, 24 horas salvo cambio de horario', () {
      final start = DateTime(2026, 10, 8, 4);
      final length = day.endOf(start).difference(start);

      // En una zona con horario de verano, el día del cambio mide 23 o 25
      // horas; en el resto, 24.
      expect(
        length,
        anyOf(
          const Duration(hours: 24),
          const Duration(hours: 23),
          const Duration(hours: 25),
        ),
      );
    });
  });

  group('la zona horaria', () {
    test('un instante en UTC se decide en hora local', () {
      final utc = DateTime.utc(2026, 10, 8, 12);

      expect(day.startOf(utc), day.startOf(utc.toLocal()));
      expect(day.endOf(utc), day.endOf(utc.toLocal()));
      // El resultado es hora local, no UTC.
      expect(day.startOf(utc).isUtc, isFalse);
    });

    test('el mismo instante da el mismo día sea cual sea la forma en que se '
        'lo dice', () {
      final local = DateTime(2026, 10, 8, 2, 15);
      final sameInstantUtc = local.toUtc();

      expect(day.startOf(sameInstantUtc), day.startOf(local));
    });
  });

  group('la hora de corte', () {
    test('se puede cambiar', () {
      const midnight = StudyDay(startHour: 0);

      expect(
        midnight.startOf(DateTime(2026, 10, 8, 0, 30)),
        DateTime(2026, 10, 8),
      );
      expect(
        midnight.endOf(DateTime(2026, 10, 8, 0, 30)),
        DateTime(2026, 10, 9),
      );
    });

    test('por defecto son las 4:00', () {
      expect(kStudyDayStartHour, 4);
      expect(const StudyDay().startHour, 4);
    });
  });
}
