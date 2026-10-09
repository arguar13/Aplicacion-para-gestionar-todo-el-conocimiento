import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_form.dart';
import 'package:sinapsis/features/flashcards/domain/usecases/create_cards_from_form_usecase.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Cada forma del formulario se guarda como la tarjeta (o las tarjetas) que le
/// toca (F31, decisión 73), enteras o ninguna.
void main() {
  late AppDatabase db;
  late CreateCardsFromFormUseCase create;
  final now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    create = CreateCardsFromFormUseCase(
      FlashcardRepositoryImpl(
        database: db,
        telemetry: _MockTelemetry(),
        ids: FakeIdGenerator(),
        clock: () => now,
      ),
    );
    await insertItemRows(db, id: 'item', title: 'Un elemento');
  });

  tearDown(() => db.close());

  Future<List<FlashcardRow>> cards() => (db.select(
    db.flashcards,
  )..orderBy([(f) => OrderingTerm(expression: f.createdAt)])).get();

  test('pregunta y respuesta: una tarjeta libre', () async {
    final result = await create(
      itemId: 'item',
      form: const QaCardForm(front: ' P ', back: ' R '),
    );

    expect(result.getRight().toNullable(), hasLength(1));
    final row = (await cards()).single;
    expect(row.kind, FlashcardKind.freeRecall);
    expect(row.front, 'P');
    expect(row.back, 'R');
    expect(row.groupId, isNull);
  });

  test(
    'dos direcciones: dos tarjetas hermanas con los lados cambiados',
    () async {
      final result = await create(
        itemId: 'item',
        form: const BothDirectionsCardForm(front: 'Francia', back: 'París'),
      );

      expect(result.getRight().toNullable(), hasLength(2));
      final rows = await cards();
      expect(rows, hasLength(2));
      expect(
        {for (final r in rows) '${r.front}>${r.back}'},
        {'Francia>París', 'París>Francia'},
      );
      expect(rows[0].groupId, isNotNull);
      expect(rows[0].groupId, rows[1].groupId);
    },
  );

  test(
    'huecos: una tarjeta por número, hermanas, con el texto entero',
    () async {
      const text = 'El {{c1::Imperio}} cayó en {{c2::476}} y {{c1::terminó}}';
      final result = await create(
        itemId: 'item',
        form: const ClozeCardForm(text: text, extra: 'Occidente'),
      );

      expect(result.getRight().toNullable(), hasLength(2));
      final rows = await (db.select(
        db.flashcards,
      )..orderBy([(f) => OrderingTerm(expression: f.clozeIndex)])).get();
      expect(rows.map((r) => r.clozeIndex), [1, 2]);
      expect(rows.every((r) => r.kind == FlashcardKind.cloze), isTrue);
      expect(rows.every((r) => r.front == text), isTrue);
      expect(rows.every((r) => r.back == 'Occidente'), isTrue);
      expect(rows[0].groupId, rows[1].groupId);
      expect(rows[0].groupId, isNotNull);
    },
  );

  test('huecos con un solo número: una tarjeta suelta, sin grupo', () async {
    final result = await create(
      itemId: 'item',
      form: const ClozeCardForm(text: 'Roma cayó en {{c1::476}}'),
      sourceCharStart: 3,
      sourceCharEnd: 20,
    );

    expect(result.getRight().toNullable(), hasLength(1));
    final row = (await cards()).single;
    expect(row.clozeIndex, 1);
    expect(row.groupId, isNull);
    expect(row.back, isEmpty);
    expect(row.sourceCharStart, 3);
    expect(row.sourceCharEnd, 20);
  });

  test(
    'huecos con el rango de la fuente: todas las hermanas lo llevan',
    () async {
      await create(
        itemId: 'item',
        form: const ClozeCardForm(text: '{{c1::A}} y {{c2::B}}'),
        sourceCharStart: 5,
        sourceCharEnd: 30,
      );

      final rows = await cards();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.sourceCharStart == 5), isTrue);
      expect(rows.every((r) => r.sourceCharEnd == 30), isTrue);
    },
  );

  test('huecos mal escritos o sin huecos: no guarda nada', () async {
    for (final text in ['Sin huecos', 'Uno {{c1::roto', 'Vacío {{c1::}}']) {
      final result = await create(
        itemId: 'item',
        form: ClozeCardForm(text: text),
      );
      expect(result.isLeft(), isTrue, reason: text);
    }
    expect(await cards(), isEmpty);
  });

  test(
    '«escribí la respuesta»: la respuesta y sus alternativas en back',
    () async {
      final result = await create(
        itemId: 'item',
        form: const TypedCardForm(
          front: '¿Capital de Italia?',
          answer: 'Roma',
          alternatives: ['La Urbe', 'roma', ' '],
        ),
      );

      expect(result.getRight().toNullable(), hasLength(1));
      final row = (await cards()).single;
      expect(row.kind, FlashcardKind.typedAnswer);
      expect(row.back, 'Roma\nLa Urbe');
    },
  );

  test('opción múltiple: la correcta y los distractores, en orden', () async {
    final result = await create(
      itemId: 'item',
      form: const MultipleChoiceCardForm(
        question: '¿Capital de Italia?',
        correct: 'Roma',
        distractors: ['Milán', 'Turín'],
      ),
    );

    final card = result.getRight().toNullable()!.single;
    expect(card.kind, FlashcardKind.multipleChoice);
    final options = await (db.select(
      db.flashcardOptions,
    )..orderBy([(o) => OrderingTerm(expression: o.position)])).get();
    expect(options.map((o) => o.content), ['Roma', 'Milán', 'Turín']);
    expect(options.map((o) => o.isCorrect), [true, false, false]);
  });

  test('opción múltiple sin distractores no se guarda', () async {
    final result = await create(
      itemId: 'item',
      form: const MultipleChoiceCardForm(
        question: 'P',
        correct: 'R',
        distractors: [],
      ),
    );

    expect(result.isLeft(), isTrue);
    expect(await cards(), isEmpty);
  });
}
