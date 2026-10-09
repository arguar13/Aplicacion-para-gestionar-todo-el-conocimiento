import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/anki_import/data/repositories/anki_import_repository_impl.dart';
import 'package:sinapsis/features/anki_import/data/services/sqlite_anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/repositories/anki_import_repository.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_ids.dart';
import 'package:sinapsis/features/anki_import/domain/usecases/import_anki_package_usecase.dart';
import 'package:sinapsis/features/export/data/services/anki_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

import '../../../../support/anki_package_fixture.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// Traer un `.apkg` a la bóveda (F31, decisión 73): de ida y vuelta con lo que
/// exporta Sinapsis, sin duplicar al reimportar, atómico, y con el calendario
/// intacto.
void main() {
  const builder = AnkiPackageBuilder();
  const reader = SqliteAnkiPackageReader();
  // Mediodía del jueves 8 de octubre de 2026.
  final now = DateTime(2026, 10, 8, 12);
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    // Guardar una nota deja en marcha, sin esperar, la búsqueda de duplicados:
    // que termine antes de cerrar la base.
    addTearDown(pumpEventQueue);
  });

  AppDatabase db() => harness.database;

  ImportAnkiPackageUseCase useCase([AnkiImportRepository? repository]) =>
      ImportAnkiPackageUseCase(
        repository:
            repository ??
            AnkiImportRepositoryImpl(database: db(), ids: FakeIdGenerator()),
        library: harness.container.read(libraryRepositoryProvider),
        organize: harness.container.read(organizeRepositoryProvider),
        ids: FakeIdGenerator(prefix: 'imp'),
        clock: () => now,
      );

  Flashcard card(
    String id, {
    String front = 'P',
    String back = 'R',
    FlashcardKind kind = FlashcardKind.freeRecall,
    int intervalDays = 0,
    int repetitions = 0,
    double easeFactor = 2.5,
    DateTime? dueAt,
    int? learningStep,
    bool suspended = false,
    String? groupId,
    int? clozeIndex,
    DateTime? lastReviewedAt,
  }) => Flashcard(
    id: id,
    itemId: 'item-1',
    front: front,
    back: back,
    dueAt: dueAt ?? now,
    createdAt: DateTime(2026, 3, 1, 9),
    kind: kind,
    intervalDays: intervalDays,
    repetitions: repetitions,
    easeFactor: easeFactor,
    learningStep: learningStep,
    suspended: suspended,
    groupId: groupId,
    clozeIndex: clozeIndex,
    lastReviewedAt: lastReviewedAt,
  );

  AnkiCardExport export(
    Flashcard card, {
    String deck = 'Sinapsis::Historia::Roma',
    String? answer,
    List<String> distractors = const [],
  }) => AnkiCardExport(
    card: card,
    deckPath: deck,
    answer: answer ?? card.back,
    distractors: distractors,
  );

  Future<AnkiImportedPackage> roundTrip(List<AnkiCardExport> cards) async =>
      reader.readBytes(await builder.build(cards));

  // Lo que Sinapsis exporta, en todas sus etapas y formas.
  final today = DateTime.now();
  final inTwelveDays = DateTime(today.year, today.month, today.day + 12, 15);
  final inTenMinutes = DateTime.now().add(const Duration(minutes: 10));
  final originals = <Flashcard>[
    card('c-nueva', front: '¿Capital de Italia?', back: 'Roma'),
    card(
      'c-repaso',
      front: '¿Caída de Roma de Occidente?',
      back: '476',
      intervalDays: 45,
      repetitions: 6,
      easeFactor: 2.36,
      dueAt: inTwelveDays,
    ),
    card(
      'c-aprende',
      front: 'Fundador de Roma',
      back: 'Rómulo',
      repetitions: 1,
      learningStep: 1,
      dueAt: inTenMinutes,
    ),
    card(
      'c-reaprende',
      front: 'Primer emperador',
      back: 'Augusto',
      intervalDays: 3,
      repetitions: 4,
      easeFactor: 2.1,
      learningStep: 0,
      dueAt: inTenMinutes,
    ),
    card(
      'c-pausada',
      front: 'Dato pausado',
      back: 'X',
      intervalDays: 10,
      repetitions: 3,
      dueAt: inTwelveDays,
      suspended: true,
    ),
    card(
      'c-hueco-1',
      front: 'El {{c1::Imperio}} cayó en {{c2::476}}',
      back: 'Occidente',
      kind: FlashcardKind.cloze,
      groupId: 'grupo',
      clozeIndex: 1,
      intervalDays: 8,
      repetitions: 2,
      dueAt: inTwelveDays,
    ),
    card(
      'c-hueco-2',
      front: 'El {{c1::Imperio}} cayó en {{c2::476}}',
      back: 'Occidente',
      kind: FlashcardKind.cloze,
      groupId: 'grupo',
      clozeIndex: 2,
    ),
    card(
      'c-escribir',
      front: '¿Otro nombre de Roma?',
      back: 'La Urbe\nCaput Mundi',
      kind: FlashcardKind.typedAnswer,
    ),
    card(
      'c-opcion',
      front: '¿Capital de Francia?',
      back: '',
      kind: FlashcardKind.multipleChoice,
    ),
    card(
      'c-vf',
      front: 'Roma se fundó en 753 a. C.',
      back: 'Verdadero',
      kind: FlashcardKind.trueFalse,
    ),
  ];

  List<AnkiCardExport> exports() => [
    for (final original in originals)
      export(
        original,
        deck: original.id == 'c-nueva' || original.id == 'c-vf'
            ? 'Sinapsis::Sin tema'
            : 'Sinapsis::Historia::Roma',
        answer: original.id == 'c-opcion' ? 'París' : null,
        distractors: original.id == 'c-opcion'
            ? const ['Lyon', 'Niza']
            : const [],
      ),
  ];

  Future<List<FlashcardRow>> rows() => (db().select(
    db().flashcards,
  )..orderBy([(f) => OrderingTerm(expression: f.front)])).get();

  FlashcardRow byFront(List<FlashcardRow> all, String front) =>
      all.singleWhere((r) => r.front == front, orElse: () => fail(front));

  DateTime seconds(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    (t.millisecondsSinceEpoch ~/ 1000) * 1000,
  );

  group('de ida y vuelta con lo que exporta Sinapsis', () {
    test(
      'las mismas tarjetas con el mismo calendario en una base limpia',
      () async {
        final package = await roundTrip(exports());
        final result = await useCase().import(
          package,
          destination: AnkiImportDestination.perDeck,
        );

        final report = result.getRight().toNullable()!;
        expect(report.cardsImported, originals.length);
        expect(report.alreadyImported, 0);
        expect(report.unusable, 0);
        final all = await rows();
        expect(all, hasLength(originals.length));

        // Nueva: sin repasos, para hoy.
        final fresh = byFront(all, '¿Capital de Italia?');
        expect(fresh.back, 'Roma');
        expect(fresh.kind, FlashcardKind.freeRecall);
        expect(fresh.repetitions, 0);
        expect(fresh.intervalDays, 0);
        expect(fresh.learningStep, isNull);
        expect(fresh.dueAt, seconds(now));

        // Repaso: intervalo, facilidad, repeticiones, y el mismo día.
        final review = byFront(all, '¿Caída de Roma de Occidente?');
        expect(review.back, '476');
        expect(review.intervalDays, 45);
        expect(review.repetitions, 6);
        expect(review.easeFactor, 2.36);
        expect(review.learningStep, isNull);
        expect(
          DateTime(review.dueAt.year, review.dueAt.month, review.dueAt.day),
          DateTime(inTwelveDays.year, inTwelveDays.month, inTwelveDays.day),
        );

        // Aprendiendo: el paso en que iba y la hora a la que vuelve.
        final learning = byFront(all, 'Fundador de Roma');
        expect(learning.learningStep, 1);
        expect(learning.intervalDays, 0);
        expect(learning.repetitions, 1);
        expect(learning.dueAt, seconds(inTenMinutes));

        // Reaprendiendo tras olvidarla.
        final relearning = byFront(all, 'Primer emperador');
        expect(relearning.learningStep, 0);
        expect(relearning.intervalDays, 3);
        expect(relearning.easeFactor, 2.1);
        expect(relearning.dueAt, seconds(inTenMinutes));

        // La etapa que deduce Sinapsis de los campos coincide con la original.
        for (final entry in {
          'c-nueva': '¿Capital de Italia?',
          'c-repaso': '¿Caída de Roma de Occidente?',
          'c-aprende': 'Fundador de Roma',
          'c-reaprende': 'Primer emperador',
        }.entries) {
          final original = originals.singleWhere((c) => c.id == entry.key);
          final imported = byFront(all, entry.value);
          final phase = Flashcard(
            id: imported.id,
            itemId: imported.itemId,
            front: imported.front,
            back: imported.back,
            dueAt: imported.dueAt,
            createdAt: imported.createdAt,
            intervalDays: imported.intervalDays,
            repetitions: imported.repetitions,
            learningStep: imported.learningStep,
            lastReviewedAt: imported.lastReviewedAt,
          ).phase;
          expect(phase, original.phase, reason: entry.key);
        }
        expect(originals.map((c) => c.phase).toSet(), {
          CardPhase.newCard,
          CardPhase.review,
          CardPhase.learning,
          CardPhase.relearning,
        });

        // Pausada.
        expect(byFront(all, 'Dato pausado').suspended, isTrue);
        expect(byFront(all, '¿Capital de Italia?').suspended, isFalse);

        // Huecos: el texto entero, el número, el complemento y el grupo.
        final holes = all.where((r) => r.kind == FlashcardKind.cloze).toList()
          ..sort((a, b) => a.clozeIndex!.compareTo(b.clozeIndex!));
        expect(holes, hasLength(2));
        expect(holes.map((r) => r.clozeIndex), [1, 2]);
        expect(
          holes.every(
            (r) => r.front == 'El {{c1::Imperio}} cayó en {{c2::476}}',
          ),
          isTrue,
        );
        expect(holes.every((r) => r.back == 'Occidente'), isTrue);
        expect(holes[0].groupId, isNotNull);
        expect(holes[0].groupId, holes[1].groupId);
        expect(holes[0].intervalDays, 8);
        expect(holes[1].repetitions, 0);

        // Escribir la respuesta: con sus alternativas.
        final typed = byFront(all, '¿Otro nombre de Roma?');
        expect(typed.kind, FlashcardKind.typedAnswer);
        expect(typed.back, 'La Urbe\nCaput Mundi');

        // Opción múltiple: sus opciones reales, sin degradarse.
        final choice = byFront(all, '¿Capital de Francia?');
        expect(choice.kind, FlashcardKind.multipleChoice);
        final options =
            await (db().select(db().flashcardOptions)
                  ..where((o) => o.flashcardId.equals(choice.id))
                  ..orderBy([(o) => OrderingTerm(expression: o.position)]))
                .get();
        expect(options.map((o) => o.content), ['París', 'Lyon', 'Niza']);
        expect(options.map((o) => o.isCorrect), [true, false, false]);

        // Verdadero o falso viaja como pregunta y respuesta.
        expect(
          byFront(all, 'Roma se fundó en 753 a. C.').kind,
          FlashcardKind.freeRecall,
        );
      },
    );

    test('cada mazo es un elemento con su nombre y sus etiquetas', () async {
      final package = await roundTrip(exports());
      await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getOrElse((f) => fail('$f'));
      expect(items.map((i) => i.title).toSet(), {
        'Historia › Roma',
        kAnkiImportedName,
      });
      final roma = items.singleWhere((i) => i.title == 'Historia › Roma');
      expect(roma.id, ankiImportedItemId('Sinapsis::Historia::Roma'));
      expect(roma.tags.map((t) => t.name).toSet(), {
        kAnkiImportedName,
        'Historia',
        'Roma',
      });
      final withoutTopic = items.singleWhere(
        (i) => i.title == kAnkiImportedName,
      );
      expect(withoutTopic.tags.map((t) => t.name), [kAnkiImportedName]);
      // Sus tarjetas cuelgan del elemento.
      final cards = await rows();
      expect(
        cards.where((c) => c.itemId == roma.id),
        hasLength(originals.length - 2),
      );
    });

    test('todo en un solo elemento «Importado de Anki»', () async {
      final package = await roundTrip(exports());
      await useCase().import(
        package,
        destination: AnkiImportDestination.singleItem,
      );

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getOrElse((f) => fail('$f'));
      expect(items.map((i) => i.title), [kAnkiImportedName]);
      expect((await rows()).every((r) => r.itemId == items.single.id), isTrue);
    });
  });

  group('sin duplicar', () {
    test('reimportar el mismo paquete no suma ni una tarjeta', () async {
      final package = await roundTrip(exports());
      final first = await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );
      final before = await rows();
      final beforeItems = await db().select(db().knowledgeEntries).get();

      final second = await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );

      final report = second.getRight().toNullable()!;
      expect(first.getRight().toNullable()!.cardsImported, originals.length);
      expect(report.cardsImported, 0);
      expect(report.itemsCreated, 0);
      expect(report.alreadyImported, originals.length);
      expect(await rows(), hasLength(before.length));
      expect(
        await db().select(db().knowledgeEntries).get(),
        hasLength(beforeItems.length),
      );
      expect(
        await db().select(db().flashcardOptions).get(),
        hasLength(3),
        reason: 'las opciones de la múltiple tampoco se repiten',
      );
    });

    test('lo repasado entre una importación y otra no se pisa', () async {
      final package = await roundTrip(exports());
      await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );
      final imported = byFront(await rows(), '¿Caída de Roma de Occidente?');
      await (db().update(
        db().flashcards,
      )..where((f) => f.id.equals(imported.id))).write(
        const FlashcardsCompanion(
          intervalDays: Value(99),
          repetitions: Value(9),
        ),
      );

      await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );

      final after = byFront(await rows(), '¿Caída de Roma de Occidente?');
      expect(after.intervalDays, 99);
      expect(after.repetitions, 9);
    });

    test('un paquete con una tarjeta más trae solo la nueva', () async {
      final first = await roundTrip(exports().take(3).toList());
      await useCase().import(first, destination: AnkiImportDestination.perDeck);

      final second = await roundTrip(exports().take(4).toList());
      final result = await useCase().import(
        second,
        destination: AnkiImportDestination.perDeck,
      );

      final report = result.getRight().toNullable()!;
      expect(report.cardsImported, 1);
      expect(report.alreadyImported, 3);
      expect(await rows(), hasLength(4));
    });

    test('traer lo que esta misma bóveda exportó no lo duplica', () async {
      await insertItemRows(db(), id: 'item-1', title: 'Roma');
      for (final original in originals) {
        await db()
            .into(db().flashcards)
            .insert(
              FlashcardsCompanion.insert(
                id: original.id,
                itemId: 'item-1',
                front: original.front,
                back: original.back,
                dueAt: original.dueAt,
                createdAt: original.createdAt,
                kind: Value(original.kind),
                clozeIndex: Value(original.clozeIndex),
                groupId: Value(original.groupId),
              ),
            );
      }
      final package = await roundTrip(exports());

      final preview = await useCase().preview(package);
      final result = await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );

      expect(preview.alreadyImported, originals.length);
      expect(preview.toImport, 0);
      final report = result.getRight().toNullable()!;
      expect(report.cardsImported, 0);
      expect(report.alreadyImported, originals.length);
      expect(await rows(), hasLength(originals.length));
    });

    test(
      'un elemento en la papelera vuelve cuando se trae algo nuevo',
      () async {
        final first = await roundTrip(exports().take(1).toList());
        await useCase().import(
          first,
          destination: AnkiImportDestination.perDeck,
        );
        final library = harness.container.read(libraryRepositoryProvider);
        final itemId = (await rows()).single.itemId;
        await library.delete(itemId);
        expect(
          (await library.findById(itemId)).getRight().toNullable(),
          isNull,
        );

        final second = await roundTrip([
          for (final e in exports())
            if (e.card.id == 'c-nueva' || e.card.id == 'c-vf') e,
        ]);
        await useCase().import(
          second,
          destination: AnkiImportDestination.perDeck,
        );

        expect(
          (await library.findById(itemId)).getRight().toNullable(),
          isNotNull,
        );
      },
    );
  });

  group('atómica', () {
    test('si falla a mitad no queda ni un elemento, ni una etiqueta, ni '
        'una tarjeta', () async {
      final package = await roundTrip(exports());
      expect(package.decks, hasLength(2));
      final failing = _FailingOnSecondInsert(
        AnkiImportRepositoryImpl(database: db(), ids: FakeIdGenerator()),
      );

      final result = await useCase(
        failing,
      ).import(package, destination: AnkiImportDestination.perDeck);

      expect(result.isLeft(), isTrue);
      expect(failing.insertCalls, 2);
      expect(await rows(), isEmpty);
      expect(await db().select(db().flashcardOptions).get(), isEmpty);
      expect(await db().select(db().knowledgeEntries).get(), isEmpty);
      final tags = await harness.container
          .read(organizeRepositoryProvider)
          .watchAllTags()
          .first;
      expect(tags, isEmpty);
    });

    test('después de un fallo, intentarlo de nuevo trae todo', () async {
      final package = await roundTrip(exports());
      await useCase(
        _FailingOnSecondInsert(
          AnkiImportRepositoryImpl(database: db(), ids: FakeIdGenerator()),
        ),
      ).import(package, destination: AnkiImportDestination.perDeck);

      final result = await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );

      expect(result.getRight().toNullable()!.cardsImported, originals.length);
    });
  });

  test('avisa el avance tarjeta a tarjeta, hasta el total', () async {
    final package = await roundTrip(exports());
    final steps = <(int, int)>[];

    await useCase().import(
      package,
      destination: AnkiImportDestination.perDeck,
      onProgress: (done, total) => steps.add((done, total)),
    );

    expect(steps.first, (0, originals.length));
    expect(steps.last, (originals.length, originals.length));
    expect(
      steps.map((s) => s.$1),
      orderedEquals(steps.map((s) => s.$1).toList()..sort()),
    );
  });

  group('lo que trae Anki de verdad (paquete armado a mano)', () {
    // 1 de enero de 2026 a las 4:00, como el `crt` de Anki; el repaso vence
    // el día 280 (8 de octubre).
    final crt = DateTime(2026, 1, 1, 4).millisecondsSinceEpoch ~/ 1000;
    final learningDue =
        DateTime(2026, 10, 8, 12, 10).millisecondsSinceEpoch ~/ 1000;

    Future<AnkiImportedPackage> handmade() async {
      final collection = collectionBytes(
        crt: crt,
        models: [basicModel(10)],
        decks: [deck(1, 'Default'), deck(2, 'Historia::Roma')],
        notes: [
          for (var i = 1; i <= 8; i++)
            FixtureNote(
              id: 100 + i,
              modelId: 10,
              fields: ['Pregunta $i', 'Respuesta $i'],
              guid: 'guid$i',
            ),
        ],
        cards: [
          const FixtureCard(id: 1700000001001, noteId: 101, due: 7),
          const FixtureCard(
            id: 1700000001002,
            noteId: 102,
            deckId: 2,
            type: 2,
            queue: 2,
            due: 280,
            ivl: 30,
            factor: 2500,
            reps: 5,
          ),
          FixtureCard(
            id: 1700000001003,
            noteId: 103,
            deckId: 2,
            type: 1,
            queue: 1,
            due: learningDue,
            reps: 1,
            left: 2002,
          ),
          FixtureCard(
            id: 1700000001004,
            noteId: 104,
            deckId: 2,
            type: 1,
            queue: 1,
            due: learningDue,
            reps: 1,
            left: 1001,
          ),
          const FixtureCard(
            id: 1700000001005,
            noteId: 105,
            deckId: 2,
            type: 2,
            queue: -1,
            due: 300,
            ivl: 12,
            factor: 2300,
            reps: 3,
          ),
          const FixtureCard(
            id: 1700000001006,
            noteId: 106,
            deckId: 2,
            type: 2,
            queue: -2,
            due: 290,
            ivl: 20,
            factor: 2500,
            reps: 4,
          ),
          const FixtureCard(
            id: 1700000001007,
            noteId: 107,
            deckId: 2,
            type: 2,
            queue: -3,
            due: 291,
            ivl: 21,
            factor: 2500,
            reps: 4,
          ),
          const FixtureCard(
            id: 1700000001008,
            noteId: 108,
            deckId: 2,
            type: 3,
            queue: 1,
            due: 0,
            ivl: 7,
            factor: 1900,
            reps: 8,
            lapses: 2,
          ),
        ],
      );
      return reader.readBytes(apkgOf(collection));
    }

    test('la vista previa cuenta etapas, pausadas y pospuestas', () async {
      final package = await handmade();
      final preview = await useCase().preview(package);

      expect(preview.deckCount, 2);
      expect(preview.cardCount, 8);
      expect(preview.kinds.basic, 8);
      expect(preview.newCards, 1);
      expect(preview.learningCards, 3);
      expect(preview.reviewCards, 4);
      expect(preview.suspendedCards, 1);
      expect(preview.postponedCards, 2);
      expect(preview.alreadyImported, 0);
      expect(preview.toImport, 8);
      expect(preview.hasUnimportedMedia, isFalse);
    });

    test(
      'el paso de aprendizaje, lo pausado y lo pospuesto se conservan',
      () async {
        final package = await handmade();
        await useCase().import(
          package,
          destination: AnkiImportDestination.perDeck,
        );
        final all = await rows();

        expect(byFront(all, 'Pregunta 3').learningStep, 0);
        expect(byFront(all, 'Pregunta 4').learningStep, 1);
        expect(byFront(all, 'Pregunta 3').dueAt, DateTime(2026, 10, 8, 12, 10));
        expect(byFront(all, 'Pregunta 8').learningStep, 0);
        expect(byFront(all, 'Pregunta 8').intervalDays, 7);

        final review = byFront(all, 'Pregunta 2');
        expect(review.dueAt, DateTime(2026, 10, 8, 4));
        expect(review.intervalDays, 30);
        expect(review.easeFactor, 2.5);

        final paused = byFront(all, 'Pregunta 5');
        expect(paused.suspended, isTrue);
        expect(paused.easeFactor, 2.3);
        expect(paused.buriedUntil, isNull);

        for (final front in ['Pregunta 6', 'Pregunta 7']) {
          final buried = byFront(all, front);
          expect(buried.suspended, isFalse);
          expect(buried.buriedUntil, DateTime(2026, 10, 9, 4));
        }
      },
    );

    test('la fecha de creación sale del id de la tarjeta', () async {
      final package = await handmade();
      await useCase().import(
        package,
        destination: AnkiImportDestination.perDeck,
      );

      expect(
        byFront(await rows(), 'Pregunta 1').createdAt,
        seconds(DateTime.fromMillisecondsSinceEpoch(1700000001001)),
      );
    });
  });
}

/// Un repositorio de importación que falla en la segunda escritura de tarjetas:
/// cuando ya se escribió el primer elemento con las suyas.
class _FailingOnSecondInsert implements AnkiImportRepository {
  _FailingOnSecondInsert(this._inner);

  final AnkiImportRepository _inner;
  int insertCalls = 0;

  @override
  Future<Set<int>> alreadyImported(List<AnkiImportedCard> cards) =>
      _inner.alreadyImported(cards);

  @override
  Future<Map<String, bool>> existingItems(List<String> itemIds) =>
      _inner.existingItems(itemIds);

  @override
  Future<int> insertCards(List<AnkiPlannedCard> cards) async {
    insertCalls++;
    if (insertCalls == 2) throw StateError('se cortó el disco');
    return _inner.insertCards(cards);
  }
}
