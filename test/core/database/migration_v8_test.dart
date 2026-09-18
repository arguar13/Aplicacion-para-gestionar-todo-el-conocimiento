import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/classify_existing_items_v8.dart';
import 'package:sinapsis/core/database/migrations/fragment_existing_sources_v8.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/util/id_generator.dart';

import '../../generated_migrations/schema.dart';
import '../../support/silent_logger.dart';

/// La migración de esquema 7→8 —que agrega el modelo de conocimiento nuevo
/// (item/source/note/chunk/embedding)— probada con el `SchemaVerifier` de
/// drift_dev: crea una base física en el esquema histórico v7, corre la
/// migración real de `AppDatabase`, y verifica el resultado contra el
/// esquema actual. Es el mecanismo oficial de Drift para esto —cuesta cero
/// dependencias nuevas y F2 en adelante lo va a poder reutilizar con sus
/// propias migraciones.
///
/// Cubre que las tablas nuevas se crean correctamente y que las tablas
/// viejas no se tocan. La clasificación de lo ya capturado
/// (`classifyExistingItems`) se prueba aparte, como función pura —ver el
/// comentario en su `group`— porque encadenarla con `SchemaVerifier` deja
/// dos instancias de `GeneratedDatabase` compitiendo por la misma
/// conexión física.
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

    // El segundo argumento tiene que ser la versión REAL de
    // `AppDatabase.schemaVersion` (hoy 11, por F4) y no la versión que da
    // nombre a este archivo: `AppDatabase` siempre migra hasta su propio
    // `schemaVersion` al abrirse, nunca se detiene a mitad de camino —así
    // que el esquema resultante solo puede compararse contra el snapshot
    // de la versión a la que de verdad llega.
    await verifier.migrateAndValidate(db, 11);

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

    // Mismo motivo que en el test anterior: se valida contra la versión
    // real a la que `AppDatabase` converge, no contra el número que da
    // nombre a este archivo.
    await verifier.migrateAndValidate(db, 11);

    final items = await db.select(db.items).get();
    final sources = await db.select(db.sources).get();
    expect(items, hasLength(1));
    expect(items.single.title, 'Un artículo cualquiera');
    expect(sources, hasLength(1));
  });

  group('clasificación de items existentes al migrar', () {
    // `classifyExistingItems` se prueba llamándola directamente —no
    // encadenada con `SchemaVerifier.startAt`/`migrateAndValidate`—: abrir
    // una segunda instancia de `GeneratedDatabase` sobre la misma conexión
    // que ya usó el verificador para crear el esquema v7 deja dos
    // instancias compitiendo por la misma conexión física (Drift lo avisa
    // en tiempo de ejecución: "race conditions... might corrupt the
    // database"), y en la práctica la migración dejaba de aplicarse. La
    // función es pura respecto a qué instancia de `AppDatabase` reciba: no
    // le importa si esa base llegó a `schemaVersion` 8 por `onCreate` o
    // por `onUpgrade`, así que probarla contra una base ya en v8 —sin ese
    // riesgo— cubre exactamente la misma lógica. Que la migración real
    // LLAMA a esta función en el momento correcto ya lo cubre el test de
    // arriba ("migrar de v7 a v8 crea las tablas nuevas, vacías").
    Future<AppDatabase> classifiedDbWith({
      required SourceKind sourceKind,
      required ProcessingState processingState,
    }) async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime(2026, 9, 17, 10);

      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'src-1',
              kind: sourceKind,
              capturedAt: now,
            ),
          );
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              id: 'item-1',
              title: 'Un elemento cualquiera',
              sourceId: 'src-1',
              processingState: processingState,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await classifyExistingItems(db, ids: const UuidV7Generator());
      return db;
    }

    test(
      'una fuente con procedencia externa migra a ItemKind.source',
      () async {
        final db = await classifiedDbWith(
          sourceKind: SourceKind.webPage,
          processingState: ProcessingState.ready,
        );
        addTearDown(db.close);

        final entry = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals('item-1'))).getSingle();
        final source = await (db.select(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals('item-1'))).getSingle();

        expect(entry.kind, ItemKind.source);
        expect(entry.state, ItemState.processed);
        expect(entry.rev, 1);
        expect(entry.deviceId, isNotEmpty);
        expect(source.sourceType, SourceKind.webPage);
        expect(source.processingStatus, SourceProcessingStatus.done);
        expect(
          await db.select(db.knowledgeNotes).get(),
          isEmpty,
          reason: 'una fuente no tiene fila en KnowledgeNotes',
        );
      },
    );

    test(
      'una nota manual migra a ItemKind.note con note_kind living',
      () async {
        final db = await classifiedDbWith(
          sourceKind: SourceKind.manualNote,
          processingState: ProcessingState.ready,
        );
        addTearDown(db.close);

        final entry = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals('item-1'))).getSingle();
        final note = await (db.select(
          db.knowledgeNotes,
        )..where((n) => n.itemId.equals('item-1'))).getSingle();

        expect(entry.kind, ItemKind.note);
        expect(note.noteKind, NoteKind.living);
        expect(note.maturity, NoteMaturity.seed);
        expect(
          await db.select(db.knowledgeSources).get(),
          isEmpty,
          reason: 'una nota no tiene fila en KnowledgeSources',
        );
      },
    );

    test('un item aún pendiente de procesar migra como captured', () async {
      final db = await classifiedDbWith(
        sourceKind: SourceKind.webPage,
        processingState: ProcessingState.pending,
      );
      addTearDown(db.close);

      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('item-1'))).getSingle();
      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('item-1'))).getSingle();

      expect(entry.state, ItemState.captured);
      expect(source.processingStatus, SourceProcessingStatus.pending);
    });
  });

  group('fragmentar fuentes existentes al migrar', () {
    // Mismo criterio que en la clasificación: se prueba
    // `fragmentExistingSources` como función pura, contra una base ya en
    // v8, no encadenada con `SchemaVerifier`.
    late AppDatabase db;
    late SilentLogger logger;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      logger = const SilentLogger();
    });

    tearDown(() => db.close());

    Future<String> seedSourceWithText(
      String content, {
      RenditionKind kind = RenditionKind.markdown,
    }) async {
      final now = DateTime(2026, 9, 17, 10);
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'src-1',
              kind: SourceKind.webPage,
              capturedAt: now,
            ),
          );
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              id: 'item-1',
              title: 'Un elemento',
              sourceId: 'src-1',
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'rend-1',
              itemId: 'item-1',
              kind: kind,
              isPrimary: true,
              createdAt: now,
              content: Value(content),
            ),
          );
      await classifyExistingItems(db, ids: const UuidV7Generator());
      return 'item-1';
    }

    test(
      'completa fullText/contentHash y fragmenta, reconstruyendo exacto',
      () async {
        const content = 'Primer párrafo.\n\nSegundo párrafo, distinto.';
        await seedSourceWithText(content);

        await fragmentExistingSources(
          db,
          ids: const UuidV7Generator(),
          logger: logger,
        );

        final source = await (db.select(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals('item-1'))).getSingle();
        final chunks =
            await (db.select(db.chunks)
                  ..where((c) => c.itemId.equals('item-1'))
                  ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
                .get();

        expect(source.fullText, content);
        expect(source.contentHash, isNotEmpty);
        expect(chunks.length, greaterThan(1));
        expect(chunks.map((c) => c.content).join(), content);
        expect(await db.select(db.migrationIssues).get(), isEmpty);
      },
    );

    test(
      'un item sin ninguna forma de texto queda sin chunks, sin fallar',
      () async {
        final now = DateTime(2026, 9, 17, 10);
        await db
            .into(db.sources)
            .insert(
              SourcesCompanion.insert(
                id: 'src-1',
                kind: SourceKind.document,
                capturedAt: now,
              ),
            );
        await db
            .into(db.items)
            .insert(
              ItemsCompanion.insert(
                id: 'item-1',
                title: 'Un PDF aún sin texto extraído',
                sourceId: 'src-1',
                processingState: ProcessingState.pending,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await classifyExistingItems(db, ids: const UuidV7Generator());

        await fragmentExistingSources(
          db,
          ids: const UuidV7Generator(),
          logger: logger,
        );

        final source = await (db.select(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals('item-1'))).getSingle();

        expect(source.fullText, isEmpty);
        expect(await db.select(db.chunks).get(), isEmpty);
        expect(await db.select(db.migrationIssues).get(), isEmpty);
      },
    );

    test('un elemento con más de una forma de texto se fragmenta igual, y '
        'queda reportado', () async {
      final now = DateTime(2026, 9, 17, 10);
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'src-1',
              kind: SourceKind.webPage,
              capturedAt: now,
            ),
          );
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              id: 'item-1',
              title: 'Un elemento con dos formas de texto',
              sourceId: 'src-1',
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'rend-vieja',
              itemId: 'item-1',
              kind: RenditionKind.plainText,
              isPrimary: false,
              createdAt: now,
              content: const Value('la vieja, no la principal'),
            ),
          );
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'rend-principal',
              itemId: 'item-1',
              kind: RenditionKind.markdown,
              isPrimary: true,
              createdAt: now.add(const Duration(minutes: 1)),
              content: const Value('la principal, esta es la que cuenta'),
            ),
          );
      await classifyExistingItems(db, ids: const UuidV7Generator());

      await fragmentExistingSources(
        db,
        ids: const UuidV7Generator(),
        logger: logger,
      );

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('item-1'))).getSingle();
      final issues = await db.select(db.migrationIssues).get();

      expect(source.fullText, 'la principal, esta es la que cuenta');
      expect(issues, hasLength(1));
      expect(issues.single.stage, 'classify');
    });

    test('una nota de bloques con JSON corrupto se reporta y no rompe el '
        'resto de la migración', () async {
      await seedSourceWithText(
        '{esto no es JSON válido',
        kind: RenditionKind.blocks,
      );

      await fragmentExistingSources(
        db,
        ids: const UuidV7Generator(),
        logger: logger,
      );

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('item-1'))).getSingle();
      final issues = await db.select(db.migrationIssues).get();

      expect(
        source.fullText,
        isEmpty,
        reason: 'el placeholder no se pisa cuando el chunking falla',
      );
      expect(await db.select(db.chunks).get(), isEmpty);
      expect(issues, hasLength(1));
      expect(issues.single.stage, 'chunk');
    });
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
