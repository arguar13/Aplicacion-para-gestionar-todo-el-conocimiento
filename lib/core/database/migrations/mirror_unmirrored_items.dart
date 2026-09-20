import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Completa el modelo nuevo con lo que solo estaba en el viejo: todo elemento
/// de `items` sin su fila en `item` la recibe, con su fuente o su nota.
///
/// Lo usa el paso v18 antes de re-apuntar las claves foráneas a `item`: desde
/// P2 de F10 toda lectura sale de ahí, y un elemento sin su fila sería
/// invisible. Antes existió como catch-up de una sola vez entre el backfill de
/// F1 y el espejo en vivo de F3.
///
/// Lee las tablas viejas con SQL y no por sus clases: F10 las retira, y este
/// paso tiene que poder correr contra una base que todavía las tiene aunque el
/// código ya no las conozca. Reusa el mismo mapeo puro que el resto del
/// proyecto (`itemKindFor`, `initialItemStateFor`): un solo criterio de
/// clasificación.
///
/// No fragmenta en chunks ni calcula `contentHash`: eso lo hace `save()` al
/// guardar y el backfill de v16, no esta migración.
Future<void> mirrorUnmirroredItems(AppDatabase db) async {
  final unmirrored = await db.customSelect('''
SELECT i.id AS id, i.title AS title, i.subtitle AS subtitle, i.notes AS notes,
       i.space_id AS space_id, i.processing_state AS processing_state,
       i.created_at AS created_at, i.updated_at AS updated_at,
       s.kind AS kind, s.url AS url, s.author_name AS author_name,
       s.author_url AS author_url, s.published_at AS published_at,
       s.captured_at AS captured_at,
       s.original_file_path AS original_file_path
  FROM items i
  LEFT JOIN sources s ON s.id = i.source_id
 WHERE i.id NOT IN (SELECT id FROM item)
 ORDER BY i.id''').get();

  for (final row in unmirrored) {
    final id = row.read<String>('id');
    final kindName = row.readNullable<String>('kind');
    // La clave foránea de `items.source_id` lo impide: no debería poder pasar.
    if (kindName == null) continue;

    final sourceKind = SourceKind.values.byName(kindName);
    final processing = ProcessingState.values.byName(
      row.read<String>('processing_state'),
    );
    final itemKind = itemKindFor(sourceKind);
    final createdAt = row.read<DateTime>('created_at');

    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: id,
            title: row.read<String>('title'),
            subtitle: Value(row.readNullable<String>('subtitle')),
            notes: Value(row.readNullable<String>('notes')),
            spaceId: Value(row.readNullable<String>('space_id')),
            kind: itemKind,
            state: initialItemStateFor(processing),
            createdAt: createdAt,
            updatedAt: row.read<DateTime>('updated_at'),
            deviceId: kMirrorDeviceIdPlaceholder,
          ),
        );

    if (itemKind == ItemKind.note) {
      await db
          .into(db.knowledgeNotes)
          .insert(
            KnowledgeNotesCompanion.insert(
              itemId: id,
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
            itemId: id,
            sourceType: sourceKind,
            originUrl: Value(row.readNullable<String>('url')),
            authorName: Value(row.readNullable<String>('author_name')),
            authorUrl: Value(row.readNullable<String>('author_url')),
            publishedAt: Value(row.readNullable<DateTime>('published_at')),
            capturedAt: row.read<DateTime>('captured_at'),
            originalBlobPath: Value(
              row.readNullable<String>('original_file_path'),
            ),
            contentHash: '',
            processingStatus: sourceProcessingStatusFor(processing),
          ),
        );
  }
}
