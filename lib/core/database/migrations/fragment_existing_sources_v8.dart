import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/chunking_service.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/util/id_generator.dart';

const _migrationName = 'f1_knowledge_model';

/// Completa `fullText`/`contentHash` y fragmenta en `chunk` cada fila de
/// `KnowledgeSources` que dejó `classifyExistingItems` —ver
/// `classify_existing_items_v8.dart`— con el placeholder vacío.
///
/// Separado de la clasificación a propósito: acá es donde se lee
/// `Renditions`, se calcula el hash y se fragmenta con [ChunkingService],
/// y ninguna de esas tres cosas tiene que ver con decidir si un `Item` es
/// fuente o nota.
///
/// Una fuente cuyo texto no reconstruye exacto —o cualquier error al
/// fragmentarla— **no** se pisa ni queda a medias: se reporta en
/// `migration_issue` con `stage: 'chunk'` y se sigue con la siguiente. Es
/// la regla central del refactor: perder la posibilidad de indexar algo es
/// aceptable, perder el texto en sí no lo es —y acá no se pierde, porque
/// nunca se le vuelve a tocar el placeholder vacío a una fila que falló.
Future<void> fragmentExistingSources(
  AppDatabase db, {
  required IdGenerator ids,
  required AppLogger logger,
}) async {
  const chunker = ChunkingService();
  final sources = await db.select(db.knowledgeSources).get();

  for (final source in sources) {
    final renditions = await (db.select(
      db.renditions,
    )..where((r) => r.itemId.equals(source.itemId))).get();
    final textRenditions = renditions.where((r) => r.content != null).toList();

    if (textRenditions.isEmpty) {
      // Nada que fragmentar —un archivo sin texto extraído todavía, o
      // cuyo procesamiento falló—: la fila ya quedó con el placeholder
      // vacío desde la clasificación, y ahí se queda.
      continue;
    }

    final chosen = textRenditions.length == 1
        ? textRenditions.single
        : _pickPrimaryOrOldest(textRenditions);
    if (textRenditions.length > 1) {
      await _reportIssue(
        db,
        ids: ids,
        itemId: source.itemId,
        stage: 'classify',
        message:
            'el elemento tenía ${textRenditions.length} formas de texto; '
            'se usó la rendition ${chosen.id} para el texto íntegro',
      );
      logger.warning(
        'classifyExistingItems: ${source.itemId} tenía '
        '${textRenditions.length} formas de texto, se usó ${chosen.id}',
      );
    }

    final fullText = chosen.content!;
    final contentHash = sha256.convert(utf8.encode(fullText)).toString();

    List<TextChunk> chunks;
    try {
      chunks = chunker.chunk(fullText, kind: chosen.kind);
    } on Object catch (e, stackTrace) {
      await _reportIssue(
        db,
        ids: ids,
        itemId: source.itemId,
        stage: 'chunk',
        message: 'chunking falló: $e',
      );
      logger.error(
        'fragmentExistingSources: ${source.itemId} no se pudo fragmentar',
        e,
        stackTrace,
      );
      continue;
    }

    if (!chunkingInvariantHolds(fullText, chunks)) {
      await _reportIssue(
        db,
        ids: ids,
        itemId: source.itemId,
        stage: 'chunk',
        message:
            'los fragmentos generados no reconstruyen el texto íntegro '
            'byte a byte; no se guardó ningún chunk para este elemento',
      );
      logger.error(
        'fragmentExistingSources: ${source.itemId} no reconstruye exacto',
      );
      continue;
    }

    await (db.update(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(source.itemId))).write(
      KnowledgeSourcesCompanion(
        fullText: Value(fullText),
        contentHash: Value(contentHash),
      ),
    );

    for (final chunk in chunks) {
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: ids.next(),
              itemId: source.itemId,
              seq: chunk.seq,
              content: chunk.text,
              charStart: chunk.charStart,
              charEnd: chunk.charEnd,
              startMs: Value(chunk.startMs),
              endMs: Value(chunk.endMs),
              pageNumber: Value(chunk.pageNumber),
              headingPath: Value(chunk.headingPath),
            ),
          );
    }
  }
}

/// Cuando un elemento tiene más de una forma de texto —no debería pasar
/// hoy, ver el hallazgo sobre los transformers en docs/arquitectura.md,
/// pero el backfill no puede asumirlo—, se prefiere la marcada como
/// principal; sin ninguna marcada, la primera que se guardó.
RenditionRow _pickPrimaryOrOldest(List<RenditionRow> renditions) {
  for (final rendition in renditions) {
    if (rendition.isPrimary) return rendition;
  }
  final sorted = [...renditions]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return sorted.first;
}

Future<void> _reportIssue(
  AppDatabase db, {
  required IdGenerator ids,
  required String itemId,
  required String stage,
  required String message,
}) {
  return db
      .into(db.migrationIssues)
      .insert(
        MigrationIssuesCompanion.insert(
          id: ids.next(),
          migration: _migrationName,
          itemId: itemId,
          stage: stage,
          message: message,
          createdAt: DateTime.now(),
        ),
      );
}
