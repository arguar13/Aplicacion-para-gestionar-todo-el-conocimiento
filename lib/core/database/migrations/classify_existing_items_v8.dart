import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Clasifica cada `Items`/`Sources` existente como fuente o nota en las
/// tablas nuevas del modelo de conocimiento —paso de la migración a
/// `schemaVersion` 8, ver `app_database.dart`—.
///
/// Sin tocar todavía el texto ni los chunks: `KnowledgeSources.fullText`
/// queda con su valor por defecto (vacío) y `contentHash` con un
/// placeholder explícito. `fragmentExistingSources`, en un paso posterior
/// de la misma migración, completa las dos cosas leyendo la rendition de
/// texto de cada fuente y actualiza estas mismas filas — separado a
/// propósito: clasificar no necesita tocar `Renditions` en absoluto, y
/// mezclar las dos cosas en una sola función haría más difícil entender
/// qué falla si algo falla.
///
/// La regla de clasificación es una lectura directa de una columna que ya
/// existe, no una heurística: una nota manual o armada con el editor de
/// bloques —las dos únicas formas hoy de que el usuario cree contenido sin
/// que venga de afuera— tienen `Sources.kind == SourceKind.manualNote`.
/// Cualquier otro tipo de fuente entra como fuente.
Future<void> classifyExistingItems(
  AppDatabase db, {
  required IdGenerator ids,
}) async {
  // Un solo id de dispositivo para toda la corrida: todo lo que ya estaba
  // en la bóveda antes de esta migración "lo escribió" el mismo
  // dispositivo, en los hechos.
  final deviceId = ids.next();
  final items = await db.select(db.items).get();

  for (final item in items) {
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
            deviceId: deviceId,
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
            // `contentHash` no tiene valor por defecto —es parte de la
            // identidad de la fuente, no algo razonable de dejar vacío
            // silenciosamente—, así que el placeholder es explícito.
            contentHash: '',
            processingStatus: sourceProcessingStatusFor(item.processingState),
          ),
        );
  }
}
