import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/mirror_unmirrored_items_v10.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// `mirrorUnmirroredItems` —el catch-up de `schemaVersion` 9→10— probada
/// como función pura contra una base ya en `schemaVersion` 10, sembrando
/// a mano filas en `Items`/`Sources` sin su `KnowledgeEntries`
/// correspondiente: mismo patrón que el resto de las migraciones de
/// backfill del proyecto, para no encadenar `SchemaVerifier` con una
/// segunda siembra sobre la misma conexión (ver la decisión 34 en
/// docs/arquitectura.md).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String> seedUnmirroredItem({
    SourceKind sourceKind = SourceKind.webPage,
    ProcessingState processingState = ProcessingState.ready,
  }) async {
    final now = DateTime(2026, 9, 18);
    final n = DateTime.now().microsecondsSinceEpoch;
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-$n',
            kind: sourceKind,
            capturedAt: now,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: 'item-$n',
            title: 'Un elemento',
            sourceId: 'src-$n',
            processingState: processingState,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return 'item-$n';
  }

  test('un item sin espejo queda clasificado como fuente, con el state '
      'que corresponde', () async {
    final itemId = await seedUnmirroredItem();

    await mirrorUnmirroredItems(db);

    final entry = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId))).getSingle();
    expect(entry.kind, ItemKind.source);
    expect(entry.state, ItemState.processed);

    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(itemId))).getSingle();
    expect(source.sourceType, SourceKind.webPage);
  });

  test('un item sin espejo aún en curso queda captured', () async {
    final itemId = await seedUnmirroredItem(
      processingState: ProcessingState.pending,
    );

    await mirrorUnmirroredItems(db);

    final entry = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId))).getSingle();
    expect(entry.state, ItemState.captured);
  });

  test('una nota manual sin espejo queda clasificada como nota', () async {
    final itemId = await seedUnmirroredItem(sourceKind: SourceKind.manualNote);

    await mirrorUnmirroredItems(db);

    final entry = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId))).getSingle();
    expect(entry.kind, ItemKind.note);

    final note = await (db.select(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(itemId))).getSingle();
    expect(note.noteKind, NoteKind.living);
  });

  test('un item que ya tenía espejo no se duplica ni se toca', () async {
    final itemId = await seedUnmirroredItem();
    final now = DateTime(2026, 9, 18);
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: 'Ya espejado, a mano',
            kind: ItemKind.source,
            state: ItemState.triaged,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );

    await mirrorUnmirroredItems(db);

    final entries = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId))).get();
    expect(entries, hasLength(1));
    expect(entries.single.title, 'Ya espejado, a mano');
    expect(entries.single.state, ItemState.triaged);
  });

  test('correrla dos veces seguidas es idempotente', () async {
    await seedUnmirroredItem();

    await mirrorUnmirroredItems(db);
    final afterFirst = await db.select(db.knowledgeEntries).get();

    await mirrorUnmirroredItems(db);
    final afterSecond = await db.select(db.knowledgeEntries).get();

    expect(afterSecond, hasLength(afterFirst.length));
  });
}
