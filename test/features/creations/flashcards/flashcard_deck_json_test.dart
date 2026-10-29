import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_json.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_item_json.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_items.dart';

import 'support/study_fakes.dart';

void main() {
  group('FlashcardDeckJson lee con tolerancia', () {
    test('las claves en castellano, en inglés, en camelCase o con tildes', () {
      final deck = FlashcardDeckJson.tryDecode({
        'Título': 'Mazo',
        'flashcards': [
          {'Pregunta': '¿Uno?', 'Respuesta': 'Sí.'},
          {'front': '¿Dos?', 'back': 'No.', 'Hint': 'Pista'},
          {'term': 'Tres', 'definition': 'El número.'},
          {'frente': '¿Cuatro?', 'dorso': 'Cuatro.', 'illustrationPrompt': 'a'},
        ],
      })!;

      expect(deck.title, 'Mazo');
      expect(deck.cards.map((c) => c.front), [
        '¿Uno?',
        '¿Dos?',
        'Tres',
        '¿Cuatro?',
      ]);
      expect(deck.cards[1].hint, 'Pista');
      expect(deck.cards[3].illustrationPrompt, 'a');
      expect(deck.cards.map((c) => c.id), ['c1', 'c2', 'c3', 'c4']);
    });

    test('una lista suelta, una tarjeta como par, y lo envuelto en un bloque '
        'de código', () {
      final fromList = FlashcardDeckJson.tryDecode([
        ['¿Uno?', 'Sí.'],
        {'frente': '¿Dos?', 'dorso': 'No.'},
      ])!;
      expect(fromList.cards, hasLength(2));

      final wrapped = FlashcardDeckJson.parse(
        extractJsonValue('¡Claro!\n```json\n${deckReply(2)}\n```'),
      );
      expect(wrapped.cards, hasLength(2));
    });

    test('sin pregunta o sin respuesta no cuenta, ni la misma pregunta dos '
        'veces (sin mayúsculas ni tildes)', () {
      final deck = FlashcardDeckJson.tryDecode({
        'cards': [
          {'front': '¿Qué es?', 'back': ''},
          {'front': '', 'back': 'Algo.'},
          {'front': '¿Qué es Éxodo?', 'back': 'Un libro.'},
          {'front': 'que es exodo', 'back': 'Repetida.'},
          'suelta',
          42,
        ],
      })!;
      expect(deck.cards.single.back, 'Un libro.');
    });

    test(
      'nada que leer da null, y parse lo dice para que la IA lo corrija',
      () {
        expect(FlashcardDeckJson.tryDecode({'cards': <Object?>[]}), isNull);
        expect(FlashcardDeckJson.tryDecode('no es json'), isNull);
        expect(FlashcardDeckJson.tryDecode(7), isNull);
        expect(
          () => FlashcardDeckJson.parse({'titulo': 'x'}),
          throwsA(isA<FormatException>()),
        );
        expect(FlashcardDeckJson.decode(null).isEmpty, isTrue);
      },
    );

    test(
      'los textos se recortan en una palabra entera y sin espacios de más',
      () {
        final long = List.filled(200, 'palabra').join(' ');
        final deck = FlashcardDeckJson.tryDecode({
          'cards': [
            {'front': '  ¿Mucho   espacio?  ', 'back': long},
          ],
        })!;
        expect(deck.cards.single.front, '¿Mucho espacio?');
        expect(
          deck.cards.single.back.length,
          lessThanOrEqualTo(DeckLimits.back + 1),
        );
        expect(deck.cards.single.back, endsWith('palabra…'));
      },
    );

    test('un id repetido se renumera: une una sola tarjeta con su repaso', () {
      final deck = FlashcardDeckJson.tryDecode({
        'cards': [
          {'id': 'c1', 'front': '¿A?', 'back': 'a'},
          {'id': 'c1', 'front': '¿B?', 'back': 'b'},
        ],
      })!;
      expect(deck.cards.map((c) => c.id).toSet(), hasLength(2));
    });
  });

  test('ida y vuelta: lo guardado se lee igual, con la ruta de su '
      'ilustración, el repaso y '
      'por qué no hubo ilustraciones', () {
    const deck = FlashcardDeck(
      title: 'Mazo',
      inReview: true,
      illustrationFailure: ImageFailure.quotaExhausted,
      illustrationAccount: 'Personal',
      cards: [
        DeckCard(
          id: 'c1',
          front: '¿A?',
          back: 'a',
          hint: 'h',
          documentId: 'doc',
          icon: 'book',
          illustrationPrompt: 'p',
          illustrationRef: 'originales/x/ilustraciones/c1.jpg',
          flashcardId: 'f1',
        ),
        DeckCard(id: 'c2', front: '¿B?', back: 'b'),
      ],
    );

    final again = FlashcardDeckJson.decode(
      jsonDecode(FlashcardDeckJson.encodeString(deck)),
    );

    expect(again, deck);
    expect(again.hashCode, deck.hashCode);
  });

  group('studyJson', () {
    test('las claves se comparan sin caja, tildes ni guiones', () {
      expect(studyJsonKey('correct_answer'), studyJsonKey('CorrectAnswer'));
      expect(studyJsonKey('Explicación'), 'explicacion');
    });

    test('un sí o no escrito de muchas maneras', () {
      for (final yes in [true, 1, 'sí', 'True', 'correcta']) {
        expect(
          studyJsonBool({'ok': yes}, const ['ok']),
          isTrue,
          reason: '$yes',
        );
      }
      for (final no in [false, 0, 'no', 'falso', 'incorrecta']) {
        expect(studyJsonBool({'ok': no}, const ['ok']), isFalse, reason: '$no');
      }
      expect(studyJsonBool({'ok': 'quizás'}, const ['ok']), isNull);
    });

    test('un mazo de antes, con la imagen adentro, se lee igual: sin '
        'ilustración y con el dibujo de la app', () {
      final deck = FlashcardDeckJson.tryDecode({
        'cards': [
          {
            'front': '¿A?',
            'back': 'a',
            'image': {'mime': 'image/jpeg', 'data': '%%%'},
          },
        ],
      })!;
      expect(deck.cards.single.illustrationRef, isNull);
      expect(deck.cards.single.front, '¿A?');
    });
  });

  group('spreadStudyItems', () {
    DeckCard card(String front) => DeckCard(id: front, front: front, back: '.');

    test('de a una de cada parte, en vueltas, hasta el total, sin repetir y '
        'en el orden del material', () {
      final spread = spreadStudyItems([
        [card('a1'), card('a2'), card('a3'), card('igual')],
        [card('igual'), card('b1')],
        [card('c1'), card('c2'), card('c3')],
      ], 6);

      expect(spread.map((c) => c.front), ['a1', 'a2', 'a3', 'b1', 'c1', 'c2']);
    });

    test('si no alcanzan, todas', () {
      expect(
        spreadStudyItems([
          [card('a')],
          [card('b')],
        ], 10),
        hasLength(2),
      );
    });
  });

  test('cuántas entran en una ventana: nunca menos de tres', () {
    expect(studyItemsThatFit(2048, 90), 9);
    expect(studyItemsThatFit(1000000, 90), greaterThan(30));
    expect(studyItemsThatFit(100, 90), 3);
  });
}
