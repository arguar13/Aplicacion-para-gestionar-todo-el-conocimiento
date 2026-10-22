import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Left, Unit, right, unit;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/correction_suggestions.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import '../../support/fake_id_generator.dart';
import '../../support/item_rows.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Las correcciones de «Revisar con otro modelo» (F33): nada cambia hasta que
/// se aceptan; aceptarlas aplica el cambio dentro de la pasada de revisión, y
/// deshacer esa pasada lo devuelve a como estaba —sin pisar lo que la persona
/// cambió después—.
void main() {
  late AppDatabase db;
  late AiRunRepositoryImpl runs;
  late FlashcardRepositoryImpl flashcards;
  late SuggestionRepositoryImpl suggestions;
  var now = DateTime(2026, 10, 17, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 10, 17, 10);
    final ids = FakeIdGenerator();
    final telemetry = _MockTelemetryService();
    runs = AiRunRepositoryImpl(
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
    suggestions = SuggestionRepositoryImpl(
      database: db,
      telemetry: telemetry,
      organize: OrganizeRepositoryImpl(
        database: db,
        telemetry: telemetry,
        ids: ids,
        clock: () => now,
      ),
      merge: null,
      ids: ids,
      clock: () => now,
    );
    await insertItemRows(db, id: 'a', title: 'Elemento a');
  });

  tearDown(() => db.close());

  /// La pasada de Gemma que hizo la tarjeta, y la tarjeta.
  Future<({String run, String card})> aiCard({
    String front = '¿Quién escribió el Quijote?',
    String back = 'Lope de Vega.',
  }) async {
    final run = (await runs.startRun(
      'a',
      model: 'Gemma 4 E4B',
    )).getOrElse((f) => fail('$f'));
    final card = (await flashcards.create(
      itemId: 'a',
      front: front,
      back: back,
      ai: AiProvenance(runId: run),
    )).getOrElse((f) => fail('$f'));
    await runs.finishRun(run);
    return (run: run, card: card.id);
  }

  Future<String> reviewRun() async => (await runs.startRun(
    'a',
    model: 'gemini-3.8-flash',
    scope: AiRunScope.review,
  )).getOrElse((f) => fail('$f'));

  Future<CorrectionSuggestion> propose(
    String card,
    String run, {
    Map<String, String>? after = const {
      FlashcardCorrectionField.front: '¿Quién escribió el Quijote?',
      FlashcardCorrectionField.back: 'Miguel de Cervantes.',
    },
    String before = 'Lope de Vega.',
  }) async =>
      (await suggestions.createCorrectionSuggestion(
            targetItemId: 'a',
            subject: CorrectionSubject.flashcard,
            subjectId: card,
            before: {
              FlashcardCorrectionField.front: '¿Quién escribió el Quijote?',
              FlashcardCorrectionField.back: before,
            },
            after: after,
            reason: 'El pasaje dice Cervantes.',
            aiRunId: run,
            model: 'gemini-3.8-flash',
          )).getOrElse((f) => fail('$f'))
          as CorrectionSuggestion;

  Future<FlashcardRow?> cardRow(String id) => (db.select(
    db.flashcards,
  )..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<SuggestionStatus> statusOf(String id) async => (await (db.select(
    db.suggestions,
  )..where((s) => s.id.equals(id))).getSingle()).status;

  Future<bool> questionRejected(String question) async =>
      (await runs.isFlashcardRejected(
        itemId: 'a',
        question: question,
      )).getOrElse((f) => fail('$f'));

  test('se guarda con todo lo que hace falta y se lee igual', () async {
    final made = await aiCard();
    final run = await reviewRun();

    final created = await propose(made.card, run);
    final read = (await suggestions.suggestionsFor(
      'a',
    )).getOrElse((f) => fail('$f')).single;

    expect(read, created);
    expect(created.subject, CorrectionSubject.flashcard);
    expect(created.subjectId, made.card);
    expect(created.before[FlashcardCorrectionField.back], 'Lope de Vega.');
    expect(
      created.after![FlashcardCorrectionField.back],
      'Miguel de Cervantes.',
    );
    expect(created.reason, 'El pasaje dice Cervantes.');
    expect(created.aiRunId, run);
    expect(created.model, 'gemini-3.8-flash');
    expect(created.status, SuggestionStatus.pending);
    // Nada cambia hasta que se acepta.
    expect((await cardRow(made.card))!.back, 'Lope de Vega.');
  });

  test('una corrección no aparece en «Para revisar»', () async {
    final made = await aiCard();
    await propose(made.card, await reviewRun());

    expect(await suggestions.watchPendingReviewCount().first, 0);
    expect(await suggestions.watchItemsWithPendingReview().first, isEmpty);
  });

  group('lo que muestra «Revisión»', () {
    test('por elemento, el de la más nueva primero, solo las pendientes '
        'que todavía valen', () async {
      await insertItemRows(db, id: 'b', title: 'Elemento b');
      final first = await aiCard();
      final stale = await aiCard(front: '¿Cuándo cayó Roma?', back: 'En 1453.');
      final run = await reviewRun();
      final kept = await propose(first.card, run);
      // Una sobre una tarjeta que la persona editó después: ya no vale.
      final gone = (await suggestions.createCorrectionSuggestion(
        targetItemId: 'a',
        subject: CorrectionSubject.flashcard,
        subjectId: stale.card,
        before: {
          FlashcardCorrectionField.front: '¿Cuándo cayó Roma?',
          FlashcardCorrectionField.back: 'En 1453.',
        },
        after: null,
        reason: 'r',
        aiRunId: run,
      )).getOrElse((f) => fail('$f'));
      await flashcards.update(
        id: stale.card,
        front: '¿Cuándo cayó Roma?',
        back: 'En 476.',
      );
      // Otra en «b», más nueva.
      final bRun = (await runs.startRun('b')).getOrElse((f) => fail('$f'));
      final bCard = (await flashcards.create(
        itemId: 'b',
        front: '¿Qué?',
        back: 'Eso.',
        ai: AiProvenance(runId: bRun),
      )).getOrElse((f) => fail('$f'));
      now = now.add(const Duration(minutes: 1));
      final newer = (await suggestions.createCorrectionSuggestion(
        targetItemId: 'b',
        subject: CorrectionSubject.flashcard,
        subjectId: bCard.id,
        before: {
          FlashcardCorrectionField.front: '¿Qué?',
          FlashcardCorrectionField.back: 'Eso.',
        },
        after: null,
        reason: 'r',
        aiRunId: run,
      )).getOrElse((f) => fail('$f'));

      final items = await suggestions.watchPendingCorrections().first;

      expect(items.map((i) => i.itemId), ['b', 'a']);
      expect(items.first.itemTitle, 'Elemento b');
      expect(items.first.corrections.map((c) => c.id), [newer.id]);
      expect(items.last.corrections.map((c) => c.id), [kept.id]);
      expect(items.last.corrections, isNot(contains(gone)));
    });

    test('se actualiza al aceptar y no muestra las de un elemento en la '
        'papelera', () async {
      final made = await aiCard();
      final correction = await propose(made.card, await reviewRun());
      final seen = StreamQueue(suggestions.watchPendingCorrections());
      expect((await seen.next).single.corrections.single.id, correction.id);

      await suggestions.accept(correction.id);
      expect(await seen.next, isEmpty);
      await seen.cancel();

      final other = await aiCard(front: '¿Otra?', back: 'Sí.');
      final second = (await suggestions.createCorrectionSuggestion(
        targetItemId: 'a',
        subject: CorrectionSubject.flashcard,
        subjectId: other.card,
        before: {
          FlashcardCorrectionField.front: '¿Otra?',
          FlashcardCorrectionField.back: 'Sí.',
        },
        after: null,
        reason: 'r',
        aiRunId: await reviewRun(),
      )).getOrElse((f) => fail('$f'));
      expect(
        (await suggestions.watchPendingCorrections().first)
            .single
            .corrections
            .single
            .id,
        second.id,
      );
      await KnowledgeEntryWriter(db, clock: () => now).trash(['a']);
      expect(await suggestions.watchPendingCorrections().first, isEmpty);
    });

    test(
      'se va sola si la persona edita la tarjeta mientras se mira',
      () async {
        final made = await aiCard();
        await propose(made.card, await reviewRun());
        final seen = StreamQueue(suggestions.watchPendingCorrections());
        expect(await seen.next, hasLength(1));

        await flashcards.update(
          id: made.card,
          front: '¿Quién escribió el Quijote?',
          back: 'Cervantes.',
        );

        expect(await seen.next, isEmpty);
        await seen.cancel();
      },
    );
  });

  group('aceptar una corrección', () {
    test(
      'corrige la tarjeta, que sigue siendo de la IA y de su pasada',
      () async {
        final made = await aiCard(front: '¿Quién escribió eso?');
        final run = await reviewRun();
        final correction = (await suggestions.createCorrectionSuggestion(
          targetItemId: 'a',
          subject: CorrectionSubject.flashcard,
          subjectId: made.card,
          before: {
            FlashcardCorrectionField.front: '¿Quién escribió eso?',
            FlashcardCorrectionField.back: 'Lope de Vega.',
          },
          after: {
            FlashcardCorrectionField.front: '  ¿Quién escribió el Quijote?  ',
            FlashcardCorrectionField.back: 'Miguel de Cervantes.',
          },
          reason: 'r',
          aiRunId: run,
        )).getOrElse((f) => fail('$f'));

        expect(
          await suggestions.accept(correction.id),
          right<Failure, Unit>(unit),
        );

        final card = (await cardRow(made.card))!;
        expect(card.front, '¿Quién escribió el Quijote?');
        expect(card.back, 'Miguel de Cervantes.');
        expect(card.origin, ContentOrigin.ai);
        expect(card.aiRunId, made.run);
        expect(await statusOf(correction.id), SuggestionStatus.accepted);
        // La pregunta de antes estaba mal: la IA no la vuelve a hacer.
        expect(await questionRejected('¿Quién escribió eso?'), isTrue);
        // Se recuerda como quedó, sin los espacios: sigue en pie.
        expect(await aiCorrectionCounts(db, [run]), {
          run: (created: 1, remaining: 1),
        });
      },
    );

    test(
      'si solo cambia la respuesta, no recuerda la pregunta como mala',
      () async {
        final made = await aiCard();
        final correction = await propose(made.card, await reviewRun());

        await suggestions.accept(correction.id);

        expect(await questionRejected('¿Quién escribió el Quijote?'), isFalse);
      },
    );

    test('sacarla la borra y recuerda que «no era»', () async {
      final made = await aiCard();
      final correction = await propose(
        made.card,
        await reviewRun(),
        after: null,
      );

      expect(
        await suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );

      expect(await cardRow(made.card), isNull);
      expect(await questionRejected('¿Quién escribió el Quijote?'), isTrue);
      expect(await statusOf(correction.id), SuggestionStatus.accepted);
    });

    test('no toca una tarjeta que la persona editó: ya es suya', () async {
      final made = await aiCard();
      final correction = await propose(made.card, await reviewRun());
      await flashcards.update(
        id: made.card,
        front: '¿Quién escribió el Quijote?',
        back: 'Lope de Vega.',
      );

      final result = await suggestions.accept(correction.id);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect((await cardRow(made.card))!.back, 'Lope de Vega.');
      expect(await statusOf(correction.id), SuggestionStatus.pending);
    });

    test('no toca una tarjeta que cambió desde que se revisó', () async {
      final made = await aiCard();
      final correction = await propose(made.card, await reviewRun());
      await (db.update(db.flashcards)..where((f) => f.id.equals(made.card)))
          .write(const FlashcardsCompanion(back: Value('Otra cosa.')));

      expect((await suggestions.accept(correction.id)).isLeft(), isTrue);
      expect((await cardRow(made.card))!.back, 'Otra cosa.');
    });

    test('ni una que ya no está', () async {
      final made = await aiCard();
      final correction = await propose(made.card, await reviewRun());
      await flashcards.delete(made.card);

      expect((await suggestions.accept(correction.id)).isLeft(), isTrue);
      expect(await statusOf(correction.id), SuggestionStatus.pending);
    });
  });

  group('deshacer la pasada de revisión', () {
    test('devuelve la tarjeta corregida a como estaba', () async {
      final made = await aiCard(front: '¿Quién escribió eso?');
      final run = await reviewRun();
      final correction = (await suggestions.createCorrectionSuggestion(
        targetItemId: 'a',
        subject: CorrectionSubject.flashcard,
        subjectId: made.card,
        before: {
          FlashcardCorrectionField.front: '¿Quién escribió eso?',
          FlashcardCorrectionField.back: 'Lope de Vega.',
        },
        after: {
          FlashcardCorrectionField.front: '¿Quién escribió el Quijote?',
          FlashcardCorrectionField.back: 'Miguel de Cervantes.',
        },
        reason: 'r',
        aiRunId: run,
      )).getOrElse((f) => fail('$f'));
      await suggestions.accept(correction.id);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );

      final card = (await cardRow(made.card))!;
      expect(card.front, '¿Quién escribió eso?');
      expect(card.back, 'Lope de Vega.');
      expect(card.origin, ContentOrigin.ai);
      // Lo que recordó la corrección se olvida, y no se vuelve a proponer.
      expect(await questionRejected('¿Quién escribió eso?'), isFalse);
      expect(await statusOf(correction.id), SuggestionStatus.rejected);
    });

    test('devuelve entera la tarjeta que se sacó, con sus repasos', () async {
      final made = await aiCard();
      await flashcards.review(id: made.card, grade: ReviewGrade.good);
      final before = (await cardRow(made.card))!;
      final reviewsBefore = await db.select(db.reviewLogs).get();
      expect(reviewsBefore, hasLength(1));
      final run = await reviewRun();
      final correction = await propose(made.card, run, after: null);
      await suggestions.accept(correction.id);
      expect(await db.select(db.reviewLogs).get(), isEmpty);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );

      expect(await cardRow(made.card), before);
      expect(await db.select(db.reviewLogs).get(), reviewsBefore);
      expect(await questionRejected('¿Quién escribió el Quijote?'), isFalse);
    });

    test(
      'no olvida un «no era» que ya estaba antes de la corrección',
      () async {
        final made = await aiCard();
        // La persona ya había dicho que esa pregunta no era —en otra tarjeta
        // igual, que borró—.
        final other = await aiCard();
        await flashcards.rejectAiFlashcard(other.card);
        final run = await reviewRun();
        final correction = await propose(made.card, run, after: null);
        await suggestions.accept(correction.id);

        await runs.undoRun(run);

        expect(await cardRow(made.card), isNotNull);
        expect(await questionRejected('¿Quién escribió el Quijote?'), isTrue);
      },
    );

    test('no pisa la tarjeta corregida que la persona editó después', () async {
      final made = await aiCard();
      final run = await reviewRun();
      final correction = await propose(made.card, run);
      await suggestions.accept(correction.id);
      await flashcards.update(
        id: made.card,
        front: '¿Quién escribió el Quijote?',
        back: 'Cervantes, en 1605.',
      );

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect((await cardRow(made.card))!.back, 'Cervantes, en 1605.');
    });

    test('no devuelve una tarjeta cuya pasada se deshizo', () async {
      final made = await aiCard();
      final run = await reviewRun();
      final correction = await propose(made.card, run, after: null);
      await suggestions.accept(correction.id);
      await runs.undoRun(made.run);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await cardRow(made.card), isNull);
    });

    test('deshacer la pasada que hizo la tarjeta se lleva también la '
        'corregida', () async {
      final made = await aiCard();
      final correction = await propose(made.card, await reviewRun());
      await suggestions.accept(correction.id);

      final tally = (await runs.undoRun(made.run)).getOrElse((f) => fail('$f'));

      expect(tally.flashcards, 1);
      expect(await cardRow(made.card), isNull);
    });

    test('una corrección pendiente, sin aceptar, no se toca', () async {
      final made = await aiCard();
      final run = await reviewRun();
      final correction = await propose(made.card, run);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await statusOf(correction.id), SuggestionStatus.pending);
    });
  });

  test(
    'la pasada de revisión cuenta lo aceptado: la historia y lo que sigue',
    () async {
      final first = await aiCard();
      final second = await aiCard(
        front: '¿Cuándo cayó Roma?',
        back: 'En 1453.',
      );
      final run = await reviewRun();
      final fix = await propose(first.card, run);
      final drop = (await suggestions.createCorrectionSuggestion(
        targetItemId: 'a',
        subject: CorrectionSubject.flashcard,
        subjectId: second.card,
        before: {
          FlashcardCorrectionField.front: '¿Cuándo cayó Roma?',
          FlashcardCorrectionField.back: 'En 1453.',
        },
        after: null,
        reason: 'r',
        aiRunId: run,
      )).getOrElse((f) => fail('$f'));
      // Una tercera, sin aceptar: no cuenta.
      await propose(first.card, run, before: 'otra');
      await suggestions.accept(fix.id);
      await suggestions.accept(drop.id);

      expect(
        await runs.finishRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 2)),
      );
      // La persona edita la corregida: deja de ser de la revisión.
      await flashcards.update(
        id: first.card,
        front: '¿Quién escribió el Quijote?',
        back: 'Cervantes.',
      );

      final listed = (await runs.listRuns()).getOrElse((f) => fail('$f'));
      final review = listed.firstWhere((r) => r.id == run);
      expect(review.created.corrections, 2);
      expect(review.remaining.corrections, 1);
      expect(review.model, 'gemini-3.8-flash');
    },
  );

  test('deshacer una revisión no cuenta como deshacer lo que hizo la IA: '
      'la cola puede seguir organizando el elemento', () async {
    await aiCard();
    final run = await reviewRun();
    await runs.undoRun(run);

    final undone = (await runs.undoneItemsAmong([
      'a',
    ])).getOrElse((f) => fail('$f'));
    expect(undone, isEmpty);
  });

  group('vínculos (F33, 4a)', () {
    late OrganizeRepositoryImpl organize;

    setUp(() async {
      organize = OrganizeRepositoryImpl(
        database: db,
        telemetry: _MockTelemetryService(),
        ids: FakeIdGenerator(prefix: 'v'),
        clock: () => now,
      );
      await insertItemRows(db, id: 'b', title: 'Cartago');
    });

    /// Un vínculo de la IA de «a» a «b», y la pasada de Gemma que lo hizo.
    Future<({String run, String relation})> aiRelation({
      RelationKind kind = RelationKind.relatedTo,
      String? note = 'Las dos hablan de Roma.',
    }) async {
      final run = (await runs.startRun(
        'a',
        model: 'Gemma 4 E4B',
      )).getOrElse((f) => fail('$f'));
      (await organize.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: kind,
        note: note,
        ai: AiProvenance(runId: run),
      )).getOrElse((f) => fail('$f'));
      await runs.finishRun(run);
      final row = await (db.select(
        db.relations,
      )..where((r) => r.kind.equalsValue(kind))).getSingle();
      return (run: run, relation: row.id);
    }

    Future<RelationRow?> relationRow(String id) => (db.select(
      db.relations,
    )..where((r) => r.id.equals(id))).getSingleOrNull();

    Future<CorrectionSuggestion> proposeOn(
      String relation,
      String run, {
      Map<String, String>? after = const {
        RelationCorrectionField.kind: 'contradicts',
        RelationCorrectionField.note: 'Una dice lo contrario de la otra.',
      },
      String kind = 'relatedTo',
      String note = 'Las dos hablan de Roma.',
    }) async =>
        (await suggestions.createCorrectionSuggestion(
              targetItemId: 'a',
              subject: CorrectionSubject.relation,
              subjectId: relation,
              before: {
                RelationCorrectionField.kind: kind,
                RelationCorrectionField.note: note,
              },
              after: after,
              reason: 'El texto dice que se oponen.',
              aiRunId: run,
              model: 'gemini-3.8-flash',
              label: 'Cartago',
            )).getOrElse((f) => fail('$f'))
            as CorrectionSuggestion;

    Future<bool> kindRejected(RelationKind kind) async =>
        (await runs.isRelationRejected(
          fromItemId: 'a',
          toItemId: 'b',
          kind: kind,
        )).getOrElse((f) => fail('$f'));

    test('se guarda con el título del otro elemento', () async {
      final made = await aiRelation();
      final correction = await proposeOn(made.relation, await reviewRun());

      final read = correctionSuggestionOf(
        await (db.select(
          db.suggestions,
        )..where((s) => s.id.equals(correction.id))).getSingle(),
      );
      expect(read.subject, CorrectionSubject.relation);
      expect(read.label, 'Cartago');
      expect(read.after![RelationCorrectionField.kind], 'contradicts');
    });

    test('aceptar corrige el tipo y la frase; sigue siendo de la IA, de su '
        'pasada, y el tipo de antes «no era»', () async {
      final made = await aiRelation();
      final correction = await proposeOn(
        made.relation,
        await reviewRun(),
        after: const {
          RelationCorrectionField.kind: 'contradicts',
          RelationCorrectionField.note: '  Una dice lo contrario.  ',
        },
      );

      expect(
        await suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );

      final row = (await relationRow(made.relation))!;
      expect(row.kind, RelationKind.contradicts);
      expect(row.note, 'Una dice lo contrario.');
      expect(row.origin, ContentOrigin.ai);
      expect(row.aiRunId, made.run);
      expect(await kindRejected(RelationKind.relatedTo), isTrue);
      expect(await kindRejected(RelationKind.contradicts), isFalse);
      expect(await aiCorrectionCounts(db, [correction.aiRunId]), {
        correction.aiRunId: (created: 1, remaining: 1),
      });
    });

    test('si solo cambia la frase, no recuerda nada como malo', () async {
      final made = await aiRelation();
      final correction = await proposeOn(
        made.relation,
        await reviewRun(),
        after: const {
          RelationCorrectionField.kind: 'relatedTo',
          RelationCorrectionField.note: '',
        },
      );

      await suggestions.accept(correction.id);

      final row = (await relationRow(made.relation))!;
      expect(row.kind, RelationKind.relatedTo);
      expect(row.note, isNull);
      expect(await kindRejected(RelationKind.relatedTo), isFalse);
    });

    test('sacarlo lo borra y recuerda que «no era»', () async {
      final made = await aiRelation();
      final correction = await proposeOn(
        made.relation,
        await reviewRun(),
        after: null,
      );

      await suggestions.accept(correction.id);

      expect(await relationRow(made.relation), isNull);
      expect(await kindRejected(RelationKind.relatedTo), isTrue);
    });

    test('no toca un vínculo que la persona editó, uno que cambió, ni uno '
        'que ya no está', () async {
      final edited = await aiRelation();
      final run = await reviewRun();
      final onEdited = await proposeOn(edited.relation, run);
      await organize.updateRelation(
        edited.relation,
        kind: RelationKind.relatedTo,
        note: 'Mía.',
      );
      expect(await suggestions.accept(onEdited.id), isA<Left<Failure, Unit>>());

      final other = await aiRelation(kind: RelationKind.cites, note: null);
      final stale = await proposeOn(other.relation, run, kind: 'cites');
      expect(await suggestions.accept(stale.id), isA<Left<Failure, Unit>>());
      expect((await relationRow(other.relation))!.kind, RelationKind.cites);

      final gone = await proposeOn(
        other.relation,
        run,
        kind: 'cites',
        note: '',
      );
      await (db.delete(
        db.relations,
      )..where((r) => r.id.equals(other.relation))).go();
      expect(await suggestions.accept(gone.id), isA<Left<Failure, Unit>>());
    });

    test('no le pone un tipo de estructura ni uno que no existe, ni uno que '
        'ya hay entre los dos', () async {
      final made = await aiRelation();
      final run = await reviewRun();
      for (final kind in ['indexes', 'extractedFrom', 'nada']) {
        final correction = await proposeOn(
          made.relation,
          run,
          after: {
            RelationCorrectionField.kind: kind,
            RelationCorrectionField.note: 'x',
          },
        );
        expect(
          await suggestions.accept(correction.id),
          isA<Left<Failure, Unit>>(),
          reason: kind,
        );
      }
      await aiRelation(kind: RelationKind.contradicts);
      final twin = await proposeOn(made.relation, run);
      expect(await suggestions.accept(twin.id), isA<Left<Failure, Unit>>());
      expect((await relationRow(made.relation))!.kind, RelationKind.relatedTo);
    });

    test('dos correcciones del mismo vínculo: aceptada una, la otra ya no '
        'vale aunque la frase siga igual', () async {
      final made = await aiRelation();
      final run = await reviewRun();
      const note = 'Las dos hablan de Roma.';
      final first = await proposeOn(
        made.relation,
        run,
        after: const {
          RelationCorrectionField.kind: 'contradicts',
          RelationCorrectionField.note: note,
        },
      );
      final second = await proposeOn(
        made.relation,
        run,
        after: const {
          RelationCorrectionField.kind: 'cites',
          RelationCorrectionField.note: note,
        },
      );
      await suggestions.accept(first.id);

      expect(await stillApplicableCorrections(db, [second]), isEmpty);
      expect(await suggestions.accept(second.id), isA<Left<Failure, Unit>>());
      expect(
        (await relationRow(made.relation))!.kind,
        RelationKind.contradicts,
      );
    });

    test('un vínculo de estructura de la IA no se ofrece corregir', () async {
      final made = await aiRelation(kind: RelationKind.indexes);
      final correction = await proposeOn(
        made.relation,
        await reviewRun(),
        kind: 'indexes',
      );

      expect(await stillApplicableCorrections(db, [correction]), isEmpty);
      expect(
        await suggestions.accept(correction.id),
        isA<Left<Failure, Unit>>(),
      );
    });

    test('«Revisión» lo ofrece mientras sigue como lo vio el modelo, y lo '
        'saca apenas la persona lo edita', () async {
      final made = await aiRelation();
      await proposeOn(made.relation, await reviewRun());
      final queue = StreamQueue(suggestions.watchPendingCorrections());
      addTearDown(queue.cancel);

      expect((await queue.next).single.corrections, hasLength(1));

      await organize.updateRelation(
        made.relation,
        kind: RelationKind.relatedTo,
        note: 'Mía.',
      );
      expect(await queue.next, isEmpty);
    });

    test('deshacer la revisión devuelve el tipo y la frase, y olvida el «no '
        'era»', () async {
      final made = await aiRelation();
      final run = await reviewRun();
      final correction = await proposeOn(made.relation, run);
      await suggestions.accept(correction.id);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );

      final row = (await relationRow(made.relation))!;
      expect(row.kind, RelationKind.relatedTo);
      expect(row.note, 'Las dos hablan de Roma.');
      expect(row.aiRunId, made.run);
      expect(await kindRejected(RelationKind.relatedTo), isFalse);
      expect(await statusOf(correction.id), SuggestionStatus.rejected);
    });

    test('deshacer no le devuelve el tipo de antes si la persona ya hizo ese '
        'vínculo', () async {
      final made = await aiRelation();
      final run = await reviewRun();
      await suggestions.accept((await proposeOn(made.relation, run)).id);
      await organize.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.relatedTo,
      );

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(
        (await relationRow(made.relation))!.kind,
        RelationKind.contradicts,
      );
    });

    test(
      'no devuelve un vínculo sacado a un elemento que se borró del todo',
      () async {
        final made = await aiRelation();
        final run = await reviewRun();
        await suggestions.accept(
          (await proposeOn(made.relation, run, after: null)).id,
        );
        await (db.delete(
          db.knowledgeEntries,
        )..where((e) => e.id.equals('b'))).go();

        expect(
          await runs.undoRun(run),
          right<Failure, AiRunTally>(const AiRunTally()),
        );
        expect(await relationRow(made.relation), isNull);
      },
    );

    test(
      'deshacer devuelve el vínculo que sacó, si su pasada sigue en pie',
      () async {
        final made = await aiRelation();
        final run = await reviewRun();
        final correction = await proposeOn(made.relation, run, after: null);
        await suggestions.accept(correction.id);

        await runs.undoRun(run);

        final row = (await relationRow(made.relation))!;
        expect(row.kind, RelationKind.relatedTo);
        expect(row.origin, ContentOrigin.ai);
        expect(row.aiRunId, made.run);
        expect(await kindRejected(RelationKind.relatedTo), isFalse);
      },
    );

    test('no devuelve el vínculo sacado si su pasada se deshizo, ni si la '
        'persona ya hizo otro igual', () async {
      final undone = await aiRelation();
      final run = await reviewRun();
      await suggestions.accept(
        (await proposeOn(undone.relation, run, after: null)).id,
      );
      await runs.undoRun(undone.run);
      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await relationRow(undone.relation), isNull);

      final again = await aiRelation(kind: RelationKind.continues);
      final second = await reviewRun();
      await suggestions.accept(
        (await proposeOn(
          again.relation,
          second,
          kind: 'continues',
          after: null,
        )).id,
      );
      await organize.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.continues,
      );
      expect(
        await runs.undoRun(second),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await relationRow(again.relation), isNull);
    });

    test('lo que sigue en pie de la revisión cuenta el vínculo corregido '
        'hasta que la persona lo edita', () async {
      final made = await aiRelation();
      final run = await reviewRun();
      await suggestions.accept((await proposeOn(made.relation, run)).id);

      expect(await aiCorrectionCounts(db, [run]), {
        run: (created: 1, remaining: 1),
      });

      await organize.updateRelation(
        made.relation,
        kind: RelationKind.contradicts,
        note: 'Mía.',
      );
      expect(await aiCorrectionCounts(db, [run]), {
        run: (created: 1, remaining: 0),
      });
    });
  });

  group('etiquetas (F33, 4b)', () {
    late OrganizeRepositoryImpl organize;
    late String tema;

    setUp(() async {
      organize = OrganizeRepositoryImpl(
        database: db,
        telemetry: _MockTelemetryService(),
        ids: FakeIdGenerator(prefix: 'p'),
        clock: () => now,
      );
      tema = await temaDefinitionId(db);
      await insertItemRows(db, id: 'b', title: 'Cartago');
      // «Cartago» ya está en el vocabulario de «Tema»: lo puso la persona en
      // otro elemento.
      (await organize.assignProperty(
        itemId: 'b',
        definitionId: tema,
        value: 'Cartago',
      )).getOrElse((f) => fail('$f'));
    });

    Future<String> valueIdOf(String value) async => (await (db.select(
      db.propertyValues,
    )..where((v) => v.value.equals(value))).getSingle()).id;

    /// La etiqueta [value] de [definitionId] que la pasada de Gemma le puso a
    /// «a», y esa pasada.
    Future<({String run, String value})> aiTag({
      String value = 'Roma',
      String? definitionId,
    }) async {
      final run = (await runs.startRun(
        'a',
        model: 'Gemma 4 E4B',
      )).getOrElse((f) => fail('$f'));
      (await organize.assignProperty(
        itemId: 'a',
        definitionId: definitionId ?? tema,
        value: value,
        origin: ItemPropertyOrigin.ai,
        aiRunId: run,
      )).getOrElse((f) => fail('$f'));
      await runs.finishRun(run);
      return (run: run, value: await valueIdOf(value));
    }

    Future<ItemPropertyValueRow?> assignmentOf(String valueId) =>
        (db.select(db.itemPropertyValues)..where(
              (p) => p.itemId.equals('a') & p.propertyValueId.equals(valueId),
            ))
            .getSingleOrNull();

    Future<CorrectionSuggestion> proposeTag(
      String valueId,
      String run, {
      Map<String, String>? after = const {
        PropertyCorrectionField.category: kTemaCategoryName,
        PropertyCorrectionField.value: 'Cartago',
      },
      String category = kTemaCategoryName,
      String value = 'Roma',
    }) async =>
        (await suggestions.createCorrectionSuggestion(
              targetItemId: 'a',
              subject: CorrectionSubject.property,
              subjectId: propertyCorrectionSubjectId('a', valueId),
              before: {
                PropertyCorrectionField.category: category,
                PropertyCorrectionField.value: value,
              },
              after: after,
              reason: 'El texto habla de Cartago.',
              aiRunId: run,
              model: 'gemini-3.8-flash',
            )).getOrElse((f) => fail('$f'))
            as CorrectionSuggestion;

    Future<bool> tagRejected(String value) async =>
        (await runs.isPropertyRejected(
          itemId: 'a',
          definitionName: kTemaCategoryName,
          value: value,
        )).getOrElse((f) => fail('$f'));

    Future<CorrectionSuggestion> read(String id) async =>
        correctionSuggestionOf(
          await (db.select(
            db.suggestions,
          )..where((s) => s.id.equals(id))).getSingle(),
        );

    test(
      'aceptar la cambia por el valor del vocabulario —como está escrito '
      'ahí—; sigue siendo de la IA, de su pasada, y la de antes «no era»',
      () async {
        final made = await aiTag();
        final cartago = await valueIdOf('Cartago');
        final correction = await proposeTag(
          made.value,
          await reviewRun(),
          after: const {
            PropertyCorrectionField.category: kTemaCategoryName,
            PropertyCorrectionField.value: '  cartago ',
          },
        );

        expect(
          await suggestions.accept(correction.id),
          right<Failure, Unit>(unit),
        );

        expect(await assignmentOf(made.value), isNull);
        final row = (await assignmentOf(cartago))!;
        expect(row.origin, ItemPropertyOrigin.ai);
        expect(row.aiRunId, made.run);
        expect(await tagRejected('Roma'), isTrue);
        expect(await tagRejected('Cartago'), isFalse);
        expect(
          (await read(correction.id)).after![PropertyCorrectionField.value],
          'Cartago',
        );
      },
    );

    test('no inventa valores, no cambia por lo mismo, ni pone uno que el '
        'elemento ya tiene', () async {
      final made = await aiTag();
      final run = await reviewRun();
      for (final value in ['Atenas', 'roma', '']) {
        final correction = await proposeTag(
          made.value,
          run,
          after: {
            PropertyCorrectionField.category: kTemaCategoryName,
            PropertyCorrectionField.value: value,
          },
        );
        expect(
          await suggestions.accept(correction.id),
          isA<Left<Failure, Unit>>(),
          reason: value,
        );
      }

      (await organize.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Cartago',
      )).getOrElse((f) => fail('$f'));
      final twin = await proposeTag(made.value, run);
      expect(await suggestions.accept(twin.id), isA<Left<Failure, Unit>>());

      expect((await assignmentOf(made.value))!.origin, ItemPropertyOrigin.ai);
      expect(await tagRejected('Roma'), isFalse);
    });

    test('una que no es de texto no se corrige, pero se puede sacar', () async {
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'paginas',
              name: 'Páginas',
              createdAt: now,
              type: const Value(PropertyValueType.number),
            ),
          );
      // «310» existe: no es por inventarlo que no se corrige.
      (await organize.assignProperty(
        itemId: 'b',
        definitionId: 'paginas',
        value: '310',
      )).getOrElse((f) => fail('$f'));
      final made = await aiTag(value: '320', definitionId: 'paginas');
      final run = await reviewRun();

      final fix = await proposeTag(
        made.value,
        run,
        category: 'Páginas',
        value: '320',
        after: const {
          PropertyCorrectionField.category: 'Páginas',
          PropertyCorrectionField.value: '310',
        },
      );
      expect(await suggestions.accept(fix.id), isA<Left<Failure, Unit>>());
      expect(await assignmentOf(made.value), isNotNull);

      final remove = await proposeTag(
        made.value,
        run,
        category: 'Páginas',
        value: '320',
        after: null,
      );
      expect(await suggestions.accept(remove.id), right<Failure, Unit>(unit));
      expect(await assignmentOf(made.value), isNull);
    });

    test('sacarla la saca del elemento y recuerda que «no era»; el valor '
        'sigue en el vocabulario', () async {
      final made = await aiTag();
      final correction = await proposeTag(
        made.value,
        await reviewRun(),
        after: null,
      );

      await suggestions.accept(correction.id);

      expect(await assignmentOf(made.value), isNull);
      expect(await tagRejected('Roma'), isTrue);
      expect(await valueIdOf('Roma'), made.value);
    });

    test('no toca una que la persona hizo suya, una que cambió, ni una que '
        'ya no está', () async {
      final made = await aiTag();
      final run = await reviewRun();

      final stale = await proposeTag(made.value, run, value: 'Atenas');
      expect(await suggestions.accept(stale.id), isA<Left<Failure, Unit>>());

      final adopted = await proposeTag(made.value, run);
      (await organize.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Roma',
      )).getOrElse((f) => fail('$f'));
      expect(await suggestions.accept(adopted.id), isA<Left<Failure, Unit>>());
      expect(
        (await assignmentOf(made.value))!.origin,
        ItemPropertyOrigin.manual,
      );

      final gone = await proposeTag(made.value, run);
      await organize.removeItemProperty(
        itemId: 'a',
        propertyValueId: made.value,
      );
      expect(await suggestions.accept(gone.id), isA<Left<Failure, Unit>>());
    });

    test(
      'la que puso la nota mapa es parte de la nota: no se ofrece',
      () async {
        final made = await aiTag();
        await db
            .into(db.aiFieldChanges)
            .insert(
              AiFieldChangesCompanion.insert(
                id: 'nota',
                aiRunId: made.run,
                field: AiChangedField.mapNote,
                afterValue: made.value,
              ),
            );
        final correction = await proposeTag(made.value, await reviewRun());

        expect(await stillApplicableCorrections(db, [correction]), isEmpty);
        expect(
          await suggestions.accept(correction.id),
          isA<Left<Failure, Unit>>(),
        );
      },
    );

    test('«Revisión» la ofrece hasta que la persona la saca', () async {
      final made = await aiTag();
      await proposeTag(made.value, await reviewRun());
      final queue = StreamQueue(suggestions.watchPendingCorrections());
      addTearDown(queue.cancel);

      expect((await queue.next).single.corrections, hasLength(1));

      await organize.removeItemProperty(
        itemId: 'a',
        propertyValueId: made.value,
      );
      expect(await queue.next, isEmpty);
    });

    test(
      'y la saca si la persona renombra el valor en el vocabulario',
      () async {
        final made = await aiTag();
        await proposeTag(made.value, await reviewRun());
        final queue = StreamQueue(suggestions.watchPendingCorrections());
        addTearDown(queue.cancel);

        expect((await queue.next).single.corrections, hasLength(1));

        (await organize.renamePropertyValue(
          id: made.value,
          label: 'Roma antigua',
        )).getOrElse((f) => fail('$f'));
        expect(await queue.next, isEmpty);
      },
    );

    test('deshacer la revisión vuelve al valor de antes y olvida el «no '
        'era»', () async {
      final made = await aiTag();
      final cartago = await valueIdOf('Cartago');
      final run = await reviewRun();
      final correction = await proposeTag(made.value, run);
      await suggestions.accept(correction.id);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );

      expect(await assignmentOf(cartago), isNull);
      final row = (await assignmentOf(made.value))!;
      expect(row.origin, ItemPropertyOrigin.ai);
      expect(row.aiRunId, made.run);
      expect(await tagRejected('Roma'), isFalse);
      expect(await statusOf(correction.id), SuggestionStatus.rejected);
    });

    test(
      'deshacer la revisión no pisa lo que la persona cambió después: ni '
      'la corregida que sacó, ni el valor de antes que puso a mano',
      () async {
        final made = await aiTag();
        final cartago = await valueIdOf('Cartago');
        final run = await reviewRun();
        await suggestions.accept((await proposeTag(made.value, run)).id);
        await organize.removeItemProperty(
          itemId: 'a',
          propertyValueId: cartago,
        );

        expect(
          await runs.undoRun(run),
          right<Failure, AiRunTally>(const AiRunTally()),
        );
        expect(await assignmentOf(made.value), isNull);

        final again = await aiTag(value: 'Útica');
        final second = await reviewRun();
        await suggestions.accept(
          (await proposeTag(again.value, second, value: 'Útica')).id,
        );
        (await organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Útica',
        )).getOrElse((f) => fail('$f'));
        expect(
          await runs.undoRun(second),
          right<Failure, AiRunTally>(const AiRunTally()),
        );
        expect(
          (await assignmentOf(again.value))!.origin,
          ItemPropertyOrigin.manual,
        );
        expect((await assignmentOf(cartago))!.origin, ItemPropertyOrigin.ai);
      },
    );

    test(
      'deshacer la pasada que la puso se lleva también la corregida',
      () async {
        final made = await aiTag();
        final cartago = await valueIdOf('Cartago');
        final run = await reviewRun();
        await suggestions.accept((await proposeTag(made.value, run)).id);

        await runs.undoRun(made.run);

        expect(await assignmentOf(cartago), isNull);
        expect(await assignmentOf(made.value), isNull);
        expect(
          await runs.undoRun(run),
          right<Failure, AiRunTally>(const AiRunTally()),
        );
        expect(await assignmentOf(made.value), isNull);
      },
    );

    test('deshacer devuelve la que sacó si su pasada sigue en pie, y no si se '
        'deshizo', () async {
      final made = await aiTag();
      final run = await reviewRun();
      await suggestions.accept(
        (await proposeTag(made.value, run, after: null)).id,
      );

      await runs.undoRun(run);

      final row = (await assignmentOf(made.value))!;
      expect(row.origin, ItemPropertyOrigin.ai);
      expect(row.aiRunId, made.run);
      expect(await tagRejected('Roma'), isFalse);

      final again = await aiTag(value: 'Útica');
      final second = await reviewRun();
      await suggestions.accept(
        (await proposeTag(again.value, second, value: 'Útica', after: null)).id,
      );
      await runs.undoRun(again.run);
      expect(
        await runs.undoRun(second),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await assignmentOf(again.value), isNull);
    });

    test(
      'no devuelve la sacada si la persona la volvió a poner a mano',
      () async {
        final made = await aiTag();
        final run = await reviewRun();
        await suggestions.accept(
          (await proposeTag(made.value, run, after: null)).id,
        );
        (await organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Roma',
        )).getOrElse((f) => fail('$f'));

        expect(
          await runs.undoRun(run),
          right<Failure, AiRunTally>(const AiRunTally()),
        );
        expect(
          (await assignmentOf(made.value))!.origin,
          ItemPropertyOrigin.manual,
        );
      },
    );

    test('lo que sigue en pie cuenta la corregida —que es otra fila— hasta '
        'que la persona la hace suya', () async {
      final made = await aiTag();
      final run = await reviewRun();
      await suggestions.accept((await proposeTag(made.value, run)).id);

      expect(await aiCorrectionCounts(db, [run]), {
        run: (created: 1, remaining: 1),
      });

      (await organize.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Cartago',
      )).getOrElse((f) => fail('$f'));
      expect(await aiCorrectionCounts(db, [run]), {
        run: (created: 1, remaining: 0),
      });
    });
  });

  group('tema (F33, 4b)', () {
    late KnowledgeEntryWriter writer;

    setUp(() async {
      writer = KnowledgeEntryWriter(
        db,
        clock: () => now,
        ids: FakeIdGenerator(prefix: 'w'),
      );
      for (final (id, name) in [('historia', 'Historia'), ('arte', 'Arte')]) {
        await db
            .into(db.spaces)
            .insert(SpacesCompanion.insert(id: id, name: name, createdAt: now));
      }
    });

    /// La pasada de Gemma que puso «a» en «Historia», y lo que recuerda de
    /// eso.
    Future<({String run, String change})> aiSpace() async {
      final run = (await runs.startRun(
        'a',
        model: 'Gemma 4 E4B',
      )).getOrElse((f) => fail('$f'));
      expect(
        await runs.applySpace(runId: run, itemId: 'a', spaceId: 'historia'),
        right<Failure, bool>(true),
      );
      await runs.finishRun(run);
      final change =
          await (db.select(db.aiFieldChanges)..where(
                (c) =>
                    c.aiRunId.equals(run) &
                    c.field.equalsValue(AiChangedField.space),
              ))
              .getSingle();
      return (run: run, change: change.id);
    }

    Future<Set<String>> spacesOfA() => spaceRowsOf(db, 'a');

    Future<CorrectionSuggestion> proposeSpace(
      String change,
      String run, {
      Map<String, String>? after = const {
        SpaceCorrectionField.id: 'arte',
        SpaceCorrectionField.name: 'Arte',
      },
      String before = 'historia',
    }) async =>
        (await suggestions.createCorrectionSuggestion(
              targetItemId: 'a',
              subject: CorrectionSubject.space,
              subjectId: change,
              before: {
                SpaceCorrectionField.id: before,
                SpaceCorrectionField.name: 'Historia',
              },
              after: after,
              reason: 'Habla de pintura.',
              aiRunId: run,
              model: 'gemini-3.8-flash',
            )).getOrElse((f) => fail('$f'))
            as CorrectionSuggestion;

    test('aceptar lo cambia de tema y sigue siendo de la IA: deshacer la '
        'pasada que lo puso lo deja sin tema, como estaba', () async {
      final made = await aiSpace();
      final correction = await proposeSpace(made.change, await reviewRun());

      expect(
        await suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );
      expect(await spacesOfA(), {'arte'});

      await runs.undoRun(made.run);
      expect(await spacesOfA(), isEmpty);
    });

    test('corregirlo cambia solo el de la IA: el tema que sumó la persona '
        'queda al aceptar, al deshacer la revisión y al deshacer la pasada '
        '(F37)', () async {
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: 'ciencia',
              name: 'Ciencia',
              createdAt: now,
            ),
          );
      final made = await aiSpace();
      await writer.addSpaces(['a'], {'ciencia'});
      final run = await reviewRun();
      final correction = await proposeSpace(made.change, run);

      expect(
        await suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );
      expect(await spacesOfA(), {'ciencia', 'arte'});

      await runs.undoRun(run);
      expect(await spacesOfA(), {'ciencia', 'historia'});

      await runs.undoRun(made.run);
      expect(await spacesOfA(), {'ciencia'});
    });

    test('sacarlo saca solo el de la IA (F37)', () async {
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: 'ciencia',
              name: 'Ciencia',
              createdAt: now,
            ),
          );
      final made = await aiSpace();
      await writer.addSpaces(['a'], {'ciencia'});
      await suggestions.accept(
        (await proposeSpace(made.change, await reviewRun(), after: null)).id,
      );

      expect(await spacesOfA(), {'ciencia'});
    });

    test('no lo pone en un tema que no existe ni en el mismo, ni en uno que '
        'cambió desde la revisión', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      for (final id in ['nada', 'historia']) {
        final correction = await proposeSpace(
          made.change,
          run,
          after: {SpaceCorrectionField.id: id, SpaceCorrectionField.name: id},
        );
        expect(
          await suggestions.accept(correction.id),
          isA<Left<Failure, Unit>>(),
          reason: id,
        );
      }
      final stale = await proposeSpace(made.change, run, before: 'arte');
      expect(await suggestions.accept(stale.id), isA<Left<Failure, Unit>>());
      expect(await spacesOfA(), {'historia'});
    });

    test('no toca el tema que la persona cambió', () async {
      final made = await aiSpace();
      final correction = await proposeSpace(made.change, await reviewRun());
      await writer.setSpaces(['a'], const {});

      expect(await stillApplicableCorrections(db, [correction]), isEmpty);
      expect(
        await suggestions.accept(correction.id),
        isA<Left<Failure, Unit>>(),
      );
      expect(await spacesOfA(), isEmpty);
    });

    test(
      'ni el que la persona eligió, aunque sea el que vio el modelo',
      () async {
        final made = await aiSpace();
        await writer.setSpaces(['a'], {'arte'});
        // Lo que vio el modelo es lo de hoy, pero ya no es lo que puso la IA.
        final correction = await proposeSpace(
          made.change,
          await reviewRun(),
          before: 'arte',
          after: const {
            SpaceCorrectionField.id: 'historia',
            SpaceCorrectionField.name: 'Historia',
          },
        );

        expect(await stillApplicableCorrections(db, [correction]), isEmpty);
        expect(
          await suggestions.accept(correction.id),
          isA<Left<Failure, Unit>>(),
        );
        expect(await spacesOfA(), {'arte'});
      },
    );

    test('ni el de una pasada que ya se deshizo', () async {
      final made = await aiSpace();
      final correction = await proposeSpace(made.change, await reviewRun());
      await runs.undoRun(made.run);
      await writer.setSpaces(['a'], {'historia'});

      expect(
        await suggestions.accept(correction.id),
        isA<Left<Failure, Unit>>(),
      );
      expect(await spacesOfA(), {'historia'});
    });

    test('sacarlo lo deja sin tema; deshacer la revisión lo vuelve a poner, y '
        'sigue siendo de la IA', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      final correction = await proposeSpace(made.change, run, after: null);

      await suggestions.accept(correction.id);
      expect(await spacesOfA(), isEmpty);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );
      expect(await spacesOfA(), {'historia'});
      await runs.undoRun(made.run);
      expect(await spacesOfA(), isEmpty);
    });

    test('deshacer la revisión que lo corrigió lo devuelve al de antes, y la '
        'pasada que lo puso lo sigue reconociendo', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      final correction = await proposeSpace(made.change, run);
      await suggestions.accept(correction.id);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );
      expect(await spacesOfA(), {'historia'});
      expect(await statusOf(correction.id), SuggestionStatus.rejected);

      await runs.undoRun(made.run);
      expect(await spacesOfA(), isEmpty);
    });

    test('deshacer devuelve el sacado junto al tema que la persona sumó '
        'después, sin pisarlo (F37)', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      await suggestions.accept(
        (await proposeSpace(made.change, run, after: null)).id,
      );
      await writer.setSpaces(['a'], {'arte'});

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally(corrections: 1)),
      );
      expect(await spacesOfA(), {'arte', 'historia'});
    });

    test('si la persona lo volvió a poner, deshacer no tiene nada que '
        'devolver', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      await suggestions.accept(
        (await proposeSpace(made.change, run, after: null)).id,
      );
      await writer.setSpaces(['a'], {'historia', 'arte'});

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await spacesOfA(), {'historia', 'arte'});
    });

    test('el sacado no vuelve si la pasada que lo puso se deshizo', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      await suggestions.accept(
        (await proposeSpace(made.change, run, after: null)).id,
      );
      await runs.undoRun(made.run);

      expect(
        await runs.undoRun(run),
        right<Failure, AiRunTally>(const AiRunTally()),
      );
      expect(await spacesOfA(), isEmpty);
    });

    test(
      '«Revisión» lo ofrece hasta que la persona le cambia el tema',
      () async {
        final made = await aiSpace();
        final run = await reviewRun();
        await proposeSpace(made.change, run);
        final queue = StreamQueue(suggestions.watchPendingCorrections());
        addTearDown(queue.cancel);

        expect((await queue.next).single.corrections, hasLength(1));
        await writer.setSpaces(['a'], {'arte'});
        expect(await queue.next, isEmpty);
      },
    );

    test('lo que sigue en pie cuenta el tema corregido hasta que la persona '
        'lo cambia', () async {
      final made = await aiSpace();
      final run = await reviewRun();
      await suggestions.accept((await proposeSpace(made.change, run)).id);

      expect(await aiCorrectionCounts(db, [run]), {
        run: (created: 1, remaining: 1),
      });

      await writer.setSpaces(['a'], {'historia'});
      expect(await aiCorrectionCounts(db, [run]), {
        run: (created: 1, remaining: 0),
      });
    });
  });
}
