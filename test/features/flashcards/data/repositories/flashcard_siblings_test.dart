import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/sibling_card_draft.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Las formas nuevas de tarjeta y las hermanas (F31, decisión 69): huecos,
/// «escribí la respuesta» y grupos de tarjetas que se crean juntas.
void main() {
  late AppDatabase db;
  late FlashcardRepositoryImpl repository;
  final now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = FlashcardRepositoryImpl(
      database: db,
      telemetry: _MockTelemetry(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    await insertItemRows(db, id: 'item', title: 'Un elemento');
  });

  tearDown(() => db.close());

  const cloze = 'El {{c1::Imperio romano}} cayó en {{c2::476}}';

  test(
    'una tarjeta de huecos guarda el texto entero y cuál hueco tapa',
    () async {
      final result = await repository.create(
        itemId: 'item',
        front: cloze,
        back: '',
        kind: FlashcardKind.cloze,
        clozeIndex: 2,
      );

      final card = result.getRight().toNullable()!;
      expect(card.kind, FlashcardKind.cloze);
      expect(card.front, cloze);
      expect(card.back, isEmpty);
      expect(card.clozeIndex, 2);
      final stored = await db.select(db.flashcards).getSingle();
      expect(stored.kind, FlashcardKind.cloze);
      expect(stored.clozeIndex, 2);
    },
  );

  test(
    'una de huecos exige el número de hueco; las demás formas, no',
    () async {
      Future<bool> rejected({
        required FlashcardKind kind,
        int? clozeIndex,
        String back = 'R',
      }) async => (await repository.create(
        itemId: 'item',
        front: cloze,
        back: back,
        kind: kind,
        clozeIndex: clozeIndex,
      )).isLeft();

      expect(await rejected(kind: FlashcardKind.cloze, back: ''), isTrue);
      expect(
        await rejected(kind: FlashcardKind.cloze, clozeIndex: 0, back: ''),
        isTrue,
      );
      expect(
        await rejected(kind: FlashcardKind.freeRecall, clozeIndex: 1),
        isTrue,
      );
      expect(await db.select(db.flashcards).get(), isEmpty);
    },
  );

  test(
    '«escribí la respuesta» necesita la respuesta con la que comparar',
    () async {
      final ok = await repository.create(
        itemId: 'item',
        front: '¿Año de la caída?',
        back: '476',
        kind: FlashcardKind.typedAnswer,
      );
      final empty = await repository.create(
        itemId: 'item',
        front: '¿Año de la caída?',
        back: '',
        kind: FlashcardKind.typedAnswer,
      );

      expect(ok.getRight().toNullable()!.kind, FlashcardKind.typedAnswer);
      expect(empty.isLeft(), isTrue);
    },
  );

  test('todas las formas se repasan con el mismo calendario', () async {
    final card = (await repository.create(
      itemId: 'item',
      front: cloze,
      back: '',
      kind: FlashcardKind.cloze,
      clozeIndex: 1,
    )).getRight().toNullable()!;

    final reviewed = (await repository.review(
      id: card.id,
      grade: ReviewGrade.good,
    )).getRight().toNullable()!;

    expect(reviewed.learningStep, 1);
    expect(reviewed.dueAt, now.add(const Duration(minutes: 10)));
  });

  group('createSiblings', () {
    test('las dos direcciones: ida y vuelta, con el mismo grupo', () async {
      final result = await repository.createSiblings(
        itemId: 'item',
        drafts: SiblingCardDraft.bothDirections(
          front: '¿Capital de Italia?',
          back: 'Roma',
        ),
      );

      final cards = result.getRight().toNullable()!;
      expect(cards, hasLength(2));
      expect(cards[0].front, '¿Capital de Italia?');
      expect(cards[0].back, 'Roma');
      expect(cards[1].front, 'Roma');
      expect(cards[1].back, '¿Capital de Italia?');
      expect(cards[0].groupId, isNotNull);
      expect(cards[1].groupId, cards[0].groupId);
      expect(await db.select(db.flashcards).get(), hasLength(2));
    });

    test(
      'los huecos de un texto: uno por número, con el texto entero',
      () async {
        final result = await repository.createSiblings(
          itemId: 'item',
          drafts: SiblingCardDraft.clozes(text: cloze, clozeNumbers: [1, 2]),
        );

        final cards = result.getRight().toNullable()!;
        expect(cards.map((c) => c.clozeIndex), [1, 2]);
        expect(cards.map((c) => c.front).toSet(), {cloze});
        expect(cards.map((c) => c.kind).toSet(), {FlashcardKind.cloze});
        expect(cards.map((c) => c.groupId).toSet(), hasLength(1));
      },
    );

    test('dos grupos distintos tienen grupos distintos', () async {
      final a = (await repository.createSiblings(
        itemId: 'item',
        drafts: SiblingCardDraft.bothDirections(front: 'a', back: 'b'),
      )).getRight().toNullable()!;
      final b = (await repository.createSiblings(
        itemId: 'item',
        drafts: SiblingCardDraft.bothDirections(front: 'c', back: 'd'),
      )).getRight().toNullable()!;

      expect(a.first.groupId, isNot(b.first.groupId));
    });

    test('todas o ninguna: si una falla, no queda ninguna', () async {
      final result = await repository.createSiblings(
        itemId: 'item',
        drafts: const [
          SiblingCardDraft(front: 'Buena', back: 'Sí'),
          SiblingCardDraft(front: '   ', back: 'No'),
        ],
      );

      expect(result.isLeft(), isTrue);
      expect(await db.select(db.flashcards).get(), isEmpty);
    });

    test('un grupo de una sola no es un grupo', () async {
      final result = await repository.createSiblings(
        itemId: 'item',
        drafts: const [SiblingCardDraft(front: 'Sola', back: 'Sí')],
      );

      expect(result.isLeft(), isTrue);
      expect(await db.select(db.flashcards).get(), isEmpty);
    });
  });
}
