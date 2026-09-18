import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';

import '../../generated_migrations/schema.dart';

/// La migración de esquema 7→8 —que agrega el modelo de conocimiento nuevo
/// (item/source/note/chunk/embedding)— probada con el `SchemaVerifier` de
/// drift_dev: crea una base física en el esquema histórico v7, corre la
/// migración real de `AppDatabase`, y verifica el resultado contra el
/// esquema actual. Es el mecanismo oficial de Drift para esto —cuesta cero
/// dependencias nuevas y F2 en adelante lo va a poder reutilizar con sus
/// propias migraciones.
///
/// Sin backfill todavía: acá solo se verifica que las tablas nuevas se
/// crean correctamente, vacías, y que las tablas viejas no se tocan. El
/// backfill de lo ya capturado es un paso posterior de F1.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('una base nueva (onCreate) trae las tablas del modelo de '
      'conocimiento, vacías', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.knowledgeEntries).get(), isEmpty);
    expect(await db.select(db.knowledgeSources).get(), isEmpty);
    expect(await db.select(db.knowledgeNotes).get(), isEmpty);
    expect(await db.select(db.chunks).get(), isEmpty);
    expect(await db.select(db.embeddings).get(), isEmpty);
    expect(await db.select(db.migrationIssues).get(), isEmpty);
  });

  test('migrar de v7 a v8 crea las tablas nuevas, vacías', () async {
    final connection = await verifier.startAt(7);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 8);

    expect(await db.select(db.knowledgeEntries).get(), isEmpty);
    expect(await db.select(db.knowledgeSources).get(), isEmpty);
    expect(await db.select(db.knowledgeNotes).get(), isEmpty);
    expect(await db.select(db.chunks).get(), isEmpty);
    expect(await db.select(db.embeddings).get(), isEmpty);
  });

  test('migrar de v7 a v8 con datos legacy en Items/Sources no los toca ni '
      'los borra', () async {
    final connection = await verifier.startAt(7);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    // Se inserta contra el esquema real (v8): `Items`/`Sources` tienen
    // exactamente la misma forma en v7 y v8 —esta migración solo agrega
    // tablas, no las toca—, así que el companion real de la app arma el
    // mismo SQL que armaría el companion generado para v7.
    final now = DateTime(2026, 9, 17, 10);
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-1',
            kind: SourceKind.webPage,
            capturedAt: now,
            url: const Value('https://ejemplo.org/articulo'),
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: 'item-1',
            title: 'Un artículo cualquiera',
            sourceId: 'src-1',
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await verifier.migrateAndValidate(db, 8);

    final items = await db.select(db.items).get();
    final sources = await db.select(db.sources).get();
    expect(items, hasLength(1));
    expect(items.single.title, 'Un artículo cualquiera');
    expect(sources, hasLength(1));
    expect(await db.select(db.knowledgeEntries).get(), isEmpty);
  });

  group('esquema nuevo', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> insertEntry({
      required String id,
      required ItemKind kind,
      required DateTime now,
    }) => db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: id,
            title: 'Un elemento',
            kind: kind,
            state: ItemState.captured,
            createdAt: now,
            updatedAt: now,
            deviceId: 'device-test',
          ),
        );

    test('rev tiene 1 por defecto', () async {
      final now = DateTime(2026, 9, 17);
      await insertEntry(id: 'item-1', kind: ItemKind.note, now: now);

      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('item-1'))).getSingle();

      expect(entry.rev, 1);
    });

    test('borrar un item borra su source y sus chunks en cascada', () async {
      final now = DateTime(2026, 9, 17);
      await insertEntry(id: 'item-1', kind: ItemKind.source, now: now);
      await db
          .into(db.knowledgeSources)
          .insert(
            KnowledgeSourcesCompanion.insert(
              itemId: 'item-1',
              sourceType: SourceKind.webPage,
              capturedAt: now,
              contentHash: 'hash-1',
              processingStatus: SourceProcessingStatus.done,
            ),
          );
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: 'chunk-1',
              itemId: 'item-1',
              seq: 0,
              content: 'texto',
              charStart: 0,
              charEnd: 5,
            ),
          );
      await db
          .into(db.embeddings)
          .insert(
            EmbeddingsCompanion.insert(
              chunkId: 'chunk-1',
              vector: Uint8List(0),
              modelVersion: 'sin-usar',
              createdAt: now,
            ),
          );

      await (db.delete(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('item-1'))).go();

      expect(await db.select(db.knowledgeSources).get(), isEmpty);
      expect(await db.select(db.chunks).get(), isEmpty);
      expect(await db.select(db.embeddings).get(), isEmpty);
    });

    test('dos chunks del mismo item no pueden compartir seq', () async {
      final now = DateTime(2026, 9, 17);
      await insertEntry(id: 'item-1', kind: ItemKind.source, now: now);

      Future<void> insertChunk(String id) => db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: id,
              itemId: 'item-1',
              seq: 0,
              content: 'texto',
              charStart: 0,
              charEnd: 5,
            ),
          );

      await insertChunk('chunk-1');
      expect(() => insertChunk('chunk-2'), throwsA(isA<Object>()));
    });

    test('una nota no necesita fila en KnowledgeSources', () async {
      final now = DateTime(2026, 9, 17);
      await insertEntry(id: 'item-1', kind: ItemKind.note, now: now);
      await db
          .into(db.knowledgeNotes)
          .insert(
            KnowledgeNotesCompanion.insert(
              itemId: 'item-1',
              noteKind: NoteKind.living,
              maturity: NoteMaturity.seed,
            ),
          );

      final note = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals('item-1'))).getSingle();
      expect(note.noteKind, NoteKind.living);
      expect(await db.select(db.knowledgeSources).get(), isEmpty);
    });
  });
}
