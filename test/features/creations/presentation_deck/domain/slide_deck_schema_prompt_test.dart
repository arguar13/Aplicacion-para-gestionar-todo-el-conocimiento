import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_icon_names.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_json.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_schema_prompt.dart';

import '../support/sample_decks.dart';

/// El esquema que se le explica a la IA (F43, decisión G) dice exactamente
/// lo que el lector entiende: los veinte diseños (los ocho de F45 también),
/// cada clave que se escribe y los íconos del juego.
void main() {
  test('nombra los veinte diseños por su nombre de JSON', () {
    for (final layout in SlideLayout.values) {
      expect(slideDeckJsonSchemaPrompt, contains('"${layout.jsonName}"'));
    }
  });

  test('nombra cada clave que escribe el mazo guardado', () {
    final keys = <String>{};
    void collect(Object? json) {
      if (json is Map) {
        for (final entry in json.entries) {
          keys.add(entry.key as String);
          collect(entry.value);
        }
      } else if (json is List) {
        json.forEach(collect);
      }
    }

    collect(SlideDeckJson.encode(sampleDeck(illustrations: true)));
    collect(SlideDeckJson.encode(longMoreDeck()));
    // La referencia de la ilustración la pone la app, no la IA.
    keys.remove('illustration_ref');
    for (final key in keys) {
      expect(slideDeckJsonSchemaPrompt, contains('"$key"'), reason: key);
    }
  });

  test('ofrece todos los íconos del juego, y solo esos', () {
    expect(slideDeckJsonSchemaPrompt, contains(creationIconNames.join(', ')));
  });

  test('pone los topes de cada lista', () {
    expect(slideDeckJsonSchemaPrompt, contains('${SlideLimits.slides}'));
    expect(
      slideDeckJsonSchemaPrompt,
      contains('${SlideLimits.bullets} textos'),
    );
    for (final limit in [
      SlideLimits.images,
      SlideLimits.nodes,
      SlideLimits.questions,
      SlideLimits.stats,
      SlideLimits.cycleSteps,
    ]) {
      expect(slideDeckJsonSchemaPrompt, contains('a $limit'));
    }
    expect(slideDeckJsonSchemaPrompt, contains('exactamente 4 objetos'));
  });

  test('pide no inventar y está en castellano', () {
    expect(slideDeckJsonSchemaPrompt, contains('no inventes'));
    expect(slideDeckJsonSchemaPrompt, contains('Devolvé SOLO un objeto JSON'));
  });

  test('el formato del presentador pide notas para decir', () {
    expect(
      slideDeckFormatPrompt(DeckFormat.presenter),
      contains('"speaker_notes"'),
    );
    expect(
      slideDeckFormatPrompt(DeckFormat.detailed),
      isNot(slideDeckFormatPrompt(DeckFormat.presenter)),
    );
  });
}
