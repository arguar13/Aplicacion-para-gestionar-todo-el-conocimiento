import 'package:async/async.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: lo que hay que verificar acá es que el
/// SM-2 se aplica y se guarda bien, no solo que un doble responda lo que se
/// le pida.
///
/// Los elementos se siembran con `LibraryRepositoryImpl.save`, igual que en
/// `organize_repository_impl_test.dart`, y no con un `itemId` de texto
/// suelto: `Flashcards.itemId` referencia a `item` con
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
      final reviewed = (await repository.review(
        id: created.id,
        grade: ReviewGrade.easy,
      )).getRight().toNullable()!;

      final result = await repository.update(
        id: created.id,
        front: 'Después',
        back: 'También después',
      );

      final updated = result.getRight().toNullable()!;
      expect(updated.front, 'Después');
      expect(updated.back, 'También después');
      expect(updated.repetitions, 2);
      expect(updated.intervalDays, reviewed.intervalDays);
      expect(updated.dueAt, reviewed.dueAt);
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
    test('aplica el calendario y guarda la nueva fecha de vencimiento: una '
        'nueva contestada «Bien» vuelve en 10 minutos (F31)', () async {
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
      expect(reviewed.learningStep, 1);
      expect(reviewed.repetitions, 0);
      expect(reviewed.dueAt, now.add(const Duration(minutes: 10)));
      expect(reviewed.lastReviewedAt, now);
    });

    test('y al segundo «Bien» se gradúa: 1 día y 1 repetición', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;
      await repository.review(id: created.id, grade: ReviewGrade.good);
      now = now.add(const Duration(minutes: 10));

      final reviewed = (await repository.review(
        id: created.id,
        grade: ReviewGrade.good,
      )).getRight().toNullable()!;

      expect(reviewed.learningStep, isNull);
      expect(reviewed.repetitions, 1);
      expect(reviewed.intervalDays, 1);
      expect(reviewed.dueAt, now.add(const Duration(days: 1)));
    });

    test('queda guardado: releerla trae el resultado del repaso', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;
      await repository.review(id: created.id, grade: ReviewGrade.easy);

      final reloaded = (await repository.watchForItem(itemId).first).single;

      expect(reloaded.repetitions, 2);
      expect(reloaded.intervalDays, 4);
      expect(reloaded.learningStep, isNull);
    });

    test('el paso de aprendizaje también queda guardado', () async {
      final itemId = await seedItem();
      final created = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;
      await repository.review(id: created.id, grade: ReviewGrade.again);

      final reloaded = (await repository.watchForItem(itemId).first).single;

      expect(reloaded.learningStep, 0);
      expect(reloaded.dueAt, now.add(const Duration(minutes: 1)));
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

    test('mandar el elemento a la papelera conserva sus tarjetas', () async {
      final itemId = await seedItem();
      await repository.create(itemId: itemId, front: 'a', back: 'b');

      await libraryRepository.delete(itemId);

      expect(await repository.watchForItem(itemId).first, hasLength(1));
    });

    test('borrarlo para siempre borra también sus tarjetas', () async {
      final itemId = await seedItem();
      await repository.create(itemId: itemId, front: 'a', back: 'b');
      await libraryRepository.delete(itemId);

      await libraryRepository.purge([itemId]);

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

  group('todas las tarjetas', () {
    test('trae las de toda la bóveda, no solo las que vencieron', () async {
      final itemA = await seedItem();
      final itemB = await seedItem();
      final due = (await repository.create(
        itemId: itemA,
        front: 'vencida',
        back: 'b',
      )).getRight().toNullable()!;
      final notDueYet = (await repository.create(
        itemId: itemB,
        front: 'todavía no',
        back: 'b',
      )).getRight().toNullable()!;
      await repository.review(id: notDueYet.id, grade: ReviewGrade.good);

      final result = await repository.getAll();

      final cards = result.getRight().toNullable()!;
      expect(cards.map((c) => c.id), containsAll([due.id, notDueYet.id]));
    });

    test('sin tarjetas todavía, trae una lista vacía', () async {
      final result = await repository.getAll();

      expect(result.getRight().toNullable(), isEmpty);
    });
  });

  group('exportación incremental (F17, D4)', () {
    test('una tarjeta recién creada nunca se exportó: entra en lo '
        'pendiente', () async {
      final item = await seedItem();
      final card = (await repository.create(
        itemId: item,
        front: 'p',
        back: 'r',
      )).getRight().toNullable()!;

      final pending = (await repository.getPendingExport())
          .getRight()
          .toNullable()!;

      expect(pending.map((c) => c.id), [card.id]);
      expect(card.lastExportedAt, isNull);
    });

    test('marcarla exportada la saca de lo pendiente, con la hora de '
        'ahora', () async {
      final item = await seedItem();
      final card = (await repository.create(
        itemId: item,
        front: 'p',
        back: 'r',
      )).getRight().toNullable()!;
      now = DateTime(2026, 9, 25, 11);

      final marked = await repository.markExported({card.id});

      expect(marked.isRight(), isTrue);
      final pending = (await repository.getPendingExport())
          .getRight()
          .toNullable()!;
      expect(pending, isEmpty);
      final all = (await repository.getAll()).getRight().toNullable()!;
      expect(all.single.lastExportedAt, now);
    });

    test('marcar un conjunto vacío no toca nada ni rompe', () async {
      final result = await repository.markExported(const {});

      expect(result.isRight(), isTrue);
    });

    test('una tarjeta en la papelera no entra en lo pendiente', () async {
      final trashed = await seedItem();
      await repository.create(itemId: trashed, front: 'p', back: 'r');
      await trashItemRows(db, trashed);

      final pending = (await repository.getPendingExport())
          .getRight()
          .toNullable()!;

      expect(pending, isEmpty);
    });
  });

  group('la papelera (F11)', () {
    Future<void> card(String itemId, String front) =>
        repository.create(itemId: itemId, front: front, back: 'respuesta');

    test('las tarjetas de algo en la papelera no tocan repasar, y vuelven al '
        'restaurarlo', () async {
      final trashed = await seedItem();
      final live = await seedItem();
      await card(trashed, 'de lo borrado');
      await card(live, 'de lo vivo');
      final queue = StreamQueue(repository.watchDue());
      addTearDown(queue.cancel);
      expect((await queue.next).map((c) => c.front), hasLength(2));

      await trashItemRows(db, trashed);
      var due = await queue.next;
      while (due.length != 1) {
        due = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(due.single.front, 'de lo vivo');

      await restoreItemRows(db, trashed);
      due = await queue.next;
      while (due.length != 2) {
        due = await queue.next.timeout(const Duration(seconds: 5));
      }
    });

    test('el contador de pendientes tampoco las cuenta', () async {
      final trashed = await seedItem();
      await card(trashed, 'de lo borrado');
      await trashItemRows(db, trashed);

      expect(await repository.watchDueCount().first, 0);
    });

    test('la exportación —todas las tarjetas— las deja afuera', () async {
      final trashed = await seedItem();
      final live = await seedItem();
      await card(trashed, 'de lo borrado');
      await card(live, 'de lo vivo');
      await trashItemRows(db, trashed);

      final all = (await repository.getAll()).getRight().toNullable()!;

      expect(all.map((c) => c.front), ['de lo vivo']);
    });

    test('las tarjetas de un elemento, pedidas por su id, siguen ahí: es lo '
        'que se ve al restaurarlo', () async {
      final trashed = await seedItem();
      await card(trashed, 'de lo borrado');
      await trashItemRows(db, trashed);

      expect(await repository.watchForItem(trashed).first, hasLength(1));
    });
  });

  group('historial de repasos (F11)', () {
    Future<List<ReviewLogRow>> log() => (db.select(
      db.reviewLogs,
    )..orderBy([(r) => OrderingTerm(expression: r.reviewedAt)])).get();

    Future<String> newCard() async {
      final itemId = await seedItem();
      return (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!.id;
    }

    test('cada repaso deja un renglón con la nota, la calidad y cómo cambió '
        'la tarjeta', () async {
      final id = await newCard();

      await repository.review(id: id, grade: ReviewGrade.good);

      final row = (await log()).single;
      expect(row.flashcardId, id);
      expect(row.reviewedAt, now);
      expect(row.grade, 'good');
      expect(row.quality, 4);
      // Una tarjeta nueva parte de intervalo 0 y, contestada «Bien», pasa al
      // paso de 10 minutos: sigue sin intervalo en días.
      expect(row.intervalBefore, 0);
      expect(row.intervalAfter, 0);
      expect(row.easeBefore, 2.5);
      expect(row.easeAfter, 2.5);
      expect(row.deviceId, 'unspecified');
    });

    test('varios repasos son varios renglones, y cada uno parte de donde '
        'quedó el anterior', () async {
      final id = await newCard();

      await repository.review(id: id, grade: ReviewGrade.good);
      now = now.add(const Duration(minutes: 10));
      await repository.review(id: id, grade: ReviewGrade.good);
      now = now.add(const Duration(days: 1));
      await repository.review(id: id, grade: ReviewGrade.good);
      now = now.add(const Duration(days: 6));
      await repository.review(id: id, grade: ReviewGrade.again);

      final rows = await log();
      expect(rows.map((r) => r.grade), ['good', 'good', 'good', 'again']);
      expect(rows.map((r) => r.quality), [4, 4, 4, 0]);
      expect(rows.map((r) => r.intervalBefore), [0, 0, 1, 6]);
      expect(rows.map((r) => r.intervalAfter), [0, 1, 6, 1]);
      // Una tarjeta que se olvidó pierde facilidad.
      expect(rows.last.easeAfter, lessThan(rows.last.easeBefore));
    });

    test(
      'guarda de qué etapa partió y lo necesario para deshacerlo (F31)',
      () async {
        final id = await newCard();
        final first = now;
        await repository.review(id: id, grade: ReviewGrade.good);
        final second = now.add(const Duration(minutes: 10));
        now = second;
        await repository.review(id: id, grade: ReviewGrade.good);
        final third = now.add(const Duration(days: 1));
        now = third;
        await repository.review(id: id, grade: ReviewGrade.again);

        final rows = await log();
        // La primera respuesta parte de una tarjeta nueva, sin nada anterior.
        expect(rows[0].phaseBefore, CardPhase.newCard);
        expect(rows[0].dueBefore, first);
        expect(rows[0].lastReviewedBefore, isNull);
        expect(rows[0].repetitionsBefore, 0);
        expect(rows[0].stepBefore, isNull);
        expect(rows[0].stepAfter, 1);
        // La segunda, de una que se está aprendiendo, en el paso de 10
        // minutos.
        expect(rows[1].phaseBefore, CardPhase.learning);
        expect(rows[1].stepBefore, 1);
        expect(rows[1].stepAfter, isNull);
        expect(rows[1].lastReviewedBefore, first);
        expect(rows[1].dueBefore, second);
        // La tercera, de una que ya se repasa por días: se olvida y pasa a
        // reaprender.
        expect(rows[2].phaseBefore, CardPhase.review);
        expect(rows[2].repetitionsBefore, 1);
        expect(rows[2].lastReviewedBefore, second);
        expect(rows[2].dueBefore, second.add(const Duration(days: 1)));
        expect(rows[2].stepBefore, isNull);
        expect(rows[2].stepAfter, 0);
      },
    );

    test('lo que guarda coincide con lo que quedó en la tarjeta', () async {
      final id = await newCard();

      final reviewed = (await repository.review(
        id: id,
        grade: ReviewGrade.easy,
      )).getRight().toNullable()!;

      final row = (await log()).single;
      expect(row.intervalAfter, reviewed.intervalDays);
      expect(row.easeAfter, reviewed.easeFactor);
      expect(row.quality, 5);
    });

    test('la nota que elige la persona y la calidad del algoritmo se guardan '
        'las dos', () async {
      final id = await newCard();
      for (final grade in ReviewGrade.values) {
        await repository.review(id: id, grade: grade);
        now = now.add(const Duration(minutes: 1));
      }

      final rows = await log();
      expect(
        {for (final r in rows) r.grade: r.quality},
        {'again': 0, 'hard': 3, 'good': 4, 'easy': 5},
      );
    });

    test('una tarjeta que no existe no deja ningún renglón', () async {
      await repository.review(id: 'no-existe', grade: ReviewGrade.good);

      expect(await log(), isEmpty);
    });

    test('el dispositivo que repasó queda registrado', () async {
      final other = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
      addTearDown(other.close);
      final library = LibraryRepositoryImpl(
        database: other,
        telemetry: MockTelemetryService(),
        files: InMemoryFileStore(),
      );
      final cards = FlashcardRepositoryImpl(
        database: other,
        telemetry: MockTelemetryService(),
        ids: FakeIdGenerator(),
        clock: () => now,
      );
      await library.save(
        KnowledgeItem(
          id: 'item-x',
          title: 'X',
          source: Source(
            id: 'src-x',
            kind: SourceKind.manualNote,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final id = (await cards.create(
        itemId: 'item-x',
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!.id;

      await cards.review(id: id, grade: ReviewGrade.good);

      expect(
        (await other.select(other.reviewLogs).getSingle()).deviceId,
        'telefono',
      );
    });

    test('borrar la tarjeta se lleva su historial', () async {
      final id = await newCard();
      await repository.review(id: id, grade: ReviewGrade.good);

      await repository.delete(id);

      expect(await log(), isEmpty);
    });
  });

  group('el fragmento de la fuente de una tarjeta (F11)', () {
    const text = 'Primer párrafo de la fuente.\n\nSegundo párrafo, más largo.';

    /// Una fuente con texto, guardada por el repositorio para que tenga sus
    /// chunks. Devuelve su id y los chunks en orden.
    Future<(String, List<ChunkRow>)> seedSource() async {
      final n = counter++;
      final id = 'item-$n';
      await libraryRepository.save(
        KnowledgeItem(
          id: id,
          title: 'Fuente $n',
          source: Source(
            id: 'src-$n',
            kind: SourceKind.webPage,
            capturedAt: now,
            url: 'https://ejemplo.org/$n',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-$n',
              itemId: id,
              kind: RenditionKind.markdown,
              content: text,
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );
      final chunks =
          await (db.select(db.chunks)
                ..where((c) => c.itemId.equals(id))
                ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
              .get();
      return (id, chunks);
    }

    Future<Flashcard> createWith(String itemId, {int? start, int? end}) async =>
        (await repository.create(
          itemId: itemId,
          front: 'a',
          back: 'b',
          sourceCharStart: start,
          sourceCharEnd: end,
        )).getRight().toNullable()!;

    test(
      'una tarjeta con rango guarda el rango y el chunk que lo contiene',
      () async {
        final (id, chunks) = await seedSource();
        expect(chunks.length, greaterThan(1));
        final second = chunks[1];

        final card = await createWith(
          id,
          start: second.charStart + 2,
          end: second.charStart + 9,
        );

        expect(card.sourceChunkId, second.id);
        expect(card.sourceCharStart, second.charStart + 2);
        expect(card.sourceCharEnd, second.charStart + 9);
        expect(card.hasSourceRange, isTrue);
      },
    );

    test('queda guardado: releerla trae el mismo fragmento', () async {
      final (id, chunks) = await seedSource();
      await createWith(id, start: 0, end: 7);

      final reloaded = (await repository.watchForItem(id).first).single;

      expect(reloaded.sourceCharStart, 0);
      expect(reloaded.sourceCharEnd, 7);
      expect(reloaded.sourceChunkId, chunks.first.id);
    });

    test('una tarjeta escrita a mano no dice de dónde salió', () async {
      final (id, _) = await seedSource();

      final card = await createWith(id);

      expect(card.sourceChunkId, isNull);
      expect(card.sourceCharStart, isNull);
      expect(card.sourceCharEnd, isNull);
      expect(card.hasSourceRange, isFalse);
    });

    test('un rango que cruza dos chunks se anota en el primero', () async {
      final (id, chunks) = await seedSource();

      final card = await createWith(
        id,
        start: chunks.first.charEnd - 3,
        end: chunks[1].charStart + 4,
      );

      expect(card.sourceChunkId, chunks.first.id);
    });

    test('un elemento sin chunks —una nota— guarda solo el rango', () async {
      final itemId = await seedItem();

      final card = await createWith(itemId, start: 2, end: 6);

      expect(card.sourceChunkId, isNull);
      expect(card.sourceCharStart, 2);
      expect(card.sourceCharEnd, 6);
    });

    test(
      'un rango a medias, negativo o vacío se rechaza y no crea nada',
      () async {
        final (id, _) = await seedSource();

        for (final (start, end) in [
          (3, null),
          (null, 5),
          (-1, 4),
          (5, 5),
          (8, 3),
        ]) {
          final result = await repository.create(
            itemId: id,
            front: 'a',
            back: 'b',
            sourceCharStart: start,
            sourceCharEnd: end,
          );
          expect(result.isLeft(), isTrue, reason: '$start-$end');
        }
        expect(await db.select(db.flashcards).get(), isEmpty);
      },
    );

    test('si el texto se rehace y sus chunks se reemplazan, la tarjeta sigue '
        'y conserva el rango', () async {
      final (id, chunks) = await seedSource();
      await createWith(id, start: 0, end: 7);

      await (db.delete(db.chunks)..where((c) => c.itemId.equals(id))).go();

      final card = (await repository.watchForItem(id).first).single;
      expect(card.sourceChunkId, isNull);
      expect(card.sourceCharStart, 0);
      expect(card.sourceCharEnd, 7);
      expect(chunks, isNotEmpty);
    });
  });

  group('la forma de la tarjeta (F20)', () {
    const text = 'Primer párrafo de la fuente.\n\nSegundo párrafo, más largo.';

    Future<(String, List<ChunkRow>)> seedSource() async {
      final n = counter++;
      final id = 'item-$n';
      await libraryRepository.save(
        KnowledgeItem(
          id: id,
          title: 'Fuente $n',
          source: Source(
            id: 'src-$n',
            kind: SourceKind.webPage,
            capturedAt: now,
            url: 'https://ejemplo.org/$n',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-$n',
              itemId: id,
              kind: RenditionKind.markdown,
              content: text,
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );
      final chunks =
          await (db.select(db.chunks)
                ..where((c) => c.itemId.equals(id))
                ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
              .get();
      return (id, chunks);
    }

    test('create sin kind es freeRecall, lo que siempre fue', () async {
      final itemId = await seedItem();

      final card = (await repository.create(
        itemId: itemId,
        front: 'a',
        back: 'b',
      )).getRight().toNullable()!;

      expect(card.kind, FlashcardKind.freeRecall);
    });

    test('create con trueFalse guarda la afirmación en front y la explicación '
        'en back, sin opciones aparte', () async {
      final itemId = await seedItem();

      final card = (await repository.create(
        itemId: itemId,
        front: 'El cielo es verde.',
        back: 'Falso: el cielo se ve azul por la dispersión de Rayleigh.',
        kind: FlashcardKind.trueFalse,
      )).getRight().toNullable()!;

      expect(card.kind, FlashcardKind.trueFalse);
      final options = (await repository.optionsFor(
        card.id,
      )).getRight().toNullable()!;
      expect(options, isEmpty);
    });

    test(
      'create rechaza multipleChoice: hace falta createMultipleChoice',
      () async {
        final itemId = await seedItem();

        final result = await repository.create(
          itemId: itemId,
          front: 'a',
          back: 'b',
          kind: FlashcardKind.multipleChoice,
        );

        expect(result.isLeft(), isTrue);
        expect(await db.select(db.flashcards).get(), isEmpty);
      },
    );

    group('createMultipleChoice', () {
      test('guarda la tarjeta y sus opciones, en el orden dado, cada una con '
          'su propio chunk', () async {
        final (id, chunks) = await seedSource();
        final second = chunks[1];

        final card = (await repository.createMultipleChoice(
          itemId: id,
          front: '¿Cuál es la correcta?',
          options: [
            const FlashcardOptionDraft(
              content: 'Distractor uno',
              isCorrect: false,
            ),
            FlashcardOptionDraft(
              content: 'La correcta',
              isCorrect: true,
              sourceCharStart: second.charStart + 2,
              sourceCharEnd: second.charStart + 9,
            ),
            const FlashcardOptionDraft(
              content: 'Distractor dos',
              isCorrect: false,
            ),
          ],
        )).getRight().toNullable()!;

        expect(card.kind, FlashcardKind.multipleChoice);
        expect(card.front, '¿Cuál es la correcta?');

        final options = (await repository.optionsFor(
          card.id,
        )).getRight().toNullable()!;
        expect(options.map((o) => o.content), [
          'Distractor uno',
          'La correcta',
          'Distractor dos',
        ]);
        expect(options.map((o) => o.isCorrect), [false, true, false]);
        expect(options[1].sourceChunkId, second.id);
        expect(options[1].sourceCharStart, second.charStart + 2);
        expect(options[0].sourceChunkId, isNull);
      });

      test('una opción con sourceItemId busca su chunk en OTRO elemento, no en '
          'el de la tarjeta (F20, distractor real de otra fuente)', () async {
        final (cardItemId, _) = await seedSource();
        final (otherItemId, otherChunks) = await seedSource();
        final otherChunk = otherChunks.first;

        final card = (await repository.createMultipleChoice(
          itemId: cardItemId,
          front: '¿Cuál es la correcta?',
          options: [
            const FlashcardOptionDraft(content: 'La correcta', isCorrect: true),
            FlashcardOptionDraft(
              content: 'Distractor de otra fuente',
              isCorrect: false,
              sourceItemId: otherItemId,
              sourceCharStart: otherChunk.charStart,
              sourceCharEnd: otherChunk.charEnd,
            ),
          ],
        )).getRight().toNullable()!;

        final options = (await repository.optionsFor(
          card.id,
        )).getRight().toNullable()!;
        final distractor = options.firstWhere((o) => !o.isCorrect);
        expect(distractor.sourceChunkId, otherChunk.id);
        // optionsFor resuelve sourceItemId con un JOIN a chunks: tiene que
        // decir el elemento del DISTRACTOR, no el de la tarjeta.
        expect(distractor.sourceItemId, otherItemId);
        final correct = options.firstWhere((o) => o.isCorrect);
        expect(correct.sourceItemId, isNull);
      });

      test('menos de dos opciones no guarda nada', () async {
        final itemId = await seedItem();

        final result = await repository.createMultipleChoice(
          itemId: itemId,
          front: 'a',
          options: const [
            FlashcardOptionDraft(content: 'única', isCorrect: true),
          ],
        );

        expect(result.isLeft(), isTrue);
        expect(await db.select(db.flashcards).get(), isEmpty);
      });

      test('ninguna opción correcta no guarda nada', () async {
        final itemId = await seedItem();

        final result = await repository.createMultipleChoice(
          itemId: itemId,
          front: 'a',
          options: const [
            FlashcardOptionDraft(content: 'uno', isCorrect: false),
            FlashcardOptionDraft(content: 'dos', isCorrect: false),
          ],
        );

        expect(result.isLeft(), isTrue);
        expect(await db.select(db.flashcards).get(), isEmpty);
      });

      test('más de una opción correcta no guarda nada', () async {
        final itemId = await seedItem();

        final result = await repository.createMultipleChoice(
          itemId: itemId,
          front: 'a',
          options: const [
            FlashcardOptionDraft(content: 'uno', isCorrect: true),
            FlashcardOptionDraft(content: 'dos', isCorrect: true),
          ],
        );

        expect(result.isLeft(), isTrue);
        expect(await db.select(db.flashcards).get(), isEmpty);
      });

      test('una opción vacía no guarda nada', () async {
        final itemId = await seedItem();

        final result = await repository.createMultipleChoice(
          itemId: itemId,
          front: 'a',
          options: const [
            FlashcardOptionDraft(content: '   ', isCorrect: true),
            FlashcardOptionDraft(content: 'dos', isCorrect: false),
          ],
        );

        expect(result.isLeft(), isTrue);
        expect(await db.select(db.flashcards).get(), isEmpty);
        expect(await db.select(db.flashcardOptions).get(), isEmpty);
      });

      test('borrar la tarjeta se lleva sus opciones', () async {
        final itemId = await seedItem();
        final card = (await repository.createMultipleChoice(
          itemId: itemId,
          front: 'a',
          options: const [
            FlashcardOptionDraft(content: 'uno', isCorrect: true),
            FlashcardOptionDraft(content: 'dos', isCorrect: false),
          ],
        )).getRight().toNullable()!;

        await repository.delete(card.id);

        expect(await db.select(db.flashcardOptions).get(), isEmpty);
      });
    });

    test('optionsFor una tarjeta que no existe da una lista vacía', () async {
      final options = (await repository.optionsFor(
        'nada',
      )).getRight().toNullable()!;

      expect(options, isEmpty);
    });
  });
}
