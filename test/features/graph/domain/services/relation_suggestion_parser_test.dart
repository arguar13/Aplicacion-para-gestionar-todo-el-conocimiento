import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_parser.dart';

void main() {
  test('interpreta una línea bien formada', () {
    final result = parseRelationSuggestions(
      'SUGERENCIA: 2 | relacionado | Hablan del mismo tema',
    );

    expect(result, [
      (
        candidateIndex: 1,
        kind: RelationKind.relatedTo,
        reason: 'Hablan del mismo tema',
        certainty: null,
      ),
    ]);
  });

  test(
    'lee la certeza que dice el modelo, entre la clave y el motivo (F27)',
    () {
      final result = parseRelationSuggestions('''
SUGERENCIA: 1 | relacionado | alta | Los dos hablan del Senado
SUGERENCIA: 2 | cita | Media | Lo menciona de pasada
SUGERENCIA: 3 | resume | baja | Puede ser un resumen
''');

      expect(result.map((r) => r.certainty), [
        AiCertainty.high,
        AiCertainty.medium,
        AiCertainty.low,
      ]);
      expect(result.map((r) => r.reason), [
        'Los dos hablan del Senado',
        'Lo menciona de pasada',
        'Puede ser un resumen',
      ]);
    },
  );

  test('una barra dentro del motivo no se toma por certeza', () {
    final result = parseRelationSuggestions(
      'SUGERENCIA: 1 | relacionado | Roma | el Senado y sus leyes',
    );

    expect(result.single.certainty, isNull);
    expect(result.single.reason, 'Roma | el Senado y sus leyes');
  });

  test('interpreta varias líneas, cada una con su tipo', () {
    final result = parseRelationSuggestions('''
SUGERENCIA: 1 | continua | Es la segunda parte
SUGERENCIA: 3 | contradice | Dice lo contrario
SUGERENCIA: 5 | cita | Menciona la fuente
SUGERENCIA: 7 | resume | Es un resumen del original
''');

    expect(result.map((r) => r.candidateIndex), [0, 2, 4, 6]);
    expect(result.map((r) => r.kind), [
      RelationKind.continues,
      RelationKind.contradicts,
      RelationKind.cites,
      RelationKind.summarizes,
    ]);
  });

  test('no distingue mayúsculas ni en la clave ni en la etiqueta', () {
    final result = parseRelationSuggestions(
      'sugerencia: 1 | RELACIONADO | Motivo',
    );

    expect(result, hasLength(1));
    expect(result.single.kind, RelationKind.relatedTo);
  });

  test('ignora líneas que no matchean el formato, sin fallar', () {
    final result = parseRelationSuggestions('''
Acá va una explicación libre que el modelo agregó de más.
SUGERENCIA: 1 | relacionado | Motivo válido
Otra línea suelta.
''');

    expect(result, hasLength(1));
  });

  test('ignora una clave que no es ninguna de las esperadas', () {
    final result = parseRelationSuggestions(
      'SUGERENCIA: 1 | inventada | Motivo',
    );

    expect(result, isEmpty);
  });

  test('sin ninguna línea SUGERENCIA, devuelve una lista vacía', () {
    final result = parseRelationSuggestions('No encontré nada relacionado.');

    expect(result, isEmpty);
  });

  test('una respuesta vacía no revienta', () {
    expect(parseRelationSuggestions(''), isEmpty);
  });
}
