import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show right;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
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

  group('qué hay para revisar con otro modelo (F33)', () {
    /// Una pasada de [model] sobre [itemId] con [cards] tarjetas de la IA.
    Future<String> cardsBy(String itemId, String? model, int cards) async {
      final run = (await runs.startRun(
        itemId,
        model: model,
      )).getOrElse((f) => fail('$f'));
      for (var i = 0; i < cards; i++) {
        await flashcards.create(
          itemId: itemId,
          front: '¿$model $i en $itemId?',
          back: 'Sí',
          ai: AiProvenance(runId: run),
        );
      }
      await runs.finishRun(run);
      return run;
    }

    test('cuánto hizo cada modelo: solo lo que sigue siendo de la IA, de '
        'pasadas en pie y elementos vivos', () async {
      await cardsBy('a', 'Gemma 4 E4B', 3);
      await cardsBy('b', 'Gemma 4 E4B', 2);
      await cardsBy('c', 'gemini-3.8-flash', 1);
      // Una deshecha, una de la persona y una adoptada no cuentan.
      final undone = await cardsBy('c', 'Gemma 4 E4B', 4);
      await runs.undoRun(undone);
      await flashcards.create(itemId: 'a', front: '¿Mía?', back: 'Sí');
      final adopted = (await flashcards.watchForItem('b').first).first;
      await flashcards.update(id: adopted.id, front: '¿Mía?', back: 'Sí');

      final work = (await runs.aiWorkByModel()).getOrElse((f) => fail('$f'));

      expect(work, const [
        AiModelWork(model: 'Gemma 4 E4B', cards: 4, items: 2),
        AiModelWork(model: 'gemini-3.8-flash', cards: 1, items: 1),
      ]);

      await KnowledgeEntryWriter(db, clock: () => now).trash(['a']);
      expect((await runs.aiWorkByModel()).getOrElse((f) => fail('$f')), const [
        AiModelWork(model: 'Gemma 4 E4B', cards: 1, items: 1),
        AiModelWork(model: 'gemini-3.8-flash', cards: 1, items: 1),
      ]);
    });

    test('toda la biblioteca: sin lo del mismo modelo ni lo que ya revisó, '
        'el que más tiene primero', () async {
      await cardsBy('a', 'Gemma 4 E4B', 1);
      await cardsBy('b', 'Gemma 4 E4B', 3);
      await cardsBy('b', 'gemini-3.8-flash', 2);
      await cardsBy('c', 'gemini-3.8-flash', 2);

      final all = (await runs.reviewCandidates(
        reviewer: 'gemini-3.8-flash',
      )).getOrElse((f) => fail('$f'));
      expect(all, const [
        AiReviewCandidate(itemId: 'b', cards: 3),
        AiReviewCandidate(itemId: 'a', cards: 1),
      ]);

      // «a» ya la revisó: una pasada de revisión suya, terminada y en pie.
      final review = (await runs.startRun(
        'a',
        model: 'gemini-3.8-flash',
        scope: AiRunScope.review,
      )).getOrElse((f) => fail('$f'));
      // Sin terminar todavía cuenta como por revisar.
      expect(
        (await runs.reviewCandidates(
          reviewer: 'gemini-3.8-flash',
        )).getOrElse((f) => fail('$f')),
        hasLength(2),
      );
      await runs.finishRun(review);
      expect(
        (await runs.reviewCandidates(
          reviewer: 'gemini-3.8-flash',
        )).getOrElse((f) => fail('$f')),
        const [AiReviewCandidate(itemId: 'b', cards: 3)],
      );
      // Deshecha, vuelve a estar por revisar.
      await runs.undoRun(review);
      expect(
        (await runs.reviewCandidates(
          reviewer: 'gemini-3.8-flash',
        )).getOrElse((f) => fail('$f')),
        hasLength(2),
      );
      // Otro modelo revisa todo, también lo de Gemini.
      expect(
        (await runs.reviewCandidates(
          reviewer: 'claude-opus-5-5',
        )).getOrElse((f) => fail('$f')),
        const [
          AiReviewCandidate(itemId: 'b', cards: 5),
          AiReviewCandidate(itemId: 'c', cards: 2),
          AiReviewCandidate(itemId: 'a', cards: 1),
        ],
      );
    });

    test('lo que un revisor todavía tiene, por modelo: sin lo suyo ni lo '
        'que ya revisó', () async {
      await cardsBy('a', 'Gemma 4 E4B', 2);
      await cardsBy('b', 'Gemma 4 E4B', 3);
      await cardsBy('b', 'gemini-3.8-flash', 4);
      final review = (await runs.startRun(
        'a',
        model: 'gemini-3.8-flash',
        scope: AiRunScope.review,
      )).getOrElse((f) => fail('$f'));
      await runs.finishRun(review);

      expect(
        (await runs.aiWorkByModel(
          reviewer: 'gemini-3.8-flash',
        )).getOrElse((f) => fail('$f')),
        const [AiModelWork(model: 'Gemma 4 E4B', cards: 3, items: 1)],
      );
      // Sin revisor, todo.
      expect(
        (await runs.aiWorkByModel()).getOrElse((f) => fail('$f')),
        const [
          AiModelWork(model: 'Gemma 4 E4B', cards: 5, items: 2),
          AiModelWork(model: 'gemini-3.8-flash', cards: 4, items: 1),
        ],
      );
    });

    test('cuántos pedidos lleva: de a tantas tarjetas por pedido, por '
        'elemento', () {
      const candidates = [
        AiReviewCandidate(itemId: 'a', cards: 5),
        AiReviewCandidate(itemId: 'b', cards: 4),
        AiReviewCandidate(itemId: 'c', cards: 1),
      ];
      expect(aiReviewRequests(candidates, perCall: 4), 4);
      expect(aiReviewRequests(candidates, perCall: 8), 3);
      expect(aiReviewRequests(const [], perCall: 4), 0);
    });

    test('solo lo de un modelo', () async {
      await cardsBy('b', 'Gemma 4 E4B', 3);
      await cardsBy('b', 'gemini-3.8-flash', 2);

      expect(
        (await runs.reviewCandidates(
          reviewer: 'claude-opus-5-5',
          madeBy: 'gemini-3.8-flash',
        )).getOrElse((f) => fail('$f')),
        const [AiReviewCandidate(itemId: 'b', cards: 2)],
      );
    });

    test('lo hecho sin modelo anotado también se revisa; los huecos no: el '
        'revisor mira preguntas y respuestas', () async {
      await cardsBy('a', null, 1);
      final run = (await runs.startRun(
        'b',
        model: 'Gemma 4 E4B',
      )).getOrElse((f) => fail('$f'));
      (await flashcards.create(
        itemId: 'b',
        front: 'El {{c1::Quijote}} lo escribió Cervantes.',
        back: '',
        kind: FlashcardKind.cloze,
        clozeIndex: 1,
        ai: AiProvenance(runId: run),
      )).getOrElse((f) => fail('$f'));

      expect(
        (await runs.reviewCandidates(
          reviewer: 'gemini-3.8-flash',
        )).getOrElse((f) => fail('$f')),
        const [AiReviewCandidate(itemId: 'a', cards: 1)],
      );
      expect((await runs.aiWorkByModel()).getOrElse((f) => fail('$f')), const [
        AiModelWork(model: null, cards: 1, items: 1),
      ]);
    });

    test('un elemento, pedido por la persona: todo lo suyo, aunque sea del '
        'mismo modelo o ya lo haya revisado', () async {
      await cardsBy('a', 'gemini-3.8-flash', 2);
      await cardsBy('b', 'Gemma 4 E4B', 1);
      final review = (await runs.startRun(
        'a',
        model: 'gemini-3.8-flash',
        scope: AiRunScope.review,
      )).getOrElse((f) => fail('$f'));
      await runs.finishRun(review);

      expect(
        (await runs.reviewCandidates(
          reviewer: 'gemini-3.8-flash',
          itemId: 'a',
        )).getOrElse((f) => fail('$f')),
        const [AiReviewCandidate(itemId: 'a', cards: 2)],
      );
    });
  });
}
