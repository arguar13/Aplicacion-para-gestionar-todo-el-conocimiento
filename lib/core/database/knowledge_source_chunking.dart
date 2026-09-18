import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/chunking_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Qué pasó al intentar poblar `chunk`/`fullText`/`contentHash` de una
/// fuente.
enum SourceChunkingOutcome {
  /// `contentHash` ya estaba poblado —de una corrida anterior, o del
  /// backfill histórico de F1—: no se tocó nada.
  alreadyDone,

  /// La fuente todavía no tiene ninguna rendition de texto —un archivo
  /// sin procesar, o cuyo procesamiento falló—: nada que fragmentar
  /// todavía.
  noTextYet,

  /// Se fragmentó con éxito: `fullText`/`contentHash` quedaron poblados
  /// y sus chunks, insertados.
  populated,

  /// El chunking falló o los fragmentos no reconstruyen el texto
  /// íntegro: se reportó en `MigrationIssues` y no se tocó nada —el
  /// placeholder vacío queda igual, nunca se pierde el texto en sí.
  failed,
}

/// Puebla `chunk`/`fullText`/`contentHash` de UNA fuente —mismo
/// algoritmo que `fragmentExistingSources` (F1,
/// `fragment_existing_sources_v8.dart`), parametrizado por [itemId] en
/// vez de recorrer toda la tabla, y con
/// idempotencia al principio. Compartida entre el backfill de catch-up
/// de F5 (`backfillSourceChunks`, migración v12) y el hook en vivo del
/// motor de relaciones (`GenerateRelationSuggestionsUseCase`) — no toca
/// `fragment_existing_sources_v8.dart`, código de F1 ya cerrado y
/// probado, se acepta duplicar esta lógica en vez de reabrirlo.
///
/// Una fuente cuyo texto no reconstruye exacto —o cualquier error al
/// fragmentarla— **no** se pisa ni queda a medias: se reporta en
/// `MigrationIssues` y se sigue, nunca se pierde el texto.
Future<SourceChunkingOutcome> chunkAndPersistSource(
  AppDatabase db, {
  required String itemId,
  required IdGenerator ids,
  String reportedBy = 'f5_relation_engine',
}) async {
  final source = await (db.select(
    db.knowledgeSources,
  )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
  if (source == null || source.contentHash.isNotEmpty) {
    return SourceChunkingOutcome.alreadyDone;
  }

  final renditions = await (db.select(
    db.renditions,
  )..where((r) => r.itemId.equals(itemId))).get();
  final textRenditions = renditions.where((r) => r.content != null).toList();

  if (textRenditions.isEmpty) {
    return SourceChunkingOutcome.noTextYet;
  }

  final chosen = _pickPrimaryOrOldest(textRenditions);
  final fullText = chosen.content!;
  final contentHash = sha256.convert(utf8.encode(fullText)).toString();

  const chunker = ChunkingService();
  List<TextChunk> chunks;
  try {
    chunks = chunker.chunk(fullText, kind: chosen.kind);
  } on Object catch (e) {
    await _reportIssue(
      db,
      ids: ids,
      itemId: itemId,
      reportedBy: reportedBy,
      message: 'chunking falló: $e',
    );
    return SourceChunkingOutcome.failed;
  }

  if (!chunkingInvariantHolds(fullText, chunks)) {
    await _reportIssue(
      db,
      ids: ids,
      itemId: itemId,
      reportedBy: reportedBy,
      message:
          'los fragmentos generados no reconstruyen el texto íntegro '
          'byte a byte; no se guardó ningún chunk para este elemento',
    );
    return SourceChunkingOutcome.failed;
  }

  await (db.update(
    db.knowledgeSources,
  )..where((s) => s.itemId.equals(itemId))).write(
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
            itemId: itemId,
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

  return SourceChunkingOutcome.populated;
}

/// Mismo criterio que `fragmentExistingSources`: se prefiere la
/// rendition marcada como principal; sin ninguna marcada, la primera
/// que se guardó.
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
  required String reportedBy,
  required String message,
}) {
  return db
      .into(db.migrationIssues)
      .insert(
        MigrationIssuesCompanion.insert(
          id: ids.next(),
          migration: reportedBy,
          itemId: itemId,
          stage: 'chunk',
          message: message,
          createdAt: DateTime.now(),
        ),
      );
}
