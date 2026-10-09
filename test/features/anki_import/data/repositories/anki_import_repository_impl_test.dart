import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/anki_import/data/repositories/anki_import_repository_impl.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_ids.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

/// Lo que la importación de Anki le pregunta y le escribe a la base (F31,
/// decisión 73), con SQLite de verdad.
void main() {
  late AppDatabase db;
  late AnkiImportRepositoryImpl repository;
  final at = DateTime(2026, 10, 8, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = AnkiImportRepositoryImpl(database: db, ids: FakeIdGenerator());
    await insertItemRows(db, id: 'item', title: 'Mazo');
  });

  tearDown(() => db.close());

  AnkiPlannedCard planned(
    String id, {
    FlashcardKind kind = FlashcardKind.freeRecall,
    String back = 'R',
    List<String> distractors = const [],
    int interval = 0,
  }) => AnkiPlannedCard(
    id: id,
    itemId: 'item',
    kind: kind,
    front: 'P $id',
    back: back,
    createdAt: at,
    dueAt: at,
    easeFactor: 2.5,
    intervalDays: interval,
    repetitions: 0,
    choiceDistractors: distractors,
  );

  AnkiImportedCard imported({
    required String guid,
    int ankiId = 1,
    int ord = 0,
    AnkiCardKind kind = AnkiCardKind.basic,
    int? clozeNumber,
  }) => AnkiImportedCard(
    ankiCardId: ankiId,
    noteId: ankiId,
    guid: guid,
    ord: ord,
    kind: kind,
    front: 'P',
    back: 'R',
    clozeNumber: clozeNumber,
    clozeSource: clozeNumber == null ? null : '{{c1::a}} {{c2::b}}',
    schedule: const AnkiCardSchedule(
      state: AnkiCardState.newCard,
      easeFactor: 2.5,
      intervalDays: 0,
      repetitions: 0,
      lapses: 0,
    ),
  );

  Future<void> seedCard(
    String id, {
    FlashcardKind kind = FlashcardKind.freeRecall,
    String? groupId,
    int? clozeIndex,
  }) => db
      .into(db.flashcards)
      .insert(
        FlashcardsCompanion.insert(
          id: id,
          itemId: 'item',
          front: 'P',
          back: 'R',
          dueAt: at,
          createdAt: at,
          kind: Value(kind),
          groupId: Value(groupId),
          clozeIndex: Value(clozeIndex),
        ),
      );

  group('insertCards', () {
    test('escribe las tarjetas con su calendario y devuelve cuántas', () async {
      final written = await repository.insertCards([
        planned('a', interval: 12),
        planned('b'),
      ]);

      expect(written, 2);
      final rows = await db.select(db.flashcards).get();
      expect(rows.map((r) => r.id).toSet(), {'a', 'b'});
      expect(rows.singleWhere((r) => r.id == 'a').intervalDays, 12);
    });

    test('una que ya existe se deja como está y no se cuenta', () async {
      await repository.insertCards([planned('a')]);
      await (db.update(db.flashcards)..where((f) => f.id.equals('a'))).write(
        const FlashcardsCompanion(intervalDays: Value(77)),
      );

      final written = await repository.insertCards([
        planned('a', interval: 5),
        planned('b'),
      ]);

      expect(written, 1);
      final rows = await db.select(db.flashcards).get();
      expect(rows, hasLength(2));
      expect(rows.singleWhere((r) => r.id == 'a').intervalDays, 77);
    });

    test(
      'opción múltiple: la respuesta va en las opciones, no en back',
      () async {
        await repository.insertCards([
          planned(
            'm',
            kind: FlashcardKind.multipleChoice,
            back: 'París',
            distractors: const ['Lyon', 'Niza'],
          ),
        ]);
        // Otra vez: las opciones no se repiten.
        await repository.insertCards([
          planned(
            'm',
            kind: FlashcardKind.multipleChoice,
            back: 'París',
            distractors: const ['Lyon', 'Niza'],
          ),
        ]);

        final card = await db.select(db.flashcards).getSingle();
        expect(card.back, isEmpty);
        final options = await db.select(db.flashcardOptions).get()
          ..sort((a, b) => a.position.compareTo(b.position));
        expect(options.map((o) => o.content), ['París', 'Lyon', 'Niza']);
        expect(options.map((o) => o.isCorrect), [true, false, false]);
      },
    );

    test('más tarjetas que una tanda se escriben todas', () async {
      final cards = [for (var i = 0; i < 1234; i++) planned('c$i')];

      expect(await repository.insertCards(cards), 1234);
      expect(await db.select(db.flashcards).get(), hasLength(1234));
    });
  });

  group('alreadyImported', () {
    test('reconoce lo que ya se trajo por su id determinista', () async {
      final card = imported(guid: 'abc', ankiId: 5);
      await seedCard(ankiImportedCardId(card));

      final present = await repository.alreadyImported([
        card,
        imported(guid: 'otra', ankiId: 6),
      ]);

      expect(present, {5});
    });

    test('la vuelta de una nota no se confunde con la ida', () async {
      await seedCard(ankiImportedCardIdOf('abc', 0));

      final present = await repository.alreadyImported([
        imported(guid: 'abc'),
        imported(guid: 'abc', ankiId: 2, ord: 1),
      ]);

      expect(present, {1});
    });

    test(
      'reconoce una tarjeta que Sinapsis exportó: su guid es su id',
      () async {
        await seedCard('mi-tarjeta');

        final present = await repository.alreadyImported([
          imported(guid: 'mi-tarjeta'),
          imported(guid: 'ajena', ankiId: 2),
        ]);

        expect(present, {1});
      },
    );

    test(
      'de un texto de huecos exportado, cubre los huecos de todo el grupo',
      () async {
        await seedCard(
          'hueco-1',
          kind: FlashcardKind.cloze,
          groupId: 'g',
          clozeIndex: 1,
        );
        await seedCard(
          'hueco-2',
          kind: FlashcardKind.cloze,
          groupId: 'g',
          clozeIndex: 2,
        );

        final present = await repository.alreadyImported([
          imported(guid: 'hueco-1', kind: AnkiCardKind.cloze, clozeNumber: 1),
          imported(
            guid: 'hueco-1',
            ankiId: 2,
            ord: 1,
            kind: AnkiCardKind.cloze,
            clozeNumber: 2,
          ),
          imported(
            guid: 'hueco-1',
            ankiId: 3,
            ord: 2,
            kind: AnkiCardKind.cloze,
            clozeNumber: 3,
          ),
        ]);

        expect(present, {1, 2}, reason: 'el hueco 3 es nuevo');
      },
    );

    test('una básica con el mismo guid que una de huecos no cuenta', () async {
      await seedCard('x', kind: FlashcardKind.cloze, clozeIndex: 1);

      final present = await repository.alreadyImported([imported(guid: 'x')]);

      expect(present, isEmpty);
    });

    test('con miles de tarjetas pregunta por tandas', () async {
      final cards = [
        for (var i = 0; i < 1500; i++) imported(guid: 'g$i', ankiId: i),
      ];
      // Una en cada borde de tanda (500) y la última.
      for (final i in [0, 499, 500, 501, 1000, 1499]) {
        await seedCard(ankiImportedCardId(cards[i]));
      }

      expect(await repository.alreadyImported(cards), {
        0,
        499,
        500,
        501,
        1000,
        1499,
      });
    });
  });

  group('existingItems', () {
    test('dice cuáles existen y cuáles están en la papelera', () async {
      await insertItemRows(db, id: 'borrado', title: 'Borrado');
      await (db.update(db.knowledgeEntries)
            ..where((e) => e.id.equals('borrado')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(at)));

      final found = await repository.existingItems([
        'item',
        'borrado',
        'nunca-existio',
      ]);

      expect(found, {'item': false, 'borrado': true});
    });
  });
}
