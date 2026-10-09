import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_ids.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_planner.dart';

/// De un paquete de Anki a lo que se escribe en Sinapsis (F31, decisión 73):
/// dónde cae cada tarjeta y cómo se traduce su calendario a SM-2.
void main() {
  // Jueves 8 de octubre de 2026, 10:30.
  final now = DateTime(2026, 10, 8, 10, 30);

  AnkiImportedCard card({
    int id = 1700000000000,
    int noteId = 1,
    String guid = 'g1',
    int ord = 0,
    AnkiCardKind kind = AnkiCardKind.basic,
    String front = 'P',
    String back = 'R',
    AnkiCardSchedule? schedule,
    String? clozeSource,
    int? clozeNumber,
    List<String> distractors = const [],
    List<AnkiMediaRef> media = const [],
  }) => AnkiImportedCard(
    ankiCardId: id,
    noteId: noteId,
    guid: guid,
    ord: ord,
    kind: kind,
    front: front,
    back: back,
    schedule:
        schedule ??
        const AnkiCardSchedule(
          state: AnkiCardState.newCard,
          easeFactor: 2.5,
          intervalDays: 0,
          repetitions: 0,
          lapses: 0,
        ),
    clozeSource: clozeSource,
    clozeNumber: clozeNumber,
    distractors: distractors,
    media: media,
  );

  AnkiImportedPackage package(
    List<AnkiImportedCard> cards, {
    String deck = 'Historia::Roma',
  }) => AnkiImportedPackage(
    decks: [AnkiImportedDeck(id: 1, path: deck, cards: cards)],
    reviews: const [],
    packageMediaFiles: 0,
    collectionCreatedAt: DateTime(2020),
    sourceFile: 'collection.anki21',
  );

  AnkiImportPlan plan(
    AnkiImportedPackage p, {
    AnkiImportDestination destination = AnkiImportDestination.perDeck,
    Set<int> already = const {},
  }) => planAnkiImport(
    p,
    destination: destination,
    alreadyImported: already,
    now: now,
  );

  AnkiPlannedCard single(AnkiImportPlan plan) => plan.items.single.cards.single;

  group('el calendario pasa a SM-2', () {
    test('una nueva queda sin repasos y lista para hoy', () {
      final planned = single(plan(package([card()])));

      expect(planned.dueAt, now);
      expect(planned.repetitions, 0);
      expect(planned.intervalDays, 0);
      expect(planned.learningStep, isNull);
      expect(planned.lastReviewedAt, isNull);
      expect(planned.suspended, isFalse);
      expect(planned.buriedUntil, isNull);
    });

    test('una de repaso conserva intervalo, facilidad y repeticiones', () {
      final planned = single(
        plan(
          package([
            card(
              schedule: AnkiCardSchedule(
                state: AnkiCardState.review,
                easeFactor: 2.36,
                intervalDays: 45,
                repetitions: 6,
                lapses: 2,
                dueAt: DateTime(2026, 10, 20, 4),
                lastReviewedAt: DateTime(2026, 9, 5, 9),
              ),
            ),
          ]),
        ),
      );

      expect(planned.easeFactor, 2.36);
      expect(planned.intervalDays, 45);
      expect(planned.repetitions, 6);
      expect(planned.dueAt, DateTime(2026, 10, 20, 4));
      expect(planned.lastReviewedAt, DateTime(2026, 9, 5, 9));
      expect(planned.learningStep, isNull);
    });

    test('un repaso por días no cae antes de las 4:00 de su día', () {
      // Una colección de Sinapsis cuenta los días desde la medianoche.
      final planned = single(
        plan(
          package([
            card(
              schedule: AnkiCardSchedule(
                state: AnkiCardState.review,
                easeFactor: 2.5,
                intervalDays: 3,
                repetitions: 2,
                lapses: 0,
                dueAt: DateTime(2026, 10, 12),
              ),
            ),
          ]),
        ),
      );

      expect(planned.dueAt, DateTime(2026, 10, 12, 4));
    });

    test('lo que se aprende conserva el paso y la hora a la que vuelve', () {
      AnkiPlannedCard learning(int stepsLeft) => single(
        plan(
          package([
            card(
              schedule: AnkiCardSchedule(
                state: AnkiCardState.learning,
                easeFactor: 2.5,
                intervalDays: 0,
                repetitions: 1,
                lapses: 0,
                dueAt: DateTime(2026, 10, 8, 10, 40),
                learningStepsLeft: stepsLeft,
              ),
            ),
          ]),
        ),
      );

      expect(learning(2).learningStep, 0);
      expect(learning(1).learningStep, 1);
      expect(learning(0).learningStep, 0);
      expect(learning(3).learningStep, 0, reason: 'más pasos de los que hay');
      final planned = learning(1);
      expect(planned.dueAt, DateTime(2026, 10, 8, 10, 40));
      expect(planned.intervalDays, 0);
      expect(planned.repetitions, 1);
    });

    test('una que se olvidó se reaprende con su intervalo', () {
      final planned = single(
        plan(
          package([
            card(
              schedule: AnkiCardSchedule(
                state: AnkiCardState.relearning,
                easeFactor: 2.1,
                intervalDays: 0,
                repetitions: 4,
                lapses: 1,
                dueAt: DateTime(2026, 10, 8, 10, 45),
                learningStepsLeft: 1,
              ),
            ),
          ]),
        ),
      );

      expect(planned.learningStep, 0);
      expect(
        planned.intervalDays,
        1,
        reason: 'reaprender exige intervalo >= 1',
      );
      expect(planned.easeFactor, 2.1);
      expect(planned.dueAt, DateTime(2026, 10, 8, 10, 45));
    });

    test('pausada sigue pausada y pospuesta lo está hasta mañana', () {
      const base = AnkiCardSchedule(
        state: AnkiCardState.review,
        easeFactor: 2.5,
        intervalDays: 10,
        repetitions: 3,
        lapses: 0,
      );
      final paused = single(
        plan(
          package([
            card(
              schedule: const AnkiCardSchedule(
                state: AnkiCardState.review,
                easeFactor: 2.5,
                intervalDays: 10,
                repetitions: 3,
                lapses: 0,
                suspended: true,
              ),
            ),
          ]),
        ),
      );
      final buried = single(
        plan(
          package([
            card(
              schedule: const AnkiCardSchedule(
                state: AnkiCardState.review,
                easeFactor: 2.5,
                intervalDays: 10,
                repetitions: 3,
                lapses: 0,
                postponed: true,
              ),
            ),
          ]),
        ),
      );
      final plain = single(plan(package([card(schedule: base)])));

      expect(paused.suspended, isTrue);
      expect(paused.buriedUntil, isNull);
      expect(buried.suspended, isFalse);
      expect(buried.buriedUntil, DateTime(2026, 10, 9, 4));
      expect(plain.suspended, isFalse);
      expect(plain.buriedUntil, isNull);
    });
  });

  group('la forma de cada tarjeta', () {
    test('básica y de escribir conservan frente y dorso', () {
      final planned = plan(
        package([
          card(front: 'Capital', back: 'Roma'),
          card(
            id: 2,
            noteId: 2,
            guid: 'g2',
            kind: AnkiCardKind.typed,
            front: 'Año',
            back: '476',
          ),
        ]),
      ).items.single.cards;

      expect(planned[0].kind, FlashcardKind.freeRecall);
      expect(planned[0].front, 'Capital');
      expect(planned[0].back, 'Roma');
      expect(planned[1].kind, FlashcardKind.typedAnswer);
      expect(planned[1].back, '476');
    });

    test('las dos direcciones de una nota son hermanas', () {
      final planned = plan(
        package([
          card(kind: AnkiCardKind.reversed, front: 'A', back: 'B'),
          card(
            id: 2,
            ord: 1,
            kind: AnkiCardKind.reversed,
            front: 'B',
            back: 'A',
          ),
        ]),
      ).items.single.cards;

      expect(planned[0].groupId, ankiImportedGroupId('g1'));
      expect(planned[1].groupId, planned[0].groupId);
      expect(planned[0].id, isNot(planned[1].id));
    });

    test('una básica sin hermanas no tiene grupo', () {
      expect(single(plan(package([card()]))).groupId, isNull);
    });

    test('los huecos guardan el texto entero, el número y solo el extra', () {
      const source = 'El {{c1::Imperio}} cayó en {{c2::476}}';
      final planned = plan(
        package([
          card(
            kind: AnkiCardKind.cloze,
            front: 'El [...] cayó en 476',
            back: 'El **Imperio** cayó en 476\n\nOccidente',
            clozeSource: source,
            clozeNumber: 1,
          ),
          card(
            id: 2,
            ord: 1,
            kind: AnkiCardKind.cloze,
            front: 'El Imperio cayó en [...]',
            back: 'El Imperio cayó en **476**',
            clozeSource: source,
            clozeNumber: 2,
          ),
        ]),
      ).items.single.cards;

      expect(planned[0].kind, FlashcardKind.cloze);
      expect(planned[0].front, source);
      expect(planned[0].clozeIndex, 1);
      expect(planned[0].back, 'Occidente');
      expect(planned[1].clozeIndex, 2);
      expect(planned[1].back, isEmpty);
      expect(planned[0].groupId, isNotNull);
      expect(planned[0].groupId, planned[1].groupId);
    });

    test('un solo hueco no forma grupo', () {
      final planned = single(
        plan(
          package([
            card(
              kind: AnkiCardKind.cloze,
              front: 'Roma cayó en [...]',
              back: 'Roma cayó en **476**',
              clozeSource: 'Roma cayó en {{c1::476}}',
              clozeNumber: 1,
            ),
          ]),
        ),
      );
      expect(planned.groupId, isNull);
    });

    test('opción múltiple conserva la correcta y los distractores', () {
      final planned = single(
        plan(
          package([
            card(
              kind: AnkiCardKind.multipleChoice,
              front: '¿Capital?',
              back: 'Roma',
              distractors: const ['Milán', 'Turín'],
            ),
          ]),
        ),
      );

      expect(planned.kind, FlashcardKind.multipleChoice);
      expect(planned.back, 'Roma');
      expect(planned.choiceDistractors, ['Milán', 'Turín']);
    });

    test('opción múltiple sin distractores es pregunta y respuesta', () {
      final planned = single(
        plan(package([card(kind: AnkiCardKind.multipleChoice)])),
      );
      expect(planned.kind, FlashcardKind.freeRecall);
    });

    test('un lado que era solo un archivo dice qué faltó', () {
      final planned = single(
        plan(
          package([
            card(
              front: '',
              back: 'Roma',
              media: const [AnkiMediaRef('mapa.png', AnkiMediaKind.image)],
            ),
          ]),
        ),
      );
      expect(planned.front, '[imagen]');
      expect(planned.back, 'Roma');
    });

    test('una sin nada que mostrar no se trae y se cuenta', () {
      final result = plan(package([card(front: '', back: '')]));
      expect(result.items, isEmpty);
      expect(result.unusable, 1);
    });

    test('la fecha de creación sale del id de Anki si es creíble', () {
      final plausible = DateTime(2024, 3, 5, 12);
      final fromId = single(
        plan(package([card(id: plausible.millisecondsSinceEpoch)])),
      );
      final nonsense = single(plan(package([card(id: 5)])));
      final future = single(
        plan(package([card(id: DateTime(2030).millisecondsSinceEpoch)])),
      );

      expect(fromId.createdAt, plausible);
      expect(nonsense.createdAt, now);
      expect(future.createdAt, now);
    });
  });

  group('dónde caen', () {
    test('un elemento por mazo, con sus niveles de etiqueta', () {
      final result = plan(package([card()]));

      final item = result.items.single;
      expect(item.title, 'Historia › Roma');
      expect(item.tags, [kAnkiImportedName, 'Historia', 'Roma']);
      expect(item.id, ankiImportedItemId('Historia::Roma'));
      expect(item.cards.single.itemId, item.id);
    });

    test(
      'el mazo raíz que agrega Sinapsis al exportar no queda de etiqueta',
      () {
        final item = plan(
          package([card()], deck: 'Sinapsis::Historia::Roma'),
        ).items.single;
        expect(item.title, 'Historia › Roma');
        expect(item.tags, [kAnkiImportedName, 'Historia', 'Roma']);
      },
    );

    test('«Sin tema» no es un tema', () {
      final item = plan(
        package([card()], deck: 'Sinapsis::Sin tema'),
      ).items.single;
      expect(item.title, kAnkiImportedName);
      expect(item.tags, [kAnkiImportedName]);
    });

    test('todo en un solo elemento junta los mazos', () {
      final two = AnkiImportedPackage(
        decks: [
          AnkiImportedDeck(id: 1, path: 'A', cards: [card()]),
          AnkiImportedDeck(
            id: 2,
            path: 'B::C',
            cards: [card(id: 2, noteId: 2, guid: 'g2')],
          ),
        ],
        reviews: const [],
        packageMediaFiles: 0,
        collectionCreatedAt: DateTime(2020),
        sourceFile: 'collection.anki21',
      );

      final perDeck = plan(two);
      final single = plan(two, destination: AnkiImportDestination.singleItem);

      expect(perDeck.items.map((i) => i.title), ['A', 'B › C']);
      expect(single.items, hasLength(1));
      expect(single.items.single.title, kAnkiImportedName);
      expect(single.items.single.cards, hasLength(2));
      expect(single.items.single.id, ankiImportedItemId(''));
    });
  });

  group('sin duplicar', () {
    test('las que ya están no se vuelven a traer, y se cuentan', () {
      final result = plan(
        package([card(id: 10, guid: 'a'), card(id: 11, noteId: 2, guid: 'b')]),
        already: {10},
      );

      expect(result.items.single.cards, hasLength(1));
      expect(result.alreadyImported, 1);
    });

    test('todas ya importadas no deja ningún elemento', () {
      final result = plan(package([card(id: 10)]), already: {10});
      expect(result.items, isEmpty);
      expect(result.alreadyImported, 1);
    });

    test('la misma nota y plantilla dos veces en el paquete cuenta una', () {
      final result = plan(
        package([card(id: 10, guid: 'a'), card(id: 11, guid: 'a')]),
      );
      expect(result.items.single.cards, hasLength(1));
      expect(result.alreadyImported, 1);
    });

    test('los ids son los mismos en cada importación', () {
      final first = single(plan(package([card(guid: 'xyz', ord: 2)])));
      final second = single(plan(package([card(guid: 'xyz', ord: 2)])));
      final other = single(plan(package([card(guid: 'xyz', ord: 3)])));

      expect(first.id, second.id);
      expect(first.id, ankiImportedCardIdOf('xyz', 2));
      expect(other.id, isNot(first.id));
    });

    test('si una hermana ya está, la otra igual se une al mismo grupo', () {
      final cards = [
        card(id: 10, kind: AnkiCardKind.reversed, front: 'A', back: 'B'),
        card(
          id: 11,
          ord: 1,
          kind: AnkiCardKind.reversed,
          front: 'B',
          back: 'A',
        ),
      ];
      final result = plan(package(cards), already: {10});

      expect(result.items.single.cards, hasLength(1));
      expect(single(result).groupId, ankiImportedGroupId('g1'));
    });
  });
}
