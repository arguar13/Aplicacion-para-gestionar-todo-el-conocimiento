import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show right;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Las tarjetas que hizo la IA (F27): editarlas las adopta, «no era» las
/// borra y recuerda su pregunta, y deshacerlo las devuelve enteras.
void main() {
  late AppDatabase db;
  late FlashcardRepositoryImpl repository;
  late AiRunRepositoryImpl runs;
  final now = DateTime(2026, 10, 2, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = FakeIdGenerator();
    repository = FlashcardRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    runs = AiRunRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    await insertItemRows(db, id: 'a', title: 'Un elemento');
  });

  tearDown(() => db.close());

  Future<String> startRun() async =>
      (await runs.startRun('a')).getOrElse((f) => fail('$f'));

  Future<String> aiCard({String front = '¿Qué es la entropía?'}) async {
    final run = await startRun();
    final created = await repository.create(
      itemId: 'a',
      front: front,
      back: 'Una medida del desorden.',
      ai: AiProvenance(runId: run),
    );
    return created.getOrElse((f) => fail('$f')).id;
  }

  test('una de la IA queda marcada, con su pasada', () async {
    final id = await aiCard();

    final card = (await repository.watchForItem('a').first).single;
    expect(card.id, id);
    expect(card.origin, ContentOrigin.ai);
    expect(card.isFromAi, isTrue);
    expect(card.aiRunId, isNotNull);
  });

  test('una a mano sigue siendo de la persona', () async {
    final created = await repository.create(
      itemId: 'a',
      front: 'Pregunta',
      back: 'Respuesta',
    );

    final card = created.getOrElse((f) => fail('$f'));
    expect(card.origin, ContentOrigin.user);
    expect(card.aiRunId, isNull);
  });

  test('editarla la adopta y no le toca el calendario', () async {
    final id = await aiCard();
    await repository.review(id: id, grade: ReviewGrade.good);
    final before = (await repository.watchForItem('a').first).single;

    final updated = await repository.update(
      id: id,
      front: '¿Qué mide la entropía?',
      back: 'El desorden de un sistema.',
    );

    final card = updated.getOrElse((f) => fail('$f'));
    expect(card.front, '¿Qué mide la entropía?');
    expect(card.origin, ContentOrigin.user);
    expect(card.aiRunId, isNull);
    expect(card.dueAt, before.dueAt);
    expect(card.repetitions, before.repetitions);
  });

  group('«no era»', () {
    test(
      'la borra, recuerda su pregunta y la IA no la vuelve a crear',
      () async {
        final id = await aiCard();

        final result = await repository.rejectAiFlashcard(id);

        expect(result.isRight(), isTrue);
        expect(await db.select(db.flashcards).get(), isEmpty);
        expect(
          await runs.isFlashcardRejected(
            itemId: 'a',
            question: 'que es la entropia',
          ),
          right<Failure, bool>(true),
        );
        final run = await startRun();
        final again = await repository.create(
          itemId: 'a',
          front: '¿QUÉ es la entropía?',
          back: 'Otra respuesta',
          ai: AiProvenance(runId: run),
        );
        final multipleChoice = await repository.createMultipleChoice(
          itemId: 'a',
          front: 'Qué es la entropía',
          options: const [
            FlashcardOptionDraft(content: 'Desorden', isCorrect: true),
            FlashcardOptionDraft(content: 'Orden', isCorrect: false),
          ],
          ai: AiProvenance(runId: run),
        );
        expect(again.getLeft().toNullable(), isA<ValidationFailure>());
        expect(multipleChoice.getLeft().toNullable(), isA<ValidationFailure>());
        expect(await db.select(db.flashcards).get(), isEmpty);

        // La persona, en cambio, la puede escribir igual.
        final byHand = await repository.create(
          itemId: 'a',
          front: '¿Qué es la entropía?',
          back: 'La mía',
        );
        expect(byHand.isRight(), isTrue);
      },
    );

    test('una de la persona no se rechaza: se borra', () async {
      final created = await repository.create(
        itemId: 'a',
        front: 'Mía',
        back: 'Sí',
      );

      final result = await repository.rejectAiFlashcard(
        created.getOrElse((f) => fail('$f')).id,
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await db.select(db.flashcards).get(), hasLength(1));
    });

    test(
      'deshacerlo la devuelve entera: calendario, opciones y repasos',
      () async {
        final run = await startRun();
        final card = (await repository.createMultipleChoice(
          itemId: 'a',
          front: '¿Qué es la entropía?',
          options: const [
            FlashcardOptionDraft(content: 'Desorden', isCorrect: true),
            FlashcardOptionDraft(content: 'Orden', isCorrect: false),
          ],
          ai: AiProvenance(runId: run),
        )).getOrElse((f) => fail('$f'));
        await repository.review(id: card.id, grade: ReviewGrade.easy);
        final cardBefore = await db.select(db.flashcards).getSingle();
        final optionsBefore = await db.select(db.flashcardOptions).get();
        final reviewsBefore = await db.select(db.reviewLogs).get();
        expect(optionsBefore, hasLength(2));
        expect(reviewsBefore, hasLength(1));

        final receipt = (await repository.rejectAiFlashcard(
          card.id,
        )).getOrElse((f) => fail('$f'));
        expect(await db.select(db.flashcardOptions).get(), isEmpty);
        final restored = await repository.restoreRejectedFlashcard(receipt);

        expect(restored.isRight(), isTrue);
        expect(await db.select(db.flashcards).getSingle(), cardBefore);
        expect(await db.select(db.flashcardOptions).get(), optionsBefore);
        expect(await db.select(db.reviewLogs).get(), reviewsBefore);
        expect(await db.select(db.aiRejections).get(), isEmpty);
      },
    );
  });
}
