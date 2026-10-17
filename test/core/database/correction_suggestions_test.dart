import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Unit, right, unit;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
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
  final now = DateTime(2026, 10, 17, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
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
}
