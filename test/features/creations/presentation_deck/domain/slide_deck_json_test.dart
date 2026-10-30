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
    test('los mazos de ejemplo vuelven idénticos, con los veinte diseños', () {
      final deck = sampleDeck(illustrations: true);
      final again = SlideDeckJson.decode(SlideDeckJson.encodeString(deck));
      expect(again, deck);

      final more = moreDeck(illustrations: true);
      final moreAgain = SlideDeckJson.decode(SlideDeckJson.encodeString(more));
      expect(moreAgain, more);

      expect({
        ...again.slides.map((s) => s.layout),
        ...moreAgain.slides.map((s) => s.layout),
      }, SlideLayout.values.toSet());
    });

    test('el peor caso de F45 vuelve idéntico', () {
      final deck = longMoreDeck();
      expect(SlideDeckJson.decode(SlideDeckJson.encode(deck)), deck);
    });

    test('un mazo guardado por F43 se sigue leyendo igual', () {
      // Tal como lo escribía la versión de F43: sin nada de lo nuevo.
      final saved = jsonEncode({
        'title': 'Éxodo',
        'format': 'detailed',
        'slides': [
          {'layout': 'cover', 'title': 'Éxodo', 'kicker': 'Estudio'},
          {'layout': 'big_number', 'value': '40 años', 'label': 'de travesía'},
          {
            'layout': 'closing',
            'title': 'Fin',
            'takeaways': ['Uno', 'Dos'],
          },
        ],
      });
      expect(
        SlideDeckJson.decode(saved),
        const SlideDeck(
          title: 'Éxodo',
          slides: [
            Slide.cover(title: 'Éxodo', kicker: 'Estudio'),
            Slide.bigNumber(value: '40 años', label: 'de travesía'),
            Slide.closing(title: 'Fin', takeaways: ['Uno', 'Dos']),
          ],
        ),
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

  group('los diseños de F45, de la IA', () {
    test('por su nombre en castellano y con sus claves en castellano', () {
      expect(
        only({
          'tipo': 'Matriz 2x2',
          'título': 'Actitudes',
          'eje_x': 'Saber',
          'eje_y': 'Hacer',
          'cuadrantes': [
            {'titulo': 'A', 'puntos': 'uno'},
            {
              'titulo': 'B',
              'puntos': ['dos'],
            },
            {'titulo': 'C'},
            {'titulo': 'D'},
          ],
        }),
        const Slide.matrix(
          title: 'Actitudes',
          xAxis: 'Saber',
          yAxis: 'Hacer',
          quadrants: [
            SlideColumn(heading: 'A', points: ['uno']),
            SlideColumn(heading: 'B', points: ['dos']),
            SlideColumn(heading: 'C'),
            SlideColumn(heading: 'D'),
          ],
        ),
      );
      expect(
        only({
          'diseño': 'definición',
          'término': 'Pascua',
          'definición': 'La fiesta de la salida',
          'ejemplo': 'El cordero',
        }),
        const Slide.definition(
          term: 'Pascua',
          definition: 'La fiesta de la salida',
          example: 'El cordero',
        ),
      );
      expect(
        only({
          'layout': 'ciclo',
          'title': 'Agua',
          'centro': 'El agua',
          'pasos': ['Lluvia', 'Río', 'Mar'],
        }),
        const Slide.cycle(
          title: 'Agua',
          center: 'El agua',
          steps: [
            SlideStep(title: 'Lluvia'),
            SlideStep(title: 'Río'),
            SlideStep(title: 'Mar'),
          ],
        ),
      );
      expect(
        only({
          'layout': 'preguntas',
          'title': 'Para pensar',
          'preguntas': '1. ¿Por qué?\n2. ¿Para qué?',
        }),
        const Slide.questions(
          title: 'Para pensar',
          questions: ['¿Por qué?', '¿Para qué?'],
        ),
      );
      expect(
        only({
          'layout': 'galeria',
          'title': 'Lugares',
          'imagenes': [
            'Egipto',
            {'epigrafe': 'El mar', 'icono': 'water'},
          ],
        }),
        const Slide.imageGrid(
          title: 'Lugares',
          images: [
            SlideImage(caption: 'Egipto'),
            SlideImage(caption: 'El mar', icon: 'water'),
          ],
        ),
      );
      expect(
        only({
          'layout': 'paneldecifras',
          'cifras': [
            {'valor': 40, 'etiqueta': 'años'},
            {'value': '10', 'title': 'plagas'},
            'suelta',
          ],
        }),
        const Slide.statGrid(
          title: '',
          stats: [
            SlideStat(value: '40', label: 'años'),
            SlideStat(value: '10', label: 'plagas'),
          ],
        ),
      );
      expect(
        only({
          'layout': 'mapa conceptual',
          'title': 'Alianza',
          'ramas': ['Ley', 'Promesa', 'Memoria'],
        }),
        const Slide.conceptMap(
          title: 'Alianza',
          nodes: [
            SlideConcept(title: 'Ley'),
            SlideConcept(title: 'Promesa'),
            SlideConcept(title: 'Memoria'),
          ],
        ),
      );
      expect(
        only({'layout': 'cita grande', 'cita': '«Yo soy»', 'autor': 'Dios'}),
        const Slide.fullQuote(quote: 'Yo soy', author: 'Dios'),
      );
    });

    test('a medias: lo que les falta los pasa a viñetas, sin perder texto', () {
      // Una matriz de tres no dice qué va dónde.
      expect(
        only({
          'layout': 'matrix',
          'title': 'Tres',
          'quadrants': [
            {
              'heading': 'A',
              'points': ['uno'],
            },
            {
              'heading': 'B',
              'points': ['dos'],
            },
            {
              'heading': 'C',
              'points': ['tres'],
            },
          ],
        }),
        const Slide.bullets(title: 'Tres', bullets: ['uno', 'dos', 'tres']),
      );
      // Un ciclo de dos se lee mejor como pasos; acá, como viñetas.
      expect(
        only({
          'layout': 'cycle',
          'title': 'Ida y vuelta',
          'steps': [
            {'title': 'Ida'},
            {'title': 'Vuelta'},
          ],
        }),
        const Slide.bullets(title: 'Ida y vuelta', bullets: ['Ida', 'Vuelta']),
      );
      // Una definición sin qué es: el término queda de título.
      expect(
        only({'layout': 'definition', 'term': 'Pascua', 'example': 'Cordero'}),
        const Slide.bullets(title: '', bullets: ['Pascua', 'Cordero']),
      );
      // Un mapa de dos ramas, una cuadrícula de una imagen, un panel de una
      // cifra, unas preguntas vacías.
      expect(
        only({
          'layout': 'concept_map',
          'title': 'Poco',
          'nodes': ['a', 'b'],
        }),
        const Slide.bullets(title: 'Poco', bullets: ['a', 'b']),
      );
      expect(
        only({
          'layout': 'image_grid',
          'title': 'Una',
          'images': [
            {'caption': 'sola'},
          ],
        }),
        const Slide.bullets(title: 'Una', bullets: ['sola']),
      );
      expect(
        only({
          'layout': 'stat_grid',
          'title': 'Una cifra',
          'stats': [
            {'value': '40', 'label': 'años'},
          ],
        }),
        const Slide.bullets(title: 'Una cifra', bullets: ['40 — años']),
      );
      expect(
        SlideDeckJson.tryDecode({
          'slides': [
            {'layout': 'questions', 'questions': <String>[]},
          ],
        }),
        isNull,
      );
    });

    test('mal formados: los tipos raros no rompen nada', () {
      expect(
        only({
          'layout': 'stat_grid',
          'title': 'Raro',
          'stats': {'value': '1'},
        }),
        const Slide.bullets(title: 'Raro'),
      );
      expect(
        only({
          'layout': 'matrix',
          'title': 'Raro',
          'quadrants': 'cuatro',
          'x_axis': 3,
        }),
        const Slide.bullets(title: 'Raro'),
      );
      expect(
        only({
          'layout': 'full_quote',
          'quote': ['no', 'es', 'texto'],
          'title': 'Sin cita',
        }),
        const Slide.bullets(title: 'Sin cita'),
      );
    });

    test('sus listas no pasan de su tope', () {
      final many = [for (var i = 0; i < 12; i++) 'cosa $i'];
      final grid =
          only({'layout': 'image_grid', 'title': 'T', 'images': many})
              as ImageGridSlide;
      expect(grid.images, hasLength(SlideLimits.images));
      final map =
          only({'layout': 'concept_map', 'title': 'T', 'nodes': many})
              as ConceptMapSlide;
      expect(map.nodes, hasLength(SlideLimits.nodes));
      final questions =
          only({'layout': 'questions', 'title': 'T', 'questions': many})
              as QuestionsSlide;
      expect(questions.questions, hasLength(SlideLimits.questions));
      final cycle =
          only({'layout': 'cycle', 'title': 'T', 'steps': many}) as CycleSlide;
      expect(cycle.steps, hasLength(SlideLimits.cycleSteps));
      final matrix =
          only({
                'layout': 'matrix',
                'title': 'T',
                'quadrants': [
                  for (final m in many)
                    {
                      'heading': m,
                      'points': [m],
                    },
                ],
              })
              as MatrixSlide;
      expect(matrix.quadrants, hasLength(SlideLimits.quadrants));
      final stats =
          only({
                'layout': 'stat_grid',
                'title': 'T',
                'stats': [
                  for (final m in many) {'value': '1', 'label': m},
                ],
              })
              as StatGridSlide;
      expect(stats.stats, hasLength(SlideLimits.stats));
    });

    test('el título que se ve, para la miniatura y el índice', () {
      expect(
        const Slide.definition(term: 'Pascua', definition: 'x').headline,
        'Pascua',
      );
      expect(const Slide.fullQuote(quote: 'Yo soy').headline, 'Yo soy');
      expect(
        const Slide.conceptMap(title: '', center: 'Alianza').headline,
        'Alianza',
      );
      expect(
        const Slide.statGrid(
          title: '',
          stats: [SlideStat(value: '40')],
        ).headline,
        '40',
      );
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
