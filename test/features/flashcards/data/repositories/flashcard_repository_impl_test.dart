import 'package:async/async.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que hay que verificar acá es que el
/// SM-2 se aplica y se guarda bien, no solo que un doble responda lo que se
/// le pida.
///
/// Los elementos se siembran con `LibraryRepositoryImpl.save`, igual que en
/// `organize_repository_impl_test.dart`, y no con un `itemId` de texto
/// suelto: `Flashcards.itemId` referencia a `Items` con
/// `foreign_keys = ON` de verdad, así que un `itemId` inventado hace que el
/// insert falle en silencio —se captura y se devuelve `Left`— y con eso la
/// tabla nunca notifica el cambio: cualquier prueba que esperara ese cambio
/// por stream se queda esperando algo que no va a llegar, hasta que el
/// framework la corta a los 30 segundos. Así se encontró este bug la
/// primera vez, con la prueba entera colgada.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late FlashcardRepositoryImpl repository;
  late FakeIdGenerator ids;
  var now = DateTime(2026, 9, 13, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    now = DateTime(2026, 9, 13, 10);
    counter = 0;
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    repository = FlashcardRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<String> seedItem() async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: 'Elemento $n',
      source: Source(
        id: 'src-$n',
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!.id;
  }

  group('crear', () {
    test('queda lista para repasarse desde ya', () async {
      final itemId = await seedItem();

      final result = await repository.create(
        itemId: itemId,
        front: '¿Pregunta?',
        back: 'Respuesta',
      );

      final card = result.getRight().toNullable()!;
      expect(card.front, '¿Pregunta?');
      expect(card.back, 'Respuesta');
      expect(card.dueAt, now);
      expect(card.repetitions, 0);
      expect(card.easeFactor, 2.5);
    });

    test('una pregunta o respuesta en blanco se rechaza', () async {
      final itemId = await seedItem();

      final result = await repository.create(
        itemId: itemId,
        front: '   ',
        back: 'Respuesta',
      );

      expect(result.isLeft(), isTrue);
    });

    test('recorta espacios de los bordes', () async {
      final itemId = await seedItem();

      final result = await repository.create(
        itemId: itemId,
        front: '  pregunta  ',
        back: '  respuesta  ',
      );

      final card = result.getRight().toNullable()!;
      expect(card.front, 'pregunta');
      expect(card.back, 'respuesta');
    });

    test('un elemento que no existe se rechaza, no revienta', () async {
      final result = await repository.create(
        itemId: 'no-existe',
        front: 'a',
        back: 'b',
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('actualizar', () {
    test('cambia el contenido sin tocar el estado de repaso', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'Antes',
        back: 'Antes',
      )).getRight().toNullable()!;
      await repository.review(id: created.id, grade: ReviewGrade.good);

      final result = await repository.update(
        id: created.id,
        front: 'Después',
        back: 'También después',
      );

      final updated = result.getRight().toNullable()!;
      expect(updated.front, 'Después');
      expect(updated.back, 'También después');
      expect(updated.repetitions, 1);
    });

    test('una que ya no existe devuelve un fallo, no revienta', () async {
      final result = await repository.update(
        id: 'no-existe',
        front: 'a',
        back: 'b',
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('borrar', () {
    test('deja de aparecer entre las tarjetas del elemento', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;

      await repository.delete(created.id);

      expect(await repository.watchForItem(itemId).first, isEmpty);
    });

    test('borrar una que no existe no falla', () async {
      final result = await repository.delete('no-existe');

      expect(result.isRight(), isTrue);
    });
  });

  group('repasar', () {
    test('aplica el SM-2 y guarda la nueva fecha de vencimiento', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;

      final result = await repository.review(
        id: created.id,
        grade: ReviewGrade.good,
      );

      final reviewed = result.getRight().toNullable()!;
      expect(reviewed.repetitions, 1);
      expect(reviewed.intervalDays, 1);
      expect(reviewed.dueAt, now.add(const Duration(days: 1)));
      expect(reviewed.lastReviewedAt, now);
    });

    test('queda guardado: releerla trae el resultado del repaso', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;
      await repository.review(id: created.id, grade: ReviewGrade.good);

      final reloaded = (await repository.watchForItem(itemId).first).single;

      expect(reloaded.repetitions, 1);
      expect(reloaded.intervalDays, 1);
    });

    test('una que ya no existe devuelve un fallo, no revienta', () async {
      final result = await repository.review(
        id: 'no-existe',
        grade: ReviewGrade.good,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('tarjetas de un elemento', () {
    test('solo trae las de ese elemento, en orden de creación', () async {
      final itemA = await seedItem();
      final itemB = await seedItem();
      await repository.create(itemId: itemA, front: 'a1', back: 'b1');
      await repository.create(itemId: itemB, front: 'a2', back: 'b2');
      await repository.create(itemId: itemA, front: 'a3', back: 'b3');

      final cards = await repository.watchForItem(itemA).first;

      expect(cards.map((c) => c.front), ['a1', 'a3']);
    });

    test('se actualiza sola cuando se agrega una tarjeta nueva', () async {
      final itemId = await seedItem();
      final queue = StreamQueue(repository.watchForItem(itemId));
      addTearDown(queue.cancel);

      expect(await queue.next, isEmpty);

      await repository.create(itemId: itemId, front: 'a', back: 'b');

      expect((await queue.next).map((c) => c.front), ['a']);
    });

    test('borrar el elemento borra también sus tarjetas', () async {
      final itemId = await seedItem();
      await repository.create(itemId: itemId, front: 'a', back: 'b');

      await libraryRepository.delete(itemId);

      expect(await repository.watchForItem(itemId).first, isEmpty);
    });
  });

  group('tarjetas que tocan repasar', () {
    test('solo trae las que ya vencieron', () async {
      final itemId = await seedItem();
      final due = (await repository.create(
        itemId: itemId,
        front: 'vencida',
        back: 'b',
      )).getRight().toNullable()!;
      final notDueYet = (await repository.create(
        itemId: itemId,
        front: 'todavía no',
        back: 'b',
      )).getRight().toNullable()!;
      // Repasarla con "bien" la empuja un día al futuro, así deja de ser
      // parte de lo que toca hoy.
      await repository.review(id: notDueYet.id, grade: ReviewGrade.good);

      final cards = await repository.watchDue().first;

      expect(cards.map((c) => c.id), [due.id]);
    });

    test('el contador refleja la misma cantidad', () async {
      final itemId = await seedItem();
      await repository.create(itemId: itemId, front: 'a', back: 'b');
      await repository.create(itemId: itemId, front: 'c', back: 'd');

      expect(await repository.watchDueCount().first, 2);
    });

    test(
      'repasar una tarjeta la saca de las que tocan, si queda a futuro',
      () async {
        final itemId = await seedItem();
        final created = (await repository.create(
          itemId: itemId,
          front: 'a',
          back: 'b',
        )).getRight().toNullable()!;

        await repository.review(id: created.id, grade: ReviewGrade.good);

        expect(await repository.watchDue().first, isEmpty);
      },
    );
  });
}
