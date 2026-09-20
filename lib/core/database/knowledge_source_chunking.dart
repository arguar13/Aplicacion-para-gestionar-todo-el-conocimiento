import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/chunking_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Qué pasó al intentar dejar al día los chunks de una fuente.
enum SourceChunkingOutcome {
  /// Los chunks ya correspondían al texto de la fuente —su `contentHash` es el
  /// del texto de hoy y hay chunks—: no se tocó nada.
  alreadyDone,

  /// La fuente todavía no tiene ninguna rendition de texto —un archivo
  /// sin procesar, o cuyo procesamiento falló—: nada que fragmentar
  /// todavía.
  noTextYet,

  /// Se fragmentó por primera vez: `contentHash` quedó poblado y sus chunks,
  /// insertados.
  populated,

  /// El texto de la fuente cambió desde la última vez —una transcripción
  /// rehecha con un modelo mejor, por ejemplo—: los chunks viejos se
  /// reemplazaron por los del texto nuevo.
  rebuilt,

  /// El chunking falló o los fragmentos no reconstruyen el texto
  /// íntegro: se reportó en `MigrationIssues` y no se tocó nada —los chunks
  /// que hubiera quedan como estaban, nunca se pierde el texto en sí.
  failed,
}

/// La forma de texto de la que sale el texto íntegro de una fuente: la
/// principal, o —si ninguna lo es— la que se guardó primero.
///
/// F10: el texto íntegro se guarda UNA vez, en esta forma. Antes lo copiaba
/// además `source.full_text`; los chunks y su índice de texto lo indexan, no
/// lo reemplazan.
Future<RenditionRow?> sourceTextRendition(AppDatabase db, String itemId) async {
  final renditions = await (db.select(
    db.renditions,
  )..where((r) => r.itemId.equals(itemId) & r.content.isNotNull())).get();
  if (renditions.isEmpty) return null;
  return _pickPrimaryOrOldest(renditions);
}

/// Deja al día los chunks de UNA fuente respecto del texto de su forma
/// principal, y su `contentHash` —el SHA-256 de ese texto—.
///
/// Es la función que usa todo el que necesita chunks: `save()` al guardar, el
/// motor de relaciones, y las migraciones. Mismo algoritmo que
/// `fragmentExistingSources` (F1, `fragment_existing_sources_v8.dart`), pero
/// idempotente por el hash del texto de hoy y no por "ya se fragmentó alguna
/// vez": si el texto no cambió no hace nada, y si cambió reemplaza los chunks
/// —y con ellos sus embeddings, que ya no describen el texto—.
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
  // Una nota no tiene fila de fuente, y no se fragmenta: ver
  // `LibraryRepositoryImpl._syncChunks`.
  if (source == null) return SourceChunkingOutcome.alreadyDone;

  final chosen = await sourceTextRendition(db, itemId);
  if (chosen == null) return SourceChunkingOutcome.noTextYet;

  final fullText = chosen.content!;
  final contentHash = sha256.convert(utf8.encode(fullText)).toString();

  final existing =
      await (db.selectOnly(db.chunks)
            ..addColumns([db.chunks.id])
            ..where(db.chunks.itemId.equals(itemId))
            ..limit(1))
          .get();
  final hasChunks = existing.isNotEmpty;

  if (source.contentHash == contentHash && (hasChunks || fullText.isEmpty)) {
    return SourceChunkingOutcome.alreadyDone;
  }

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

  // Los chunks viejos, si los hay, describen un texto que ya no es el de la
  // fuente; sus embeddings se van con ellos, en cascada.
  final rebuilding = hasChunks;
  if (rebuilding) {
    await (db.delete(db.chunks)..where((c) => c.itemId.equals(itemId))).go();
  }

  await (db.update(db.knowledgeSources)..where((s) => s.itemId.equals(itemId)))
      .write(KnowledgeSourcesCompanion(contentHash: Value(contentHash)));

  // De una sola vez: una fuente larga tiene cientos de chunks, y con miles de
  // fuentes en una migración, insertarlos de a uno era lo que más tardaba.
  await db.batch((batch) {
    batch.insertAll(db.chunks, [
      for (final chunk in chunks)
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
    ]);
  });

  return rebuilding
      ? SourceChunkingOutcome.rebuilt
      : SourceChunkingOutcome.populated;
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
