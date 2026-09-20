import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/health/data/repositories/health_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Las consultas del panel de salud, contra SQLite real: las notas se guardan
/// por el camino de la app —para que el espejo nazca como nace de verdad— y
/// después se ajustan el subtipo, la madurez y las fechas.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late HealthRepositoryImpl repository;

  final since = DateTime.utc(2026, 9, 12);
  final before = DateTime.utc(2026, 9);
  final after = DateTime.utc(2026, 9, 15);
  final later = DateTime.utc(2026, 9, 16);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    repository = HealthRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
    );
  });

  tearDown(() => db.close());

  /// Guarda una nota de bloques y le pone [kind] y [maturity]. [updatedAt] es
  /// cuándo se guardó por última vez.
  Future<void> seedNote(
    String id, {
    String? title,
    List<ContentBlock> blocks = const [ContentBlock.paragraph(text: 'texto')],
    DateTime? updatedAt,
    NoteKind kind = NoteKind.living,
    NoteMaturity maturity = NoteMaturity.seed,
    String? rawContent,
  }) async {
    final at = updatedAt ?? before;
    await library.save(
      KnowledgeItem(
        id: id,
        title: title ?? 'Nota $id',
        source: Source(
          id: 'src-$id',
          kind: SourceKind.manualNote,
          capturedAt: at,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
        renditions: [
          Rendition.text(
            id: 'rend-$id',
            itemId: id,
            kind: RenditionKind.blocks,
            content: rawContent ?? encodeContentBlocks(blocks),
            isPrimary: true,
            createdAt: at,
          ),
        ],
      ),
    );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(noteKind: Value(kind), maturity: Value(maturity)),
    );
  }

  Future<void> relate(
    String from,
    String to, {
    RelationKind kind = RelationKind.relatedTo,
    DateTime? createdAt,
    DateTime? reviewedAt,
  }) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'rel-$from-$to-${kind.name}',
          fromItemId: from,
          toItemId: to,
          kind: kind,
          createdAt: createdAt ?? before,
          reviewedAt: Value(reviewedAt),
        ),
      );

  group('watchNoteComposition', () {
    test(
      'sin notas trae todo en cero, con todos los valores presentes',
      () async {
        final composition = await repository.watchNoteComposition().first;

        expect(composition.total, 0);
        expect(composition.byKind.keys, NoteKind.values);
        expect(composition.byMaturity.keys, NoteMaturity.values);
        expect(composition.byKind.values, everyElement(0));
      },
    );

    test('cuenta por subtipo y por madurez', () async {
      await seedNote('a1', kind: NoteKind.atomic);
      await seedNote(
        'a2',
        kind: NoteKind.atomic,
        maturity: NoteMaturity.mature,
      );
      await seedNote('v1', maturity: NoteMaturity.developing);
      await seedNote('v2', maturity: NoteMaturity.developing);
      await seedNote('v3', maturity: NoteMaturity.developing);
      await seedNote('m1', kind: NoteKind.map);

      final composition = await repository.watchNoteComposition().first;

      expect(composition.total, 6);
      expect(composition.kindCount(NoteKind.atomic), 2);
      expect(composition.kindCount(NoteKind.living), 3);
      expect(composition.kindCount(NoteKind.map), 1);
      expect(composition.maturityCount(NoteMaturity.seed), 2);
      expect(composition.maturityCount(NoteMaturity.developing), 3);
      expect(composition.maturityCount(NoteMaturity.mature), 1);
    });

    test('una fuente no es una nota: no cuenta', () async {
      await library.save(
        KnowledgeItem(
          id: 'fuente',
          title: 'Una fuente',
          source: Source(
            id: 'src-fuente',
            kind: SourceKind.webPage,
            capturedAt: before,
          ),
          processingState: ProcessingState.ready,
          createdAt: before,
          updatedAt: before,
        ),
      );

      expect((await repository.watchNoteComposition().first).total, 0);
    });

    test('se actualiza sola cuando cambia la madurez', () async {
      await seedNote('v1');
      final queue = StreamQueue(repository.watchNoteComposition());
      addTearDown(queue.cancel);
      expect((await queue.next).maturityCount(NoteMaturity.mature), 0);

      await (db.update(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals('v1'))).write(
        const KnowledgeNotesCompanion(maturity: Value(NoteMaturity.mature)),
      );

      expect((await queue.next).maturityCount(NoteMaturity.mature), 1);
    });
  });

  group('watchUnreviewedContradictionCount', () {
    test('cuenta solo las contradicciones sin revisar', () async {
      await seedNote('a');
      await seedNote('b');
      await seedNote('c');
      await seedNote('d');
      await relate('a', 'b', kind: RelationKind.contradicts);
      await relate('a', 'c', kind: RelationKind.contradicts);
      await relate('a', 'd', kind: RelationKind.contradicts, reviewedAt: after);
      // Otro tipo de vínculo no es una contradicción.
      await relate('b', 'c');

      expect(await repository.watchUnreviewedContradictionCount().first, 2);
    });

    test('sin contradicciones es cero', () async {
      expect(await repository.watchUnreviewedContradictionCount().first, 0);
    });

    test('baja cuando se marca una como revisada', () async {
      await seedNote('a');
      await seedNote('b');
      await relate('a', 'b', kind: RelationKind.contradicts);
      final queue = StreamQueue(repository.watchUnreviewedContradictionCount());
      addTearDown(queue.cancel);
      expect(await queue.next, 1);

      await db
          .update(db.relations)
          .write(RelationsCompanion(reviewedAt: Value(after)));

      expect(await queue.next, 0);
    });
  });

  group('watchBrokenLinkCount', () {
    test('cuenta títulos distintos, no notas que los escriben', () async {
      await seedNote(
        'n1',
        blocks: const [
          ContentBlock.paragraph(text: '[[Cartago]] y [[Atenas]]'),
        ],
      );
      await seedNote(
        'n2',
        blocks: const [ContentBlock.paragraph(text: 'otra vez [[cartago]]')],
      );

      expect(await repository.watchBrokenLinkCount().first, 2);
    });

    test('un enlace con destino no está roto', () async {
      await seedNote('roma', title: 'Roma');
      await seedNote(
        'n1',
        blocks: const [ContentBlock.paragraph(text: '[[Roma]] y [[Cartago]]')],
      );

      expect(await repository.watchBrokenLinkCount().first, 1);
    });

    test('baja en cuanto se crea la nota que faltaba', () async {
      await seedNote(
        'n1',
        blocks: const [ContentBlock.paragraph(text: '[[Cartago]]')],
      );
      final queue = StreamQueue(repository.watchBrokenLinkCount());
      addTearDown(queue.cancel);
      expect(await queue.next, 1);

      await seedNote('cartago', title: 'Cartago');

      var latest = await queue.next;
      while (latest != 0) {
        latest = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(latest, 0);
    });
  });

  group('watchGrownNotes', () {
    Future<List<(String, int, int)>> grown({
      Set<NoteKind> kinds = const {NoteKind.living},
    }) async => [
      for (final note
          in await repository.watchGrownNotes(since: since, kinds: kinds).first)
        (note.itemId, note.newBlocks, note.newRelations),
    ];

    test('cuenta los bloques con texto que nacieron desde la fecha', () async {
      await seedNote(
        'a',
        updatedAt: later,
        blocks: [
          ContentBlock.paragraph(text: 'viejo', addedAt: before),
          ContentBlock.paragraph(text: 'nuevo uno', addedAt: after),
          ContentBlock.quote(text: 'nuevo dos', addedAt: later),
          // Un bloque vacío que nació esta semana no es crecimiento.
          ContentBlock.paragraph(text: '   ', addedAt: later),
        ],
      );

      expect(await grown(), [('a', 2, 0)]);
    });

    test('un bloque que nació justo en la fecha cuenta', () async {
      await seedNote(
        'a',
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'justo', addedAt: since)],
      );

      expect(await grown(), [('a', 1, 0)]);
    });

    test(
      'los bloques sin fecha no cuentan: no se sabe cuándo nacieron',
      () async {
        await seedNote(
          'a',
          updatedAt: later,
          blocks: const [
            ContentBlock.paragraph(text: 'uno'),
            ContentBlock.paragraph(text: 'dos'),
          ],
        );

        expect(await grown(), isEmpty);
      },
    );

    test(
      'una nota editada esta semana pero sin bloques nuevos no crece',
      () async {
        await seedNote(
          'a',
          updatedAt: later,
          blocks: [
            ContentBlock.paragraph(text: 'viejo, corregido', addedAt: before),
          ],
        );

        expect(await grown(), isEmpty);
      },
    );

    test('las relaciones nuevas cuentan para las dos puntas', () async {
      await seedNote('a');
      await seedNote('b');
      await seedNote('c');
      await relate('a', 'b', createdAt: after);
      // Una relación de antes de la fecha no cuenta.
      await relate('a', 'c', createdAt: before);

      expect(await grown(), [('a', 0, 1), ('b', 0, 1)]);
    });

    test('suma bloques y relaciones, y ordena por lo que más creció', () async {
      await seedNote(
        'a',
        title: 'A',
        updatedAt: later,
        blocks: [
          ContentBlock.paragraph(text: 'uno', addedAt: after),
          ContentBlock.paragraph(text: 'dos', addedAt: after),
        ],
      );
      await seedNote('c', title: 'C');
      await seedNote('b', title: 'B');
      await relate('a', 'c', createdAt: after);
      await relate('b', 'c', createdAt: after);

      // A: 2 bloques + 1 relación; C: 2 relaciones; B: 1 relación.
      expect(await grown(), [('a', 2, 1), ('c', 0, 2), ('b', 0, 1)]);
    });

    test(
      'a igual crecimiento ordena por título sin mirar los acentos',
      () async {
        await seedNote('z', title: 'Zeta');
        await seedNote('e', title: 'Época');
        await seedNote('r', title: 'Roma');
        await relate('z', 'e', createdAt: after);
        await relate('r', 'e', createdAt: after);
        // "Época" tiene 2, las otras 1: primero ella, después Roma y Zeta.

        expect(await grown(), [('e', 0, 2), ('r', 0, 1), ('z', 0, 1)]);
      },
    );

    test('por defecto solo las vivas: una atómica no crece, ni un mapa es '
        'contenido', () async {
      await seedNote(
        'viva',
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'x', addedAt: after)],
      );
      await seedNote(
        'atomica',
        kind: NoteKind.atomic,
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'x', addedAt: after)],
      );
      await seedNote(
        'mapa',
        kind: NoteKind.map,
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'x', addedAt: after)],
      );

      expect((await grown()).map((g) => g.$1), ['viva']);
      expect(
        (await grown(
          kinds: {NoteKind.living, NoteKind.atomic},
        )).map((g) => g.$1),
        unorderedEquals(['viva', 'atomica']),
      );
      expect(await grown(kinds: const {}), isEmpty);
    });

    test('trae la madurez y el título de cada nota', () async {
      await seedNote(
        'a',
        title: 'Una nota viva',
        maturity: NoteMaturity.developing,
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'x', addedAt: after)],
      );

      final note =
          (await repository.watchGrownNotes(since: since).first).single;

      expect(note.title, 'Una nota viva');
      expect(note.maturity, NoteMaturity.developing);
    });

    test('una nota con bloques ilegibles no rompe a las demás', () async {
      await seedNote('mala', updatedAt: later, rawContent: 'esto no es json');
      await seedNote(
        'buena',
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'x', addedAt: after)],
      );

      expect(await grown(), [('buena', 1, 0)]);
    });

    test('aguanta más notas tocadas que las que entran en un IN', () async {
      // Más de 500: el troceado del `IN (...)` tiene que dar la cuenta entera.
      const total = 520;
      for (var i = 0; i < total; i++) {
        await seedNote(
          'n$i',
          updatedAt: later,
          blocks: [ContentBlock.paragraph(text: 'x', addedAt: after)],
        );
      }

      final result = await grown();

      expect(result, hasLength(total));
      expect(result.every((g) => g.$2 == 1), isTrue);
    });

    test('qué notas se tocaron desde la fecha lo dice item, y la lista se '
        'actualiza sola cuando eso cambia', () async {
      // Una nota con un bloque nacido esta semana, pero guardada por última vez
      // antes de la fecha: no se la considera tocada.
      await seedNote(
        'a',
        updatedAt: before,
        blocks: [ContentBlock.paragraph(text: 'nuevo', addedAt: after)],
      );
      final queue = StreamQueue(repository.watchGrownNotes(since: since));
      addTearDown(queue.cancel);
      expect(await queue.next, isEmpty);

      // Se cambia SOLO la fila nueva: si la lectura saliera de la tabla vieja,
      // la nota seguiría sin contar.
      await (db.update(db.knowledgeEntries)..where((e) => e.id.equals('a')))
          .write(KnowledgeEntriesCompanion(updatedAt: Value(later)));

      var latest = await queue.next;
      while (latest.isEmpty) {
        latest = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(latest.single.newBlocks, 1);
    });

    test('se actualiza sola cuando una nota gana un bloque', () async {
      await seedNote('a', updatedAt: later);
      final queue = StreamQueue(repository.watchGrownNotes(since: since));
      addTearDown(queue.cancel);
      expect(await queue.next, isEmpty);

      await seedNote(
        'a',
        updatedAt: later,
        blocks: [ContentBlock.paragraph(text: 'nuevo', addedAt: after)],
      );

      var latest = await queue.next;
      while (latest.isEmpty) {
        latest = await queue.next.timeout(const Duration(seconds: 5));
      }
      expect(latest.single.newBlocks, 1);
    });
  });
}
