import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/cloze_card_editor_impl.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/sibling_card_draft.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Editar el texto de una tarjeta de huecos (F31, decisión 73): las hermanas
/// de un texto se reconcilian en una transacción, cada hueco que sigue
/// conserva su calendario.
void main() {
  late AppDatabase db;
  late FlashcardRepositoryImpl repository;
  late ClozeCardEditorImpl editor;
  final now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ids = FakeIdGenerator();
    repository = FlashcardRepositoryImpl(
      database: db,
      telemetry: _MockTelemetry(),
      ids: ids,
      clock: () => now,
    );
    editor = ClozeCardEditorImpl(
      database: db,
      telemetry: _MockTelemetry(),
      ids: ids,
      clock: () => now,
    );
    await insertItemRows(db, id: 'item', title: 'Un elemento');
  });

  tearDown(() => db.close());

  const original = 'El {{c1::Imperio romano}} cayó en {{c2::476}}';

  Future<List<FlashcardRow>> allCards() => (db.select(
    db.flashcards,
  )..orderBy([(f) => OrderingTerm(expression: f.clozeIndex)])).get();

  Future<List<FlashcardRow>> createGroup() async {
    final created = await repository.createSiblings(
      itemId: 'item',
      drafts: SiblingCardDraft.clozes(
        text: original,
        clozeNumbers: [1, 2],
        extra: 'Occidente',
      ),
    );
    expect(created.isRight(), isTrue, reason: '$created');
    return allCards();
  }

  test('cambiar el texto sin tocar los huecos actualiza a todas las hermanas '
      'y no toca su calendario', () async {
    final cards = await createGroup();
    // La hermana 2 ya se repasó: su calendario no puede perderse.
    await repository.review(id: cards[1].id, grade: ReviewGrade.good);
    final before = (await allCards())[1];

    final result = await editor.edit(
      cardId: cards[0].id,
      text: 'El {{c1::Imperio romano de Occidente}} cayó en {{c2::476}}',
      extra: 'Nuevo complemento',
    );

    final outcome = result.getRight().toNullable()!;
    expect(outcome.updated, 2);
    expect(outcome.created, 0);
    expect(outcome.removed, 0);
    final after = await allCards();
    expect(after, hasLength(2));
    for (final card in after) {
      expect(card.front, contains('de Occidente'));
      expect(card.back, 'Nuevo complemento');
      expect(card.groupId, cards[0].groupId);
    }
    expect(after[1].dueAt, before.dueAt);
    expect(after[1].intervalDays, before.intervalDays);
    expect(after[1].repetitions, before.repetitions);
    expect(after[1].lastReviewedAt, before.lastReviewedAt);
  });

  test('un hueco nuevo suma una tarjeta al mismo grupo', () async {
    final cards = await createGroup();

    final result = await editor.edit(
      cardId: cards[0].id,
      text: '$original en el año {{c3::medieval}}',
      extra: '',
    );

    final outcome = result.getRight().toNullable()!;
    expect(outcome.created, 1);
    expect(outcome.updated, 2);
    final after = await allCards();
    expect(after.map((c) => c.clozeIndex), [1, 2, 3]);
    expect({for (final c in after) c.groupId}, {cards[0].groupId});
    expect(after.every((c) => c.front.contains('{{c3::medieval}}')), isTrue);
  });

  test('sacar un hueco borra su tarjeta y deja las otras', () async {
    final cards = await createGroup();

    final result = await editor.edit(
      cardId: cards[0].id,
      text: 'El {{c1::Imperio romano}} cayó en 476',
      extra: '',
    );

    final outcome = result.getRight().toNullable()!;
    expect(outcome.removed, 1);
    expect(outcome.updated, 1);
    final after = await allCards();
    expect(after, hasLength(1));
    expect(after.single.clozeIndex, 1);
    expect(after.single.front, 'El {{c1::Imperio romano}} cayó en 476');
  });

  test('editar adopta una tarjeta que hizo la IA', () async {
    final cards = await createGroup();
    await db
        .update(db.flashcards)
        .write(const FlashcardsCompanion(origin: Value(ContentOrigin.ai)));

    await editor.edit(cardId: cards[0].id, text: original, extra: 'x');

    final after = await allCards();
    expect(after.every((c) => c.origin == ContentOrigin.user), isTrue);
  });

  test(
    'una tarjeta suelta que gana huecos forma grupo con las nuevas',
    () async {
      final single = (await repository.create(
        itemId: 'item',
        front: 'El {{c1::Imperio}} cayó',
        back: '',
        kind: FlashcardKind.cloze,
        clozeIndex: 1,
      )).getRight().toNullable()!;
      expect(single.groupId, isNull);

      await editor.edit(
        cardId: single.id,
        text: 'El {{c1::Imperio}} cayó en {{c2::476}}',
        extra: '',
      );

      final after = await allCards();
      expect(after, hasLength(2));
      expect(after[0].groupId, isNotNull);
      expect(after[0].groupId, after[1].groupId);
    },
  );

  test('un texto sin huecos se rechaza sin tocar nada', () async {
    final cards = await createGroup();

    final result = await editor.edit(
      cardId: cards[0].id,
      text: 'Un texto sin huecos',
      extra: '',
    );

    expect(result.isLeft(), isTrue);
    final after = await allCards();
    expect(after, hasLength(2));
    expect(after.every((c) => c.front == original), isTrue);
  });

  test('una tarjeta que no es de huecos se rechaza', () async {
    final card = (await repository.create(
      itemId: 'item',
      front: 'P',
      back: 'R',
    )).getRight().toNullable()!;

    final result = await editor.edit(
      cardId: card.id,
      text: original,
      extra: '',
    );

    expect(result.isLeft(), isTrue);
    expect((await allCards()).single.front, 'P');
  });

  test('una tarjeta que ya no existe se rechaza', () async {
    final result = await editor.edit(
      cardId: 'no-existe',
      text: original,
      extra: '',
    );
    expect(result.isLeft(), isTrue);
  });
}
