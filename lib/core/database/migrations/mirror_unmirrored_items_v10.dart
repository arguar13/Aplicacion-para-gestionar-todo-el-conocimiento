import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';

/// Catch-up de una sola vez: todo lo capturado entre el backfill de F1
/// (`schemaVersion` 8, retirado con los pasos anteriores a v15) y la activación
/// del espejo en vivo de F3 (`LibraryRepositoryImpl._mirrorItem`) nunca
/// pasó por esa clasificación, así que no tiene fila en `item` — sería
/// invisible para la Bandeja de entrada hasta que alguien lo editara de
/// nuevo. Reusa el mismo mapeo puro que el espejo en vivo: un solo
/// criterio de clasificación en todo el proyecto.
///
/// No fragmenta en chunks ni calcula `fullText`/`contentHash` — igual que
/// `LibraryRepositoryImpl._mirrorItem`, ese trabajo es de F5/F7, no de
/// esta migración.
Future<void> mirrorUnmirroredItems(AppDatabase db) async {
  final mirroredIds = db.selectOnly(db.knowledgeEntries)
    ..addColumns([db.knowledgeEntries.id]);
  final unmirrored = await (db.select(
    db.items,
  )..where((i) => i.id.isInQuery(mirroredIds).not())).get();

  for (final item in unmirrored) {
    final source = await (db.select(
      db.sources,
    )..where((s) => s.id.equals(item.sourceId))).getSingleOrNull();
    // La FK de `Items.sourceId` lo impide: no debería poder pasar.
    if (source == null) continue;

    final isNote = itemKindFor(source.kind) == ItemKind.note;

    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: item.id,
            title: item.title,
            subtitle: Value(item.subtitle),
            spaceId: Value(item.spaceId),
            kind: isNote ? ItemKind.note : ItemKind.source,
            state: initialItemStateFor(item.processingState),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            deviceId: kMirrorDeviceIdPlaceholder,
          ),
        );

    if (isNote) {
      await db
          .into(db.knowledgeNotes)
          .insert(
            KnowledgeNotesCompanion.insert(
              itemId: item.id,
              noteKind: NoteKind.living,
              maturity: NoteMaturity.seed,
            ),
          );
      continue;
    }

    await db
        .into(db.knowledgeSources)
        .insert(
          KnowledgeSourcesCompanion.insert(
            itemId: item.id,
            sourceType: source.kind,
            originUrl: Value(source.url),
            authorName: Value(source.authorName),
            authorUrl: Value(source.authorUrl),
            publishedAt: Value(source.publishedAt),
            capturedAt: source.capturedAt,
            originalBlobPath: Value(source.originalFilePath),
            contentHash: '',
            processingStatus: sourceProcessingStatusFor(item.processingState),
          ),
        );
  }
}
