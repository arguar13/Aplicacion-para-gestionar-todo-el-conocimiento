import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/anki_import/data/services/sqlite_anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';

import '../../../../support/anki_package_fixture.dart';

/// Mediodía local del 1 de marzo de 2026: el «día 0» de las colecciones de
/// estas pruebas.
final _crtDate = DateTime(2026, 3, 1, 4);
final _crt = _crtDate.millisecondsSinceEpoch ~/ 1000;

Future<AnkiImportedPackage> read(Uint8List bytes) =>
    const SqliteAnkiPackageReader().readBytes(bytes);

Future<AnkiImportException> failureOf(Uint8List bytes) async {
  try {
    await read(bytes);
  } on AnkiImportException catch (e) {
    return e;
  }
  throw TestFailure('Se esperaba un AnkiImportException.');
}

Future<AnkiImportException> failureOf2(
  SqliteAnkiPackageReader reader,
  Uint8List bytes,
) async {
  try {
    await reader.readBytes(bytes);
  } on AnkiImportException catch (e) {
    return e;
  }
  throw TestFailure('Se esperaba un AnkiImportException.');
}

Uint8List collection({
  List<Map<String, dynamic>>? models,
  List<Map<String, dynamic>>? decks,
  List<FixtureNote> notes = const [],
  List<FixtureCard> cards = const [],
  List<FixtureReview>? revlog,
}) => collectionBytes(
  crt: _crt,
  models: models ?? [basicModel(10)],
  decks: decks ?? [deck(1, 'Default')],
  notes: notes,
  cards: cards,
  revlog: revlog,
);

AnkiImportedCard single(AnkiImportedPackage package) {
  expect(package.cardCount, 1);
  return package.cards.single;
}

void main() {
  group('tarjetas básicas', () {
    test('frente, dorso, mazo y etiquetas', () async {
      final package = await read(
        apkgOf(
          collection(
            decks: [deck(1, 'Default'), deck(2, 'Historia::Roma')],
            notes: [
              const FixtureNote(
                id: 100,
                modelId: 10,
                fields: ['¿Quién fundó Roma?', 'Rómulo'],
                tags: ' historia roma::antigua ',
                guid: 'abc123',
              ),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100, deckId: 2)],
          ),
        ),
      );

      final deckOfCard = package.decks.single;
      expect(deckOfCard.path, 'Historia::Roma');
      expect(deckOfCard.name, 'Roma');
      expect(deckOfCard.levels, ['Historia', 'Roma']);
      final card = single(package);
      expect(card.kind, AnkiCardKind.basic);
      expect(card.front, '¿Quién fundó Roma?');
      expect(card.back, 'Rómulo');
      expect(card.tags, ['historia', 'roma::antigua']);
      expect(card.guid, 'abc123');
      expect(card.ankiCardId, 1000);
      expect(card.noteId, 100);
      expect(card.noteTypeName, 'Básico');
      expect(package.sourceFile, 'collection.anki21');
      expect(package.collectionCreatedAt, _crtDate);
    });

    test('el HTML sale del frente y del dorso', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(
                id: 100,
                modelId: 10,
                fields: [
                  '<div>Dos&nbsp;líneas</div><div>con <b>negrita</b></div>',
                  'Tom &amp; Jerry<br>y <i>más</i> &#233;',
                ],
              ),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100)],
          ),
        ),
      );

      final card = single(package);
      expect(card.front, 'Dos líneas\ncon **negrita**');
      expect(card.back, 'Tom & Jerry\ny *más* é');
    });

    test('los medios se cuentan, se sacan del texto y se avisan', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(
                id: 100,
                modelId: 10,
                fields: [
                  'Mirá <img src="mapa.png"> el mapa',
                  'Escuchá [sound:voz.mp3] y <img src="mapa.png">',
                ],
              ),
              const FixtureNote(
                id: 101,
                modelId: 10,
                fields: ['<img src="solo.jpg">', 'respuesta'],
              ),
            ],
            cards: [
              const FixtureCard(id: 1000, noteId: 100),
              const FixtureCard(id: 1001, noteId: 101),
            ],
          ),
          media: '{"0": "mapa.png", "1": "voz.mp3", "2": "solo.jpg"}',
        ),
      );

      final cards = package.cards.toList();
      expect(cards[0].front, 'Mirá el mapa');
      expect(cards[0].back, 'Escuchá y');
      expect(cards[0].media, const [
        AnkiMediaRef('mapa.png', AnkiMediaKind.image),
        AnkiMediaRef('voz.mp3', AnkiMediaKind.audio),
      ]);
      expect(cards[1].front, '');
      expect(cards[1].isMediaOnly, isTrue);
      expect(package.packageMediaFiles, 3);
      expect(package.imageCount, 2);
      expect(package.audioCount, 1);
      expect(package.videoCount, 0);
      expect(package.hasUnimportedMedia, isTrue);
    });

    test('un paquete sin medios no avisa de ninguno', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100)],
          ),
        ),
      );

      expect(package.hasUnimportedMedia, isFalse);
      expect(package.packageMediaFiles, 0);
    });

    test('Unicode: acentos, ñ, emoji y otros alfabetos', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(
                id: 100,
                modelId: 10,
                fields: ['¿Qué es la piña 🍍?', 'Привет 漢字 ñandú'],
                tags: ' ñandú ',
              ),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100)],
          ),
        ),
      );

      final card = single(package);
      expect(card.front, '¿Qué es la piña 🍍?');
      expect(card.back, 'Привет 漢字 ñandú');
      expect(card.tags, ['ñandú']);
    });
  });

  group('plantillas con forma propia', () {
    Future<List<AnkiImportedCard>> cardsOf(
      Map<String, dynamic> custom,
      List<String> fields, {
      int templates = 1,
    }) async {
      final package = await read(
        apkgOf(
          collection(
            models: [custom],
            notes: [FixtureNote(id: 100, modelId: 50, fields: fields)],
            cards: [
              for (var ord = 0; ord < templates; ord++)
                FixtureCard(id: 1000 + ord, noteId: 100, ord: ord),
            ],
          ),
        ),
      );
      return package.cards.toList();
    }

    test('un dorso que repite el frente sin {{FrontSide}} ni raya', () async {
      final cards = await cardsOf(
        model(
          id: 50,
          name: 'Repite',
          fields: ['Front', 'Back'],
          templates: [
            (name: 'T', qfmt: '{{Front}}', afmt: '{{Front}}<br>{{Back}}'),
          ],
        ),
        ['casa', 'house'],
      );

      expect(cards.single.front, 'casa');
      expect(cards.single.back, 'house');
    });

    test('un dorso con algo antes de la raya: la raya manda', () async {
      final cards = await cardsOf(
        model(
          id: 50,
          name: 'Con rótulo',
          fields: ['Front', 'Back'],
          templates: [
            (
              name: 'T',
              qfmt: '{{Front}}',
              afmt: '<b>Pregunta:</b> {{Front}}<hr id=answer>{{Back}}',
            ),
          ],
        ),
        ['casa', 'house'],
      );

      expect(cards.single.back, 'house');
    });

    test(
      'dos tarjetas donde solo el frente de una es el dorso de la otra',
      () async {
        Map<String, dynamic> twoWay(String q1, String a1) => model(
          id: 50,
          name: 'Rara',
          fields: ['Front', 'Back', 'Example'],
          templates: [
            (
              name: 'T1',
              qfmt: '{{Front}}',
              afmt: '{{FrontSide}}<hr id=answer>{{Back}}',
            ),
            (name: 'T2', qfmt: q1, afmt: '{{FrontSide}}<hr id=answer>$a1'),
          ],
        );

        // El frente de la 2 es el dorso de la 1, pero su dorso no es el frente.
        final first = await cardsOf(twoWay('{{Back}}', '{{Example}}'), [
          'casa',
          'house',
          'Mi casa',
        ], templates: 2);
        expect(first.map((c) => c.kind), everyElement(AnkiCardKind.basic));

        // El dorso de la 2 es el frente de la 1, pero su frente no es el dorso.
        final second = await cardsOf(twoWay('{{Example}}', '{{Front}}'), [
          'casa',
          'house',
          'Mi casa',
        ], templates: 2);
        expect(second.map((c) => c.kind), everyElement(AnkiCardKind.basic));
      },
    );

    test('el nombre de un mazo con separador U+001F usa "::"', () async {
      final package = await read(
        apkgOf(
          collection(
            decks: [deck(1, 'Default'), deck(2, 'Historia\u001fRoma')],
            notes: [
              const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100, deckId: 2)],
          ),
        ),
      );

      expect(package.decks.single.path, 'Historia::Roma');
    });
  });

  group('límites y fallos del disco', () {
    final bytes = apkgOf(
      collection(
        notes: [
          const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
        ],
        cards: [const FixtureCard(id: 1000, noteId: 100)],
      ),
    );

    test('una colección más grande que el tope se rechaza', () async {
      final error = await failureOf2(
        const SqliteAnkiPackageReader(maxCollectionBytes: 100),
        bytes,
      );

      expect(error.failure, AnkiImportFailure.corrupt);
    });

    test('con el tope justo, se lee', () async {
      final package = await const SqliteAnkiPackageReader(
        maxCollectionBytes: 10 * 1024 * 1024,
      ).readBytes(bytes);

      expect(package.cardCount, 1);
    });

    test(
      'si el disco falla al armar la carpeta de trabajo, no es "dañado"',
      () async {
        final error = await failureOf2(
          SqliteAnkiPackageReader(
            workDirectory: () async =>
                throw const FileSystemException('sin espacio'),
          ),
          bytes,
        );

        expect(error.failure, AnkiImportFailure.unreadable);
        expect(error.cause, isA<FileSystemException>());
      },
    );
  });

  group('dos direcciones', () {
    test(
      'las dos tarjetas hermanas llegan marcadas, con el frente cruzado',
      () {
        return read(
          apkgOf(
            collection(
              models: [reversedModel(11)],
              notes: [
                const FixtureNote(
                  id: 100,
                  modelId: 11,
                  fields: ['perro', 'dog'],
                ),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100),
                const FixtureCard(id: 1001, noteId: 100, ord: 1),
              ],
            ),
          ),
        ).then((package) {
          final cards = package.cards.toList();
          expect(cards, hasLength(2));
          expect(cards.map((c) => c.kind), everyElement(AnkiCardKind.reversed));
          expect(cards[0].front, 'perro');
          expect(cards[0].back, 'dog');
          expect(cards[1].front, 'dog');
          expect(cards[1].back, 'perro');
          expect(cards[0].noteId, cards[1].noteId);
          expect(cards.map((c) => c.ord), [0, 1]);
        });
      },
    );

    test(
      'la invertida opcional: sin la marca es básica, con la marca no',
      () async {
        final package = await read(
          apkgOf(
            collection(
              models: [optionalReversedModel(12)],
              notes: [
                const FixtureNote(id: 100, modelId: 12, fields: ['a', 'b', '']),
                const FixtureNote(
                  id: 101,
                  modelId: 12,
                  fields: ['c', 'd', 'y'],
                ),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100),
                const FixtureCard(id: 1001, noteId: 101),
                const FixtureCard(id: 1002, noteId: 101, ord: 1),
              ],
            ),
          ),
        );

        final cards = package.cards.toList();
        expect(cards.map((c) => c.kind), [
          AnkiCardKind.basic,
          AnkiCardKind.reversed,
          AnkiCardKind.reversed,
        ]);
        expect(cards[2].front, 'd');
        expect(cards[2].back, 'c');
      },
    );

    test(
      'dos tarjetas de una nota que NO son una la inversa de la otra',
      () async {
        final custom = model(
          id: 13,
          name: 'Con ejemplo',
          fields: ['Front', 'Back', 'Example'],
          templates: [
            (
              name: 'Tarjeta 1',
              qfmt: '{{Front}}',
              afmt: '{{FrontSide}}<hr id=answer>{{Back}}',
            ),
            (
              name: 'Tarjeta 2',
              qfmt: '{{Front}} (ejemplo)',
              afmt: '{{FrontSide}}<hr id=answer>{{Example}}',
            ),
          ],
        );
        final package = await read(
          apkgOf(
            collection(
              models: [custom],
              notes: [
                const FixtureNote(
                  id: 100,
                  modelId: 13,
                  fields: ['casa', 'house', 'Mi casa es tu casa'],
                ),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100),
                const FixtureCard(id: 1001, noteId: 100, ord: 1),
              ],
            ),
          ),
        );

        final cards = package.cards.toList();
        expect(cards.map((c) => c.kind), everyElement(AnkiCardKind.basic));
        expect(cards[1].front, 'casa (ejemplo)');
        expect(cards[1].back, 'Mi casa es tu casa');
      },
    );
  });

  group('huecos', () {
    test(
      'una tarjeta por número, con la pregunta armada y la fuente',
      () async {
        final package = await read(
          apkgOf(
            collection(
              models: [clozeModel(14)],
              notes: [
                const FixtureNote(
                  id: 100,
                  modelId: 14,
                  fields: [
                    'El {{c1::Imperio romano}} cayó en {{c2::476}}',
                    'Occidente',
                  ],
                ),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100),
                const FixtureCard(id: 1001, noteId: 100, ord: 1),
              ],
            ),
          ),
        );

        final cards = package.cards.toList();
        expect(cards.map((c) => c.kind), everyElement(AnkiCardKind.cloze));
        expect(cards[0].clozeNumber, 1);
        expect(cards[0].front, 'El [...] cayó en 476');
        expect(cards[0].back, 'El **Imperio romano** cayó en 476\n\nOccidente');
        expect(cards[1].clozeNumber, 2);
        expect(cards[1].front, 'El Imperio romano cayó en [...]');
        expect(
          cards[1].clozeSource,
          'El {{c1::Imperio romano}} cayó en {{c2::476}}',
        );
      },
    );

    test('con pista, con HTML adentro y sin extra', () async {
      final package = await read(
        apkgOf(
          collection(
            models: [clozeModel(14)],
            notes: [
              const FixtureNote(
                id: 100,
                modelId: 14,
                fields: [
                  'La capital de <b>Francia</b> es {{c1::<i>París</i>::ciudad}}.',
                  '',
                ],
              ),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100)],
          ),
        ),
      );

      final card = single(package);
      expect(card.front, 'La capital de Francia es [ciudad].');
      expect(card.back, 'La capital de Francia es **París**.');
    });

    test(
      'una tarjeta de un número que ya no está en el texto se deja afuera',
      () async {
        final package = await read(
          apkgOf(
            collection(
              models: [clozeModel(14)],
              notes: [
                const FixtureNote(
                  id: 100,
                  modelId: 14,
                  fields: ['Solo {{c1::uno}}', ''],
                ),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100),
                const FixtureCard(id: 1001, noteId: 100, ord: 4),
              ],
            ),
          ),
        );

        expect(package.cardCount, 1);
        expect(package.skippedCards, 1);
      },
    );
  });

  group('escribir la respuesta', () {
    test(
      'el frente no trae la caja y el dorso es lo que hay que escribir',
      () async {
        final package = await read(
          apkgOf(
            collection(
              models: [typedModel(15)],
              notes: [
                const FixtureNote(
                  id: 100,
                  modelId: 15,
                  fields: ['Capital de España', 'Madrid'],
                ),
              ],
              cards: [const FixtureCard(id: 1000, noteId: 100)],
            ),
          ),
        );

        final card = single(package);
        expect(card.kind, AnkiCardKind.typed);
        expect(card.front, 'Capital de España');
        expect(card.back, 'Madrid');
      },
    );
  });

  group('calendario', () {
    Future<AnkiCardSchedule> schedule(
      FixtureCard card, {
      List<FixtureReview>? revlog,
    }) async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
            ],
            cards: [card],
            revlog: revlog,
          ),
        ),
      );
      return single(package).schedule;
    }

    test('una tarjeta de repaso: SM-2 y el día de vencimiento', () async {
      final s = await schedule(
        const FixtureCard(
          id: 1000,
          noteId: 100,
          type: 2,
          queue: 2,
          due: 30,
          ivl: 21,
          factor: 2300,
          reps: 7,
          lapses: 2,
        ),
      );

      expect(s.state, AnkiCardState.review);
      expect(s.easeFactor, 2.3);
      expect(s.intervalDays, 21);
      expect(s.repetitions, 7);
      expect(s.lapses, 2);
      expect(s.dueAt, DateTime(2026, 3, 31, 4));
      expect(s.suspended, isFalse);
      expect(s.postponed, isFalse);
      expect(s.isNew, isFalse);
      expect(s.newPosition, isNull);
    });

    test(
      'una tarjeta nueva: sin vencimiento, con su lugar en la cola',
      () async {
        final s = await schedule(
          const FixtureCard(id: 1000, noteId: 100, due: 17),
        );

        expect(s.state, AnkiCardState.newCard);
        expect(s.isNew, isTrue);
        expect(s.dueAt, isNull);
        expect(s.newPosition, 17);
        expect(s.easeFactor, 2.5);
        expect(s.intervalDays, 0);
        expect(s.repetitions, 0);
      },
    );

    test('suspendida y pospuesta (de las dos formas)', () async {
      final suspended = await schedule(
        const FixtureCard(
          id: 1000,
          noteId: 100,
          type: 2,
          queue: -1,
          due: 5,
          ivl: 5,
          factor: 2500,
          reps: 3,
        ),
      );
      expect(suspended.suspended, isTrue);
      expect(suspended.postponed, isFalse);
      expect(suspended.state, AnkiCardState.review);
      expect(suspended.dueAt, DateTime(2026, 3, 6, 4));

      for (final queue in [-2, -3]) {
        final postponed = await schedule(
          FixtureCard(
            id: 1000,
            noteId: 100,
            type: 2,
            queue: queue,
            due: 5,
            ivl: 5,
            factor: 2500,
            reps: 3,
          ),
        );
        expect(postponed.postponed, isTrue, reason: 'queue $queue');
        expect(postponed.suspended, isFalse);
      }
    });

    test('una tarjeta nueva suspendida sigue siendo nueva', () async {
      final s = await schedule(
        const FixtureCard(id: 1000, noteId: 100, queue: -1, due: 3),
      );

      expect(s.state, AnkiCardState.newCard);
      expect(s.suspended, isTrue);
    });

    test('en aprendizaje: el vencimiento son segundos desde 1970', () async {
      final at = DateTime(2026, 3, 10, 15, 30);
      final seconds = at.millisecondsSinceEpoch ~/ 1000;
      final s = await schedule(
        FixtureCard(
          id: 1000,
          noteId: 100,
          type: 1,
          queue: 1,
          due: seconds,
          factor: 2500,
          reps: 1,
        ),
      );

      expect(s.state, AnkiCardState.learning);
      expect(s.dueAt, at);
      expect(s.intervalDays, 0);
      expect(s.repetitions, 1);
    });

    test('reaprendiendo, con lapsos; y en aprendizaje por días', () async {
      final relearning = await schedule(
        const FixtureCard(
          id: 1000,
          noteId: 100,
          type: 3,
          queue: 1,
          due: 1773000000,
          ivl: 4,
          factor: 2100,
          reps: 12,
          lapses: 3,
        ),
      );
      expect(relearning.state, AnkiCardState.relearning);
      expect(relearning.lapses, 3);
      expect(relearning.intervalDays, 4);

      final daysLearning = await schedule(
        const FixtureCard(
          id: 1001,
          noteId: 100,
          type: 1,
          queue: 3,
          due: 2,
          reps: 1,
        ),
      );
      expect(daysLearning.state, AnkiCardState.learning);
      expect(daysLearning.dueAt, DateTime(2026, 3, 3, 4));
    });

    test(
      'el factor 0 de una tarjeta que no es nueva, y los muy bajos',
      () async {
        final zero = await schedule(
          const FixtureCard(
            id: 1000,
            noteId: 100,
            type: 2,
            queue: 2,
            ivl: 1,
            reps: 1,
          ),
        );
        expect(zero.easeFactor, 2.5);

        final low = await schedule(
          const FixtureCard(
            id: 1001,
            noteId: 100,
            type: 2,
            queue: 2,
            ivl: 1,
            factor: 1000,
            reps: 1,
          ),
        );
        expect(low.easeFactor, 1.3);
      },
    );

    test('una tarjeta de repaso sin repeticiones cuenta como una', () async {
      final s = await schedule(
        const FixtureCard(
          id: 1000,
          noteId: 100,
          type: 2,
          queue: 2,
          ivl: 3,
          factor: 2500,
        ),
      );

      expect(s.repetitions, 1);
    });

    test('un intervalo negativo (segundos) es 0 días', () async {
      final s = await schedule(
        const FixtureCard(
          id: 1000,
          noteId: 100,
          type: 1,
          queue: 1,
          due: 1773000000,
          ivl: -600,
          reps: 1,
        ),
      );

      expect(s.intervalDays, 0);
    });

    test(
      'en un mazo filtrado: el mazo y el calendario son los originales',
      () async {
        final package = await read(
          apkgOf(
            collection(
              decks: [
                deck(1, 'Default'),
                deck(2, 'Historia'),
                deck(3, 'Filtrado', filtered: true),
              ],
              notes: [
                const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
              ],
              cards: [
                const FixtureCard(
                  id: 1000,
                  noteId: 100,
                  deckId: 3,
                  type: 2,
                  queue: 2,
                  due: 999,
                  odue: 12,
                  odid: 2,
                  ivl: 9,
                  factor: 2500,
                  reps: 4,
                ),
              ],
            ),
          ),
        );

        expect(package.decks.single.path, 'Historia');
        final s = single(package).schedule;
        expect(s.inFilteredDeck, isTrue);
        expect(s.dueAt, DateTime(2026, 3, 13, 4));
        expect(package.warnings.single, contains('mazo filtrado'));
      },
    );

    test(
      'el último repaso sale del historial, y el historial se trae',
      () async {
        final first = DateTime(2026, 3, 2, 9).millisecondsSinceEpoch;
        final second = DateTime(2026, 3, 5, 9).millisecondsSinceEpoch;
        final package = await read(
          apkgOf(
            collection(
              notes: [
                const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
              ],
              cards: [
                const FixtureCard(
                  id: 1000,
                  noteId: 100,
                  type: 2,
                  queue: 2,
                  due: 9,
                  ivl: 6,
                  factor: 2500,
                  reps: 2,
                ),
              ],
              revlog: [
                FixtureReview(
                  id: second,
                  cardId: 1000,
                  ease: 3,
                  ivl: 6,
                  lastIvl: 1,
                ),
                FixtureReview(id: first, cardId: 1000, ease: 3, time: 4200),
                // Reprogramada a mano: no es un repaso.
                const FixtureReview(id: 5, cardId: 1000, ease: 0),
              ],
            ),
          ),
        );

        expect(
          single(package).schedule.lastReviewedAt,
          DateTime.fromMillisecondsSinceEpoch(second),
        );
        expect(package.reviews, hasLength(2));
        expect(
          package.reviews.first.reviewedAt,
          DateTime.fromMillisecondsSinceEpoch(first),
        );
        expect(package.reviews.first.ease, 3);
        expect(package.reviews.first.durationMs, 4200);
        expect(package.reviews.last.previousIntervalDays, 1);
        expect(package.reviews.last.intervalDays, 6);
      },
    );

    test('sin tabla de historial, el calendario sigue valiendo', () async {
      final bytes = collectionBytes(
        crt: _crt,
        models: [basicModel(10)],
        decks: [deck(1, 'Default')],
        notes: const [
          FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
        ],
        cards: const [FixtureCard(id: 1000, noteId: 100)],
        withRevlogTable: false,
      );
      final package = await read(apkgOf(bytes));

      expect(package.cardCount, 1);
      expect(package.reviews, isEmpty);
      expect(
        package.warnings,
        contains('El mazo no trae el historial de repasos.'),
      );
    });
  });

  group('varios mazos y notas raras', () {
    test(
      'los mazos salen en el orden de su primera tarjeta, sin los vacíos',
      () async {
        final package = await read(
          apkgOf(
            collection(
              decks: [
                deck(1, 'Default'),
                deck(2, 'B'),
                deck(3, 'A::Sub'),
                deck(4, 'Vacío'),
              ],
              notes: [
                for (var i = 0; i < 3; i++)
                  FixtureNote(id: 100 + i, modelId: 10, fields: ['f$i', 'b$i']),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100, deckId: 3),
                const FixtureCard(id: 1001, noteId: 101, deckId: 2),
                const FixtureCard(id: 1002, noteId: 102, deckId: 3),
              ],
            ),
          ),
        );

        expect(package.decks.map((d) => d.path), ['A::Sub', 'B']);
        expect(package.decks.first.cards, hasLength(2));
        expect(package.cardCount, 3);
      },
    );

    test(
      'una tarjeta de una nota que no existe se cuenta y no rompe',
      () async {
        final package = await read(
          apkgOf(
            collection(
              notes: [
                const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
              ],
              cards: [
                const FixtureCard(id: 1000, noteId: 100),
                const FixtureCard(id: 1001, noteId: 999),
              ],
            ),
          ),
        );

        expect(package.cardCount, 1);
        expect(package.skippedCards, 1);
      },
    );

    test('una nota de un tipo que no está en el paquete', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
              const FixtureNote(id: 101, modelId: 77, fields: ['x', 'y']),
            ],
            cards: [
              const FixtureCard(id: 1000, noteId: 100),
              const FixtureCard(id: 1001, noteId: 101),
            ],
          ),
        ),
      );

      expect(package.cardCount, 1);
      expect(package.skippedCards, 1);
      expect(package.warnings, isNotEmpty);
    });

    test('una tarjeta sin nada que mostrar se deja afuera', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(id: 100, modelId: 10, fields: ['', '']),
              const FixtureNote(id: 101, modelId: 10, fields: ['a', 'b']),
            ],
            cards: [
              const FixtureCard(id: 1000, noteId: 100),
              const FixtureCard(id: 1001, noteId: 101),
            ],
          ),
        ),
      );

      expect(package.cardCount, 1);
      expect(package.skippedCards, 1);
    });

    test('una nota con menos campos de los que dice el tipo', () async {
      final package = await read(
        apkgOf(
          collection(
            notes: [
              const FixtureNote(id: 100, modelId: 10, fields: ['solo frente']),
            ],
            cards: [const FixtureCard(id: 1000, noteId: 100)],
          ),
        ),
      );

      final card = single(package);
      expect(card.front, 'solo frente');
      expect(card.back, '');
    });

    test('un mazo sin tarjetas lo dice', () async {
      final package = await read(apkgOf(collection()));

      expect(package.decks, isEmpty);
      expect(
        package.warnings,
        contains('El mazo de Anki no tiene ninguna tarjeta.'),
      );
    });
  });

  group('qué colección se lee', () {
    final legacy = collection(
      notes: [
        const FixtureNote(id: 100, modelId: 10, fields: ['vieja', 'x']),
      ],
      cards: [const FixtureCard(id: 1000, noteId: 100)],
    );
    final newer = collection(
      notes: [
        const FixtureNote(id: 100, modelId: 10, fields: ['nueva', 'x']),
      ],
      cards: [const FixtureCard(id: 1000, noteId: 100)],
    );

    test('collection.anki2 solo (el que escribe Sinapsis)', () async {
      final package = await read(
        apkgOf(legacy, collectionName: 'collection.anki2'),
      );

      expect(package.sourceFile, 'collection.anki2');
      expect(single(package).front, 'vieja');
    });

    test('collection.anki21 le gana a collection.anki2', () async {
      final package = await read(
        zipOf({
          'collection.anki2': legacy,
          'collection.anki21': newer,
          'media': '{}'.codeUnits,
        }),
      );

      expect(package.sourceFile, 'collection.anki21');
      expect(single(package).front, 'nueva');
    });

    test('el formato nuevo solo: error claro y específico', () async {
      final error = await failureOf(
        zipOf({
          'collection.anki21b': List.filled(64, 7),
          'meta': const [8, 3],
          'media': const [1, 2, 3],
        }),
      );

      expect(error.failure, AnkiImportFailure.newFormatOnly);
      expect(error.message, contains('Compatibilidad con versiones antiguas'));
    });

    test(
      'el formato nuevo con el relleno de collection.anki2: lo mismo',
      () async {
        final error = await failureOf(
          zipOf({
            'collection.anki21b': List.filled(64, 7),
            'collection.anki2': placeholderCollection(),
            'media': const [1, 2, 3],
          }),
        );

        expect(error.failure, AnkiImportFailure.newFormatOnly);
      },
    );

    test(
      'el formato nuevo con un collection.anki2 de verdad: se usa ese',
      () async {
        final package = await read(
          zipOf({
            'collection.anki21b': List.filled(64, 7),
            'collection.anki2': legacy,
            'media': '{}'.codeUnits,
          }),
        );

        expect(single(package).front, 'vieja');
      },
    );

    test('el relleno en anki2 y la colección de verdad en anki21', () async {
      final package = await read(
        zipOf({
          'collection.anki2': placeholderCollection(),
          'collection.anki21': newer,
          'media': '{}'.codeUnits,
        }),
      );

      expect(single(package).front, 'nueva');
    });

    test(
      'solo el relleno (sin formato nuevo): también es el formato nuevo',
      () async {
        final error = await failureOf(
          apkgOf(placeholderCollection(), collectionName: 'collection.anki2'),
        );

        expect(error.failure, AnkiImportFailure.newFormatOnly);
      },
    );
  });

  group('archivos que no sirven', () {
    test('vacío', () async {
      final error = await failureOf(Uint8List(0));

      expect(error.failure, AnkiImportFailure.emptyFile);
      expect(error.message, isNotEmpty);
    });

    test('bytes cualquiera', () async {
      final error = await failureOf(
        Uint8List.fromList(List.generate(500, (i) => (i * 37) % 251)),
      );

      expect(error.failure, AnkiImportFailure.notAnApkg);
    });

    test('un texto', () async {
      final error = await failureOf(Uint8List.fromList('hola mundo'.codeUnits));

      expect(error.failure, AnkiImportFailure.notAnApkg);
    });

    test('un zip sin colección', () async {
      final error = await failureOf(
        zipOf({
          'foto.jpg': const [1, 2, 3],
          'notas.txt': 'hola'.codeUnits,
        }),
      );

      expect(error.failure, AnkiImportFailure.notAnApkg);
    });

    test('un zip vacío', () async {
      final error = await failureOf(zipOf(const {}));

      expect(error.failure, AnkiImportFailure.notAnApkg);
    });

    test('un zip cortado a la mitad', () async {
      final full = apkgOf(
        collection(
          notes: [
            const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
          ],
          cards: [const FixtureCard(id: 1000, noteId: 100)],
        ),
      );
      final error = await failureOf(
        Uint8List.sublistView(full, 0, full.length ~/ 2),
      );

      expect(
        error.failure,
        anyOf(AnkiImportFailure.notAnApkg, AnkiImportFailure.corrupt),
      );
    });

    test('la colección no es una base SQLite', () async {
      final error = await failureOf(
        apkgOf(
          Uint8List.fromList(List.filled(2048, 65)),
          collectionName: 'collection.anki2',
        ),
      );

      expect(error.failure, AnkiImportFailure.corrupt);
    });

    test('una base SQLite que no es de Anki', () async {
      final error = await failureOf(
        apkgOf(unrelatedDatabaseBytes(), collectionName: 'collection.anki2'),
      );

      expect(error.failure, AnkiImportFailure.corrupt);
    });

    test(
      'el esquema nuevo, con los tipos de nota y mazos vacíos en col',
      () async {
        // `col` con `models` y `decks` vacíos, como en el esquema 18.
        final emptied = rewriteColJson(collection(), models: '', decks: '');
        final error = await failureOf(
          apkgOf(emptied, collectionName: 'collection.anki2'),
        );

        expect(error.failure, AnkiImportFailure.unsupportedSchema);
        expect(
          error.message,
          contains('Compatibilidad con versiones antiguas'),
        );
      },
    );

    test('JSON de tipos de nota dañado', () async {
      final broken = rewriteColJson(
        collection(
          notes: [
            const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
          ],
          cards: [const FixtureCard(id: 1000, noteId: 100)],
        ),
        models: '{no es json',
        decks: '{}',
      );
      final error = await failureOf(
        apkgOf(broken, collectionName: 'collection.anki2'),
      );

      expect(error.failure, AnkiImportFailure.corrupt);
    });

    test(
      'nunca una excepción cruda: todo falla con AnkiImportException',
      () async {
        final samples = <Uint8List>[
          Uint8List(0),
          Uint8List(1),
          Uint8List.fromList('PK'.codeUnits),
          Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4, 5, 6, 7, 8]),
          Uint8List.fromList(List.filled(100, 0)),
          zipOf({'collection.anki2': const []}),
          zipOf({
            'collection.anki21': const [1, 2, 3],
          }),
          zipOf({'collection.anki21b': const []}),
        ];

        for (final sample in samples) {
          await expectLater(
            read(sample),
            throwsA(isA<AnkiImportException>()),
            reason: 'con ${sample.length} bytes',
          );
        }
      },
    );
  });

  group('desde un archivo', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sinapsis-anki-t-'));
    tearDown(() => dir.deleteSync(recursive: true));

    int leftovers() => Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).startsWith('sinapsis-anki-'))
        .where((d) => !d.path.startsWith(dir.path))
        .where(
          (d) =>
              !p.basename(d.path).startsWith('sinapsis-anki-t-') &&
              !p.basename(d.path).startsWith('sinapsis-anki-test-') &&
              !p.basename(d.path).startsWith('sinapsis-anki-fixture-'),
        )
        .length;

    test('lee un .apkg del disco y no deja temporales', () async {
      final file = File(p.join(dir.path, 'mazo.apkg'))
        ..writeAsBytesSync(
          apkgOf(
            collection(
              notes: [
                const FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
              ],
              cards: [const FixtureCard(id: 1000, noteId: 100)],
            ),
          ),
        );
      final before = leftovers();

      final package = await const SqliteAnkiPackageReader().readFile(file.path);

      expect(single(package).front, 'a');
      expect(leftovers(), before);
      // El archivo original queda como estaba.
      expect(file.existsSync(), isTrue);
    });

    test('tampoco deja temporales cuando falla', () async {
      final file = File(p.join(dir.path, 'roto.apkg'))
        ..writeAsBytesSync(
          apkgOf(
            Uint8List.fromList(List.filled(1024, 3)),
            collectionName: 'collection.anki2',
          ),
        );
      final before = leftovers();

      await expectLater(
        const SqliteAnkiPackageReader().readFile(file.path),
        throwsA(isA<AnkiImportException>()),
      );
      expect(leftovers(), before);
    });

    test('un archivo que no existe y uno vacío', () async {
      await expectLater(
        const SqliteAnkiPackageReader().readFile(p.join(dir.path, 'no.apkg')),
        throwsA(
          isA<AnkiImportException>().having(
            (e) => e.failure,
            'failure',
            AnkiImportFailure.emptyFile,
          ),
        ),
      );

      final empty = File(p.join(dir.path, 'vacio.apkg'))..writeAsBytesSync([]);
      await expectLater(
        const SqliteAnkiPackageReader().readFile(empty.path),
        throwsA(
          isA<AnkiImportException>().having(
            (e) => e.failure,
            'failure',
            AnkiImportFailure.emptyFile,
          ),
        ),
      );
    });

    test('un archivo que no es un zip', () async {
      final file = File(p.join(dir.path, 'texto.apkg'))
        ..writeAsStringSync('esto no es un zip' * 100);

      await expectLater(
        const SqliteAnkiPackageReader().readFile(file.path),
        throwsA(
          isA<AnkiImportException>().having(
            (e) => e.failure,
            'failure',
            AnkiImportFailure.notAnApkg,
          ),
        ),
      );
    });
  });
}
