import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show right;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Las pasadas de la IA (F27): lo que hizo cada una, y deshacerla entera sin
/// llevarse lo que la persona adoptó ni lo que hizo ella.
void main() {
  late AppDatabase db;
  late AiRunRepositoryImpl runs;
  late OrganizeRepositoryImpl organize;
  late FlashcardRepositoryImpl flashcards;
  late String tema;
  var now = DateTime(2026, 10, 2, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 10, 2, 10);
    final ids = FakeIdGenerator();
    final telemetry = _MockTelemetryService();
    runs = AiRunRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: ids,
      clock: () => now,
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: ids,
      clock: () => now,
    );
    flashcards = FlashcardRepositoryImpl(
      database: db,
      telemetry: telemetry,
      ids: ids,
      clock: () => now,
    );
    for (final id in ['a', 'b', 'c']) {
      await insertItemRows(db, id: id, title: 'Elemento $id');
    }
    tema = await temaDefinitionId(db);
  });

  tearDown(() => db.close());

  Future<String> startRun(String itemId) async => (await runs.startRun(
    itemId,
    model: 'gemma',
  )).getOrElse((f) => fail('$f'));

  /// Una pasada sobre «a» que crea dos vínculos, dos tarjetas y un tema.
  Future<String> organizeA() async {
    final run = await startRun('a');
    final ai = AiProvenance(runId: run, confidence: 0.9);
    for (final other in ['b', 'c']) {
      await organize.createRelation(
        fromItemId: 'a',
        toItemId: other,
        kind: RelationKind.relatedTo,
        note: 'motivo',
        ai: ai,
      );
    }
    for (final question in ['¿Uno?', '¿Dos?']) {
      await flashcards.create(itemId: 'a', front: question, back: 'Sí', ai: ai);
    }
    await organize.assignProperty(
      itemId: 'a',
      definitionId: tema,
      value: 'Roma',
      origin: ItemPropertyOrigin.ai,
      aiRunId: run,
    );
    return run;
  }

  test('terminar una pasada cuenta lo que creó', () async {
    final run = await organizeA();

    final tally = await runs.finishRun(run);

    expect(
      tally,
      right<Failure, AiRunTally>(
        const AiRunTally(relations: 2, flashcards: 2, properties: 1),
      ),
    );
    final row = await db.select(db.aiRuns).getSingle();
    expect(row.finishedAt, now);
    expect(row.relationsCreated, 2);
    expect(row.model, 'gemma');
  });

  group('deshacer una pasada', () {
    test('se lleva todo lo que sigue siendo de la IA, y nada más', () async {
      final run = await organizeA();
      await runs.finishRun(run);
      // Lo de la persona, que no se toca.
      await organize.createRelation(
        fromItemId: 'b',
        toItemId: 'c',
        kind: RelationKind.cites,
      );
      await flashcards.create(itemId: 'a', front: 'Mía', back: 'Sí');
      // Y algo de la IA que la persona adoptó al editarlo.
      final adoptedRelation = await (db.select(
        db.relations,
      )..where((r) => r.toItemId.equals('b'))).getSingle();
      await organize.updateRelation(
        adoptedRelation.id,
        kind: RelationKind.continues,
      );
      final adoptedCard = await (db.select(
        db.flashcards,
      )..where((f) => f.front.equals('¿Uno?'))).getSingle();
      await flashcards.update(
        id: adoptedCard.id,
        front: '¿Uno, de verdad?',
        back: 'Sí',
      );

      now = DateTime(2026, 10, 3);
      final undone = await runs.undoRun(run);

      expect(
        undone,
        right<Failure, AiRunTally>(
          const AiRunTally(relations: 1, flashcards: 1, properties: 1),
        ),
      );
      final relationsLeft = await db.select(db.relations).get();
      expect(relationsLeft.map((r) => r.id).toSet(), {
        adoptedRelation.id,
        relationsLeft.firstWhere((r) => r.kind == RelationKind.cites).id,
      });
      final cardsLeft = await db.select(db.flashcards).get();
      expect(cardsLeft.map((c) => c.front).toSet(), {
        '¿Uno, de verdad?',
        'Mía',
      });
      expect(await db.select(db.itemPropertyValues).get(), isEmpty);
      expect((await db.select(db.aiRuns).getSingle()).undoneAt, now);
    });

    test('dos veces no borra nada la segunda ni cambia la fecha', () async {
      final run = await organizeA();
      await runs.undoRun(run);
      final firstUndo = (await db.select(db.aiRuns).getSingle()).undoneAt;

      now = DateTime(2026, 10, 9);
      final again = await runs.undoRun(run);

      expect(again, right<Failure, AiRunTally>(const AiRunTally()));
      expect((await db.select(db.aiRuns).getSingle()).undoneAt, firstUndo);
    });

    test('una que no existe es un fallo', () async {
      expect((await runs.undoRun('no-existe')).isLeft(), isTrue);
    });

    test('no deja nada a medias: si algo falla, no se borra nada', () async {
      final run = await organizeA();
      await db.customStatement('''
        CREATE TEMP TRIGGER falla_al_borrar_tarjetas
        BEFORE DELETE ON flashcards
        BEGIN SELECT RAISE(ABORT, 'falla a propósito'); END''');

      final result = await runs.undoRun(run);

      expect(result.isLeft(), isTrue);
      expect(await db.select(db.relations).get(), hasLength(2));
      expect((await db.select(db.aiRuns).getSingle()).undoneAt, isNull);
    });
  });

  test('deshacer un elemento deshace todas sus pasadas en pie', () async {
    final first = await organizeA();
    await runs.undoRun(first);
    final second = await startRun('a');
    await organize.createRelation(
      fromItemId: 'c',
      toItemId: 'a',
      kind: RelationKind.cites,
      ai: AiProvenance(runId: second),
    );
    final third = await startRun('a');
    await flashcards.create(
      itemId: 'a',
      front: '¿Tres?',
      back: 'Sí',
      ai: AiProvenance(runId: third),
    );
    final elsewhere = await startRun('b');
    await flashcards.create(
      itemId: 'b',
      front: '¿De otro?',
      back: 'Sí',
      ai: AiProvenance(runId: elsewhere),
    );

    final undone = await runs.undoItem('a');

    expect(
      undone,
      right<Failure, AiRunTally>(const AiRunTally(relations: 1, flashcards: 1)),
    );
    expect((await db.select(db.flashcards).getSingle()).front, '¿De otro?');
    expect(await db.select(db.relations).get(), isEmpty);
  });

  group('listar', () {
    test(
      'de la más nueva a la más vieja, con lo creado y lo que queda',
      () async {
        final older = await organizeA();
        await runs.finishRun(older);
        now = DateTime(2026, 10, 5);
        final newer = await startRun('b');
        await runs.finishRun(newer);
        // La persona adopta una tarjeta de la primera.
        final card = await (db.select(
          db.flashcards,
        )..where((f) => f.front.equals('¿Uno?'))).getSingle();
        await flashcards.update(id: card.id, front: '¿Uno!', back: 'Sí');

        final listed = (await runs.listRuns()).getOrElse((f) => fail('$f'));

        expect(listed.map((r) => r.id), [newer, older]);
        final first = listed.last;
        expect(first.itemTitle, 'Elemento a');
        expect(
          first.created,
          const AiRunTally(relations: 2, flashcards: 2, properties: 1),
        );
        expect(
          first.remaining,
          const AiRunTally(relations: 2, flashcards: 1, properties: 1),
        );
        expect(first.isUndone, isFalse);
      },
    );

    test('por elemento, de a páginas', () async {
      for (var i = 0; i < 3; i++) {
        now = DateTime(2026, 10, 2 + i);
        await startRun('a');
      }
      await startRun('b');

      final page = (await runs.listRuns(
        itemId: 'a',
        limit: 2,
        offset: 1,
      )).getOrElse((f) => fail('$f'));

      expect(page, hasLength(2));
      expect(page.every((r) => r.itemId == 'a'), isTrue);
      expect(page.first.startedAt, DateTime(2026, 10, 3));
    });

    test('las de un elemento en la papelera no se listan', () async {
      await startRun('a');
      await (db.update(db.knowledgeEntries)..where((e) => e.id.equals('a')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));

      expect((await runs.listRuns()).getOrElse((f) => fail('$f')), isEmpty);
    });
  });

  test('qué elementos tienen deshecha su última pasada', () async {
    // «a»: deshecha. «b»: deshecha y después organizada de nuevo a pedido.
    // «c»: nunca organizado.
    await runs.undoRun(await startRun('a'));
    await runs.undoRun(await startRun('b'));
    now = DateTime(2026, 10, 3);
    await runs.finishRun(await startRun('b'));

    final undone = await runs.undoneItemsAmong(['a', 'b', 'c']);

    expect(undone.getOrElse((f) => fail('$f')), {'a'});
    expect(
      (await runs.undoneItemsAmong(const [])).getOrElse((f) => fail('$f')),
      isEmpty,
    );
  });

  test('una pasada de solo tarjetas (F30) guarda su alcance, cuenta sus '
      'tarjetas y se deshace como cualquiera', () async {
    final run = (await runs.startRun(
      'a',
      model: 'gemma',
      scope: AiRunScope.flashcards,
    )).getOrElse((f) => fail('$f'));
    expect(
      (await (db.select(
        db.aiRuns,
      )..where((r) => r.id.equals(run))).getSingle()).scope,
      AiRunScope.flashcards,
    );
    // El alcance es de la pasada: no deja nada en los datos que completó.
    expect(await db.select(db.aiFieldChanges).get(), isEmpty);
    for (final question in ['¿Uno?', '¿Dos?']) {
      await flashcards.create(
        itemId: 'a',
        front: question,
        back: 'x',
        ai: AiProvenance(runId: run),
      );
    }
    await runs.finishRun(run);

    final listed = (await runs.listRuns()).getOrElse((f) => fail('$f')).single;
    expect(listed.created, const AiRunTally(flashcards: 2));
    expect(listed.remaining, const AiRunTally(flashcards: 2));

    final undone = (await runs.undoRun(run)).getOrElse((f) => fail('$f'));
    expect(undone, const AiRunTally(flashcards: 2));
    expect(await db.select(db.flashcards).get(), isEmpty);
  });

  test('borrar el elemento se lleva sus pasadas', () async {
    await organizeA();

    await (db.delete(db.knowledgeEntries)..where((e) => e.id.equals('a'))).go();

    expect(await db.select(db.aiRuns).get(), isEmpty);
  });
}
