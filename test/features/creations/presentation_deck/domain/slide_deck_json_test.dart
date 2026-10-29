import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_json.dart';

import '../support/sample_decks.dart';

/// El JSON de un mazo (F43, decisión G): lo que se guarda vuelve igual, y lo
/// que devuelve la IA se lee con tolerancia —nunca se pierde una diapositiva
/// por un campo raro, y nunca entra un texto sin tope—.
void main() {
  Slide only(Object? json) => SlideDeckJson.tryDecode({
    'title': 'Mazo',
    'slides': [json],
  })!.slides.single;

  group('ida y vuelta', () {
    test('el mazo de ejemplo vuelve idéntico, con sus doce diseños', () {
      final deck = sampleDeck(illustrations: true);
      final again = SlideDeckJson.decode(SlideDeckJson.encodeString(deck));

      expect(again, deck);
      expect(
        again.slides.map((s) => s.layout).toSet(),
        SlideLayout.values.toSet(),
      );
    });

    test('las notas, la ilustración pedida y la ya hecha también vuelven', () {
      const deck = SlideDeck(
        title: 'T',
        format: DeckFormat.presenter,
        slides: [
          Slide.bullets(
            title: 'Uno',
            bullets: ['a', 'b'],
            speakerNotes: 'Primero esto.\nDespués aquello.',
            illustrationPrompt: 'Un río',
            illustrationRef: 'creaciones/abc/3.png',
          ),
        ],
      );
      expect(SlideDeckJson.decode(SlideDeckJson.encode(deck)), deck);
    });

    test('lo vacío no se escribe', () {
      final json = SlideDeckJson.encodeSlide(const Slide.cover(title: 'Solo'));
      expect(json, {'layout': 'cover', 'title': 'Solo'});
    });
  });

  group('lo que devuelve la IA', () {
    test('envuelto en ```json y con texto alrededor', () {
      const text =
          'Acá está tu presentación:\n```json\n'
          '{"title": "Éxodo", "slides": '
          '[{"layout": "cover", "title": "Éxodo"}]}'
          '\n```\n¡Espero que sirva!';
      final deck = SlideDeckJson.tryDecode(text)!;
      expect(deck.title, 'Éxodo');
      expect(deck.slides.single, const Slide.cover(title: 'Éxodo'));
    });

    test('una lista suelta de diapositivas es un mazo', () {
      final deck = SlideDeckJson.tryDecode([
        {'layout': 'section', 'title': 'Parte'},
      ])!;
      expect(deck.slides.single, const Slide.section(title: 'Parte'));
      // Sin título, el mazo toma el de su primera diapositiva.
      expect(deck.title, 'Parte');
    });

    test('las claves en camelCase, snake_case o castellano', () {
      final slide = only({
        'Tipo': 'Viñetas',
        'Título': 'Claves',
        'viñetas': ['uno', 'dos'],
        'speakerNotes': 'decir algo',
        'illustration_prompt': 'un dibujo',
      });
      expect(
        slide,
        const Slide.bullets(
          title: 'Claves',
          bullets: ['uno', 'dos'],
          speakerNotes: 'decir algo',
          illustrationPrompt: 'un dibujo',
        ),
      );
    });

    test('los diseños por su nombre en castellano', () {
      expect(
        only({
          'layout': 'cronología',
          'title': 'T',
          'hitos': [
            {'fecha': 1492, 'titulo': 'Llegada'},
            {'fecha': '1810', 'titulo': 'Revolución'},
          ],
        }),
        const Slide.timeline(
          title: 'T',
          events: [
            TimelineEvent(date: '1492', title: 'Llegada'),
            TimelineEvent(date: '1810', title: 'Revolución'),
          ],
        ),
      );
      expect(
        only({'layout': 'cifra destacada', 'valor': 40, 'etiqueta': 'años'}),
        const Slide.bigNumber(value: '40', label: 'años'),
      );
    });

    test('un diseño desconocido se lee como viñetas, con todo su texto', () {
      final slide = only({
        'layout': 'carrusel-3d',
        'title': 'Lo raro',
        'items': ['a', 'b'],
      });
      expect(slide, const Slide.bullets(title: 'Lo raro', bullets: ['a', 'b']));
    });

    test('un diseño al que le falta lo suyo no se pierde: pasa a viñetas', () {
      // Una cronología sin hitos, con lo que trajo en otros campos.
      final timeline = only({
        'layout': 'timeline',
        'title': 'Sin hitos',
        'events': [
          {'date': '1', 'title': 'uno'},
        ],
      });
      expect(
        timeline,
        const Slide.bullets(title: 'Sin hitos', bullets: ['1 — uno']),
      );

      // Una cifra sin cifra.
      final number = only({
        'layout': 'big_number',
        'title': 'T',
        'label': 'algo',
      });
      expect(number, const Slide.bullets(title: 'T', bullets: ['algo']));

      // Pasos sueltos como textos sí sirven.
      final steps = only({
        'layout': 'steps',
        'title': 'P',
        'steps': ['uno', 'dos'],
      });
      expect(
        steps,
        const Slide.steps(
          title: 'P',
          steps: [
            SlideStep(title: 'uno'),
            SlideStep(title: 'dos'),
          ],
        ),
      );
    });

    test('una lista escrita como un texto con renglones y sus marcas', () {
      final slide = only({
        'layout': 'bullets',
        'title': 'T',
        'bullets': '- primero\n• segundo\n3. tercero\n\n',
      });
      expect((slide as BulletsSlide).bullets, [
        'primero',
        'segundo',
        'tercero',
      ]);
    });

    test('lo que falta toma su valor de fábrica', () {
      final slide = only({
        'layout': 'two_columns',
        'left': ['a'],
        'right': ['b'],
      });
      expect(
        slide,
        const Slide.twoColumns(
          title: '',
          left: SlideColumn(points: ['a']),
          right: SlideColumn(points: ['b']),
        ),
      );
      final deck = SlideDeckJson.tryDecode({
        'slides': [
          {'layout': 'cover', 'title': 'x'},
        ],
      })!;
      expect(deck.format, DeckFormat.detailed);
      expect(deck.subtitle, '');
    });

    test('el formato se entiende en los dos idiomas', () {
      SlideDeck withFormat(String format) => SlideDeckJson.tryDecode({
        'format': format,
        'slides': [
          {'layout': 'cover', 'title': 'x'},
        ],
      })!;
      expect(withFormat('presenter').format, DeckFormat.presenter);
      expect(withFormat('Del presentador').format, DeckFormat.presenter);
      expect(withFormat('detallada').format, DeckFormat.detailed);
      expect(withFormat('cualquier cosa').format, DeckFormat.detailed);
    });

    test('las comillas de la IA alrededor de una cita se sacan', () {
      final slide = only({'layout': 'quote', 'quote': '“Deja ir a mi pueblo”'});
      expect((slide as QuoteSlide).quote, 'Deja ir a mi pueblo');
    });

    test('los espacios repetidos y los bordes se limpian', () {
      final slide = only({
        'layout': 'cover',
        'title': '  Mucho   aire \n aquí  ',
      });
      expect(slide.headline, 'Mucho aire aquí');
    });

    test('el ícono se guarda tal cual, y el de reserva lo pone el dibujo', () {
      final slide = only({
        'layout': 'concept_grid',
        'title': 'C',
        'concepts': [
          {'title': 'a', 'icon': 'balance'},
          {'title': 'b'},
        ],
      });
      expect((slide as ConceptGridSlide).concepts.map((c) => c.icon), [
        'balance',
        null,
      ]);
    });
  });

  group('topes', () {
    test('un texto largo se corta en una palabra entera, con «…»', () {
      final title = List.filled(60, 'palabra').join(' ');
      final slide = only({'layout': 'cover', 'title': title});
      expect(slide.headline.length, lessThanOrEqualTo(SlideLimits.title));
      expect(slide.headline, endsWith('…'));
      expect(slide.headline, isNot(contains('palab…')));
    });

    test('clamp no toca lo que entra', () {
      expect(SlideDeckJson.clamp('corto', 10), 'corto');
      expect(SlideDeckJson.clamp('uno dos tres', 12), 'uno dos tres');
      expect(SlideDeckJson.clamp('uno dos tres', 11), 'uno dos…');
    });

    test('las listas no pasan de su tope', () {
      final slide = only({
        'layout': 'bullets',
        'title': 'T',
        'bullets': List.generate(20, (i) => 'v$i'),
      });
      expect((slide as BulletsSlide).bullets, hasLength(SlideLimits.bullets));

      final grid = only({
        'layout': 'concept_grid',
        'title': 'T',
        'concepts': List.generate(20, (i) => {'title': 'c$i'}),
      });
      expect(
        (grid as ConceptGridSlide).concepts,
        hasLength(SlideLimits.concepts),
      );
    });

    test('un mazo no pasa de su tope de diapositivas', () {
      final deck = SlideDeckJson.tryDecode({
        'slides': List.generate(
          100,
          (i) => {'layout': 'section', 'title': 'S$i'},
        ),
      })!;
      expect(deck.slides, hasLength(SlideLimits.slides));
    });
  });

  group('lo que no se puede leer', () {
    test('sin ninguna diapositiva legible no hay mazo', () {
      expect(SlideDeckJson.tryDecode('no es JSON'), isNull);
      expect(SlideDeckJson.tryDecode('{"title": "x"}'), isNull);
      expect(SlideDeckJson.tryDecode({'slides': 'tampoco'}), isNull);
      expect(SlideDeckJson.tryDecode(42), isNull);
      expect(
        SlideDeckJson.tryDecode({
          'slides': [
            {'layout': 'bullets'},
            'texto suelto',
            null,
          ],
        }),
        isNull,
      );
    });

    test('una diapositiva sin texto se descarta y las demás quedan', () {
      final deck = SlideDeckJson.tryDecode({
        'slides': [
          {'layout': 'quote'},
          {'layout': 'section', 'title': 'Queda'},
        ],
      })!;
      expect(deck.slides, [const Slide.section(title: 'Queda')]);
    });

    test('decode de algo roto da un mazo vacío, sin fallar', () {
      expect(SlideDeckJson.decode('{roto'), const SlideDeck(title: ''));
    });

    test('lo guardado con una clave que ya no se usa se sigue leyendo', () {
      final json = jsonEncode({
        'title': 'Viejo',
        'version': 7,
        'slides': [
          {'layout': 'closing', 'title': 'Fin', 'confetti': true},
        ],
      });
      expect(
        SlideDeckJson.decode(json).slides.single,
        const Slide.closing(title: 'Fin'),
      );
    });
  });
}
