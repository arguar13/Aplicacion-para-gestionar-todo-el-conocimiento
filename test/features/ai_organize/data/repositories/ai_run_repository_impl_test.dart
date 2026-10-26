import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show right;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
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

  group('lo que costó cada pasada (F39, paso 6)', () {
    Future<AiRun> listedRun(String id) async => (await runs.listRuns())
        .getOrElse((f) => fail('$f'))
        .firstWhere((run) => run.id == id);

    test('una pasada recién abierta no costó nada, y una de antes de v43 '
        'tampoco: ceros, no un dato inventado', () async {
      final run = await startRun('a');

      final listed = await listedRun(run);

      expect(listed.workTime, Duration.zero);
      expect((listed.inputTokens, listed.outputTokens), (0, 0));
      expect(listed.hasUsage, isFalse);
      expect(listed.scope, AiRunScope.organize);
    });

    test('lo gastado se suma en cada tanda de trabajo: una pasada cortada '
        'esperando al modelo y retomada suma las dos', () async {
      final run = await startRun('a');

      await runs.addUsage(
        run,
        const AiTaskUsage(
          elapsed: Duration(seconds: 40),
          inputTokens: 1000,
          outputTokens: 200,
        ),
      );
      await runs.addUsage(
        run,
        const AiTaskUsage(
          elapsed: Duration(milliseconds: 2500),
          inputTokens: 500,
          outputTokens: 50,
        ),
      );

      final listed = await listedRun(run);
      expect(listed.workTime, const Duration(milliseconds: 42500));
      expect((listed.inputTokens, listed.outputTokens), (1500, 250));
      expect(listed.tokens, 1750);
      expect(listed.hasUsage, isTrue);
    });

    test('sumar a una pasada que ya no existe es un fallo, no un silencio', () {
      return runs
          .addUsage('fantasma', const AiTaskUsage(inputTokens: 1))
          .then((result) => expect(result.isLeft(), isTrue));
    });

    test('cada pasada lleva lo suyo', () async {
      final a = await startRun('a');
      final b = await startRun('b');

      await runs.addUsage(a, const AiTaskUsage(inputTokens: 7));

      expect((await listedRun(a)).inputTokens, 7);
      expect((await listedRun(b)).inputTokens, 0);
    });

    test('el análisis para estudiar es una pasada de estudio: se lista con '
        'su costo, no cuenta como organizar el elemento ni se deshace con '
        '«deshacer todo»', () async {
      final organized = await organizeA();
      await runs.finishRun(organized);
      now = DateTime(2026, 10, 3);
      final study = (await runs.startRun(
        'a',
        model: 'gemini-3.8-flash',
        scope: AiRunScope.study,
      )).getOrElse((f) => fail('$f'));
      await runs.addUsage(
        study,
        const AiTaskUsage(elapsed: Duration(minutes: 3), outputTokens: 900),
      );
      await runs.finishRun(study);

      final listed = await listedRun(study);
      expect(listed.scope, AiRunScope.study);
      expect(listed.organizedItem, isFalse);
      expect(listed.workTime, const Duration(minutes: 3));
      expect(listed.remaining.isEmpty, isTrue);

      // «Deshacer todo» deshace lo que la IA organizó y deja el estudio.
      await runs.undoItem('a');
      expect((await listedRun(organized)).isUndone, isTrue);
      expect((await listedRun(study)).isUndone, isFalse);
      // Y tampoco lo hace pasar por «organizado»: no aparece deshecho porque
      // la última pasada que organizó sí lo está.
      expect(
        (await runs.undoneItemsAmong(['a'])).getOrElse((f) => fail('$f')),
        {'a'},
      );
    });
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
        AiModelWork(model: 'Gemma 4 E4B', things: 4, items: 2),
        AiModelWork(model: 'gemini-3.8-flash', things: 1, items: 1),
      ]);

      await KnowledgeEntryWriter(db, clock: () => now).trash(['a']);
      expect((await runs.aiWorkByModel()).getOrElse((f) => fail('$f')), const [
        AiModelWork(model: 'Gemma 4 E4B', things: 1, items: 1),
        AiModelWork(model: 'gemini-3.8-flash', things: 1, items: 1),
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
        const [AiModelWork(model: 'Gemma 4 E4B', things: 3, items: 1)],
      );
      // Sin revisor, todo.
      expect((await runs.aiWorkByModel()).getOrElse((f) => fail('$f')), const [
        AiModelWork(model: 'Gemma 4 E4B', things: 5, items: 2),
        AiModelWork(model: 'gemini-3.8-flash', things: 4, items: 1),
      ]);
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
        AiModelWork(model: null, things: 1, items: 1),
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

    group('cuenta también lo demás (F33, 4d)', () {
      setUp(() async {
        for (final (id, name) in [('lit', 'Literatura'), ('arte', 'Arte')]) {
          await db
              .into(db.spaces)
              .insert(
                SpacesCompanion.insert(id: id, name: name, createdAt: now),
              );
        }
      });

      /// Una pasada de Gemma sobre «a» que hace de todo menos tarjetas: un
      /// vínculo, una extracción, una etiqueta, el tema, la editorial y el
      /// tipo de obra.
      Future<String> organizeAllOfA() async {
        final run = (await runs.startRun(
          'a',
          model: 'Gemma 4 E4B',
        )).getOrElse((f) => fail('$f'));
        final ai = AiProvenance(runId: run);
        await organize.createRelation(
          fromItemId: 'a',
          toItemId: 'b',
          kind: RelationKind.relatedTo,
          ai: ai,
        );
        await organize.createRelation(
          fromItemId: 'c',
          toItemId: 'a',
          kind: RelationKind.extractedFrom,
          ai: ai,
        );
        await organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Cuento',
          origin: ItemPropertyOrigin.ai,
          aiRunId: run,
        );
        // La que le puso a otro elemento no es de «a», ni de «b»: no la hizo
        // una pasada sobre «b».
        await organize.assignProperty(
          itemId: 'b',
          definitionId: tema,
          value: 'Novela',
          origin: ItemPropertyOrigin.ai,
          aiRunId: run,
        );
        await runs.applySpace(runId: run, itemId: 'a', spaceId: 'arte');
        await runs.completeReference(
          runId: run,
          itemId: 'a',
          extracted: const ExtractedMetadata(
            reference: ReferenceData(
              type: ReferenceType.book,
              publisher: 'Planeta',
            ),
          ),
        );
        await runs.finishRun(run);
        return run;
      }

      /// Una nota mapa de la IA, de [model]; con [intro], su introducción.
      Future<void> mapNote(String id, String model, {bool intro = true}) async {
        await insertItemRows(
          db,
          id: id,
          title: 'Mapa $id',
          kind: SourceKind.manualNote,
        );
        await (db.update(
          db.knowledgeNotes,
        )..where((n) => n.itemId.equals(id))).write(
          KnowledgeNotesCompanion(
            noteKind: const Value(NoteKind.map),
            generatedByModel: Value(model),
          ),
        );
        await db
            .into(db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: 'bloques-$id',
                itemId: id,
                kind: RenditionKind.blocks,
                isPrimary: true,
                createdAt: now,
                content: Value(
                  encodeContentBlocks([
                    if (intro) const ContentBlock.paragraph(text: 'Intro.'),
                    const ContentBlock.heading(text: 'Roma', level: 2),
                    const ContentBlock.heading(text: 'Grecia', level: 2),
                  ]),
                ),
              ),
            );
        final run = (await runs.startRun(
          id,
          model: model,
        )).getOrElse((f) => fail('$f'));
        // Su tema es parte de la nota: no se cuenta aparte.
        await organize.assignProperty(
          itemId: id,
          definitionId: tema,
          value: 'Roma',
          origin: ItemPropertyOrigin.ai,
          aiRunId: run,
        );
        await db
            .into(db.aiFieldChanges)
            .insert(
              AiFieldChangesCompanion.insert(
                id: 'mapa-$id',
                aiRunId: run,
                field: AiChangedField.mapNote,
                afterValue: 'roma',
              ),
            );
        await runs.finishRun(run);
      }

      test(
        'el vínculo, la etiqueta, el tema, la editorial y la introducción; '
        'no la estructura, el tipo de obra ni el tema de una nota mapa',
        () async {
          await organizeAllOfA();
          await mapNote('m', 'gemini-3.8-flash');
          await mapNote('n', 'gemini-3.8-flash', intro: false);

          expect(
            (await runs.aiWorkByModel()).getOrElse((f) => fail('$f')),
            const [
              AiModelWork(model: 'Gemma 4 E4B', things: 4, items: 1),
              AiModelWork(model: 'gemini-3.8-flash', things: 1, items: 1),
            ],
          );
          expect(
            (await runs.reviewCandidates(
              reviewer: 'otro',
            )).getOrElse((f) => fail('$f')),
            const [
              AiReviewCandidate(itemId: 'a', others: 4),
              AiReviewCandidate(itemId: 'm', others: 1),
            ],
          );
        },
      );

      test('lo que la persona cambió deja de contar', () async {
        await organizeAllOfA();
        await mapNote('m', 'gemini-3.8-flash');
        final writer = KnowledgeEntryWriter(db, clock: () => now);
        await writer.setSpaces(['a'], {'lit'});
        await writer.setReference(
          'a',
          const ReferenceData(type: ReferenceType.book, publisher: 'Alfaguara'),
        );
        await organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Cuento',
        );
        await writer.markDerivedEdited('m');

        expect(
          (await runs.aiWorkByModel()).getOrElse((f) => fail('$f')),
          const [AiModelWork(model: 'Gemma 4 E4B', things: 1, items: 1)],
        );
      });

      test('la introducción no cuenta si la persona deshizo la pasada de la '
          'nota, pero sí después de deshacer una revisión', () async {
        await mapNote('m', 'gemini-3.8-flash');
        now = now.add(const Duration(minutes: 1));
        final review = (await runs.startRun(
          'm',
          model: 'Gemma 4 E4B',
          scope: AiRunScope.review,
        )).getOrElse((f) => fail('$f'));
        await runs.undoRun(review);
        expect(
          (await runs.aiWorkByModel()).getOrElse((f) => fail('$f')),
          const [AiModelWork(model: 'gemini-3.8-flash', things: 1, items: 1)],
        );

        final made = (await runs.listRuns(
          itemId: 'm',
        )).getOrElse((f) => fail('$f')).firstWhere((r) => r.id != review);
        await runs.undoRun(made.id);
        await KnowledgeEntryWriter(db, clock: () => now).restore(['m']);
        expect(
          (await runs.aiWorkByModel()).getOrElse((f) => fail('$f')),
          isEmpty,
        );
      });

      test('las tarjetas y lo demás de un elemento van por separado: el costo '
          'los manda en pedidos distintos', () async {
        await organizeAllOfA();
        await cardsBy('a', 'Gemma 4 E4B', 5);

        final candidates = (await runs.reviewCandidates(
          reviewer: 'otro',
        )).getOrElse((f) => fail('$f'));
        expect(candidates, const [
          AiReviewCandidate(itemId: 'a', cards: 5, others: 4),
        ]);
        // De a cuatro: dos pedidos de tarjetas y uno de lo demás.
        expect(aiReviewRequests(candidates, perCall: 4), 3);
      });
    });
  });
}
