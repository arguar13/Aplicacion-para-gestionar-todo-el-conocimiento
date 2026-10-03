import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/services/vocabulary_budget.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// El vocabulario que va al modelo, acotado (F27): lo más pertinente, de
/// cada categoría, dentro de lo que entra en la ventana.
void main() {
  String described(List<PropertyVocabularyCategory> categories) =>
      categories.map(describeVocabularyCategory).join('\n');

  List<String> valuesOf(
    List<PropertyVocabularyCategory> categories,
    String name,
  ) => categories.singleWhere((c) => c.name == name).values;

  VocabularyCategoryCandidates category(
    String name,
    List<VocabularyValueCandidate> values,
  ) => VocabularyCategoryCandidates(
    definitionId: 'def-$name',
    name: name,
    values: values,
  );

  /// [count] valores sin nada que ver con nada.
  List<VocabularyValueCandidate> filler(String prefix, int count) => [
    for (var i = 0; i < count; i++)
      VocabularyValueCandidate(
        label: '$prefix ${'$i'.padLeft(4, '0')}',
        similarity: 0.1,
      ),
  ];

  test('miles de valores en varias categorías: nunca pasa del tope, y cada '
      'categoría lleva sus primeros', () {
    final categories = [
      for (final name in ['Tema', 'Época', 'Región', 'Personaje', 'Lugar'])
        category(name, filler(name, 2000)),
    ];

    final chosen = selectVocabularyForPrompt(categories, mentionedIn: 'Nada.');

    expect(
      described(chosen).length,
      lessThanOrEqualTo(kPropertyVocabularyBudgetChars),
    );
    // Lleno casi hasta el tope: no se desperdicia la ventana.
    expect(
      described(chosen).length,
      greaterThan(kPropertyVocabularyBudgetChars - 20),
    );
    for (final c in chosen) {
      expect(c.values.length, greaterThanOrEqualTo(kMinValuesPerCategory));
    }
  });

  test('lo que el elemento nombra va primero, aunque no se use; después, lo '
      'más parecido; el uso desempata', () {
    final chosen = selectVocabularyForPrompt([
      category('Tema', [
        ...filler('Tema', 3000),
        const VocabularyValueCandidate(label: 'Cocina', similarity: 0),
        const VocabularyValueCandidate(label: 'Senado', similarity: 0.2),
        const VocabularyValueCandidate(label: 'República', similarity: 0.9),
        const VocabularyValueCandidate(
          label: 'Política',
          similarity: 0.5,
          uses: 1,
        ),
        const VocabularyValueCandidate(
          label: 'Gobierno',
          similarity: 0.5,
          uses: 100,
        ),
      ]),
    ], mentionedIn: 'Las sesiones del senado, en el año 100.');

    expect(valuesOf(chosen, 'Tema').take(4), [
      'Senado',
      'República',
      'Gobierno',
      'Política',
    ]);
    // Lo que no tiene nada que ver va al final: solo entra si sobra lugar
    // donde un valor más pertinente, y más largo, ya no entraba.
    final values = valuesOf(chosen, 'Tema');
    expect(values.indexOf('Cocina'), anyOf(-1, values.length - 1));
  });

  test('un alias nombrado también cuenta, y los alias de lo que entra '
      'acompañan', () {
    final chosen = selectVocabularyForPrompt([
      category('Lugar', [
        ...filler('Lugar', 3000),
        const VocabularyValueCandidate(
          label: 'Roma',
          aliases: ['Urbe', 'Ciudad eterna'],
        ),
      ]),
    ], mentionedIn: 'Lo que pasaba en la Urbe.');

    final lugar = chosen.single;
    expect(lugar.values.first, 'Roma');
    expect(lugar.aliases, ['Urbe', 'Ciudad eterna']);
    expect(
      described(chosen).length,
      lessThanOrEqualTo(kPropertyVocabularyBudgetChars),
    );
  });

  test('una categoría sin valores va igual, y una enorme no deja a las '
      'demás sin nada', () {
    final chosen = selectVocabularyForPrompt([
      category('Tema', [
        for (var i = 0; i < 5000; i++)
          VocabularyValueCandidate(label: 'Tema $i', similarity: 0.9),
      ]),
      category('Época', const [
        VocabularyValueCandidate(label: 'Antigua', similarity: 0.1),
        VocabularyValueCandidate(label: 'Moderna', similarity: 0.1),
      ]),
      category('Estado de ánimo', const []),
    ], mentionedIn: 'Nada.');

    expect(valuesOf(chosen, 'Época'), unorderedEquals(['Antigua', 'Moderna']));
    expect(valuesOf(chosen, 'Estado de ánimo'), isEmpty);
    expect(
      described(chosen).length,
      lessThanOrEqualTo(kPropertyVocabularyBudgetChars),
    );
  });

  test('con un tope chico entran las categorías más pertinentes, enteras '
      'hasta donde se pueda', () {
    final chosen = selectVocabularyForPrompt(
      [
        category('Cocina', const [VocabularyValueCandidate(label: 'Pan')]),
        category('Historia', const [
          VocabularyValueCandidate(label: 'Roma', similarity: 0.9),
        ]),
      ],
      mentionedIn: 'Nada.',
      budgetChars: 'Historia: Roma'.length,
    );

    expect(described(chosen), 'Historia: Roma');
  });

  test('el mismo vocabulario da siempre el mismo pedido', () {
    final categories = [category('Tema', filler('Tema', 3000))];

    final first = selectVocabularyForPrompt(categories, mentionedIn: 'x');
    final again = selectVocabularyForPrompt([
      category('Tema', filler('Tema', 3000).reversed.toList()),
    ], mentionedIn: 'x');

    expect(described(again), described(first));
  });
}
