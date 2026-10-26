import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';

/// Las huellas de lo que «no era» (F27): lo mismo tiene que dar la misma
/// huella mire desde donde se mire, y lo distinto, otra.
void main() {
  group('un vínculo', () {
    test('es el mismo par en cualquier sentido', () {
      final ida = relationRejectionKey(
        fromItemId: 'b',
        toItemId: 'a',
        kind: RelationKind.continues,
      );
      final vuelta = relationRejectionKey(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.continues,
      );

      expect(ida, vuelta);
      expect(ida.itemId, 'a');
      expect(ida.otherItemId, 'b');
      // La misma expresión que arma la fusión en SQL: MAX(…) || ':' || kind.
      expect(ida.fingerprint, 'b:continues');
    });

    test('otro tipo es otra cosa', () {
      expect(
        relationRejectionKey(
          fromItemId: 'a',
          toItemId: 'b',
          kind: RelationKind.cites,
        ).fingerprint,
        isNot(
          relationRejectionKey(
            fromItemId: 'a',
            toItemId: 'b',
            kind: RelationKind.relatedTo,
          ).fingerprint,
        ),
      );
    });
  });

  test('una propiedad no distingue mayúsculas ni acentos', () {
    expect(
      propertyRejectionFingerprint(definitionName: 'Tema', value: 'Álgebra'),
      propertyRejectionFingerprint(definitionName: 'tema', value: ' algebra '),
    );
    expect(
      propertyRejectionFingerprint(definitionName: 'Tema', value: 'Roma'),
      isNot(
        propertyRejectionFingerprint(definitionName: 'Región', value: 'Roma'),
      ),
    );
  });

  group('una tarjeta', () {
    test('es la misma pregunta sin signos, acentos ni punto final', () {
      expect(
        flashcardRejectionFingerprint('¿Qué es la entropía?'),
        flashcardRejectionFingerprint('que es la  entropia'),
      );
      expect(
        flashcardRejectionFingerprint('Definí la entropía.'),
        flashcardRejectionFingerprint('definí la entropía'),
      );
    });

    test('una palabra distinta es otra pregunta', () {
      expect(
        flashcardRejectionFingerprint('¿Qué es la entropía?'),
        isNot(flashcardRejectionFingerprint('¿Qué mide la entropía?')),
      );
    });
  });

  group('un hecho fechado (F40)', () {
    HistoricalDate year(int y, {bool circa = false}) =>
        HistoricalDate(year: y, precision: DatePrecision.year, isCirca: circa);

    test('es la misma con la cita escrita con otras mayúsculas, acentos o '
        'espacios', () {
      expect(
        datedEventRejectionFingerprint(
          date: year(1831),
          excerpt: 'En 1831  zarpó\n el Beagle',
        ),
        datedEventRejectionFingerprint(
          date: year(1831),
          excerpt: 'EN 1831 ZARPO EL BEAGLE',
        ),
      );
    });

    test('otra fecha o otra precisión es otra huella; el circa no', () {
      final base = datedEventRejectionFingerprint(
        date: year(1831),
        excerpt: 'zarpó',
      );

      expect(
        datedEventRejectionFingerprint(date: year(1832), excerpt: 'zarpó'),
        isNot(base),
      );
      expect(
        datedEventRejectionFingerprint(
          date: const HistoricalDate(
            year: 1831,
            precision: DatePrecision.month,
            month: 1,
          ),
          excerpt: 'zarpó',
        ),
        isNot(base),
      );
      expect(
        datedEventRejectionFingerprint(
          date: year(1831, circa: true),
          excerpt: 'zarpó',
        ),
        base,
      );
    });

    test('el mes y el día cuentan', () {
      HistoricalDate on(int month, int day) => HistoricalDate(
        year: 1831,
        precision: DatePrecision.day,
        month: month,
        day: day,
      );
      final base = datedEventRejectionFingerprint(
        date: on(3, 10),
        excerpt: 'zarpó',
      );

      expect(
        datedEventRejectionFingerprint(date: on(4, 10), excerpt: 'zarpó'),
        isNot(base),
      );
      expect(
        datedEventRejectionFingerprint(date: on(3, 11), excerpt: 'zarpó'),
        isNot(base),
      );
    });

    test('a.C. y d.C. son años distintos', () {
      expect(
        datedEventRejectionFingerprint(
          date: const HistoricalDate(
            year: 44,
            precision: DatePrecision.year,
            isBce: true,
          ),
          excerpt: 'x',
        ),
        isNot(datedEventRejectionFingerprint(date: year(44), excerpt: 'x')),
      );
    });

    test('otra cita es otra huella', () {
      expect(
        datedEventRejectionFingerprint(date: year(1831), excerpt: 'zarpó'),
        isNot(
          datedEventRejectionFingerprint(date: year(1831), excerpt: 'volvió'),
        ),
      );
    });
  });
}
