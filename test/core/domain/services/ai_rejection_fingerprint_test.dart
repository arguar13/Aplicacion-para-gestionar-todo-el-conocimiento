import 'package:flutter_test/flutter_test.dart';
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
}
