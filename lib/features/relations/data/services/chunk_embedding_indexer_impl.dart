import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/note_text.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// [ChunkEmbeddingIndexer] contra `AppDatabase` + [EmbeddingService].
class ChunkEmbeddingIndexerImpl implements ChunkEmbeddingIndexer {
  const ChunkEmbeddingIndexerImpl({
    required AppDatabase database,
    required EmbeddingService embeddings,
    required Clock clock,
    this.modelVersion = 'embeddinggemma-300m-8bit',
  }) : _db = database,
       _embeddings = embeddings,
       _clock = clock;

  final AppDatabase _db;
  final EmbeddingService _embeddings;
  final Clock _clock;

  /// Identifica con qué modelo se calculó cada vector — hoy siempre el
  /// mismo (D9 de F5: un solo modelo fijo, sin selector), pero la columna
  /// ya existe desde F1 pensando en esto.
  final String modelVersion;

  /// Cuántos fragmentos se piden y se guardan por vez: ver [indexItem].
  static const batchSize = 32;

  @override
  Future<int> indexItem(String itemId) async {
    final chunks = await (_db.select(
      _db.chunks,
    )..where((c) => c.itemId.equals(itemId))).get();
    if (chunks.isEmpty) return 0;

    final existing =
        await (_db.select(_db.embeddings)
              ..where((e) => e.chunkId.isIn(chunks.map((c) => c.id))))
            .map((row) => row.chunkId)
            .get();
    final existingIds = existing.toSet();

    final missing = chunks.where((c) => !existingIds.contains(c.id)).toList();
    if (missing.isEmpty) return 0;

    // Por tandas, guardando cada una (F21): un libro de 500 páginas son unos
    // mil fragmentos, y pedirlos todos juntos era todo o nada —si la app se
    // cerraba a mitad de camino no quedaba ningún vector, y la vez siguiente
    // se empezaba de cero—. Así lo guardado queda, y la próxima pasada sigue
    // desde lo que falta.
    for (var start = 0; start < missing.length; start += batchSize) {
      final batch = missing.sublist(
        start,
        (start + batchSize).clamp(0, missing.length),
      );
      final vectors = await _embeddings.embedBatch(
        batch.map((c) => c.content).toList(),
      );

      final now = _clock();
      await _db.batch((b) {
        for (var i = 0; i < batch.length; i++) {
          b.insert(
            _db.embeddings,
            EmbeddingsCompanion.insert(
              chunkId: batch[i].id,
              vector: encodeEmbeddingVector(vectors[i]),
              modelVersion: modelVersion,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
    return missing.length;
  }

  @override
  Future<int> indexNote(String itemId) async {
    // Una nota en la papelera no se propone como destino de nada: no hace
    // falta describirla.
    final entry = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.isActive)).getSingleOrNull();
    if (entry == null || entry.kind != ItemKind.note) return 0;

    final text = (await noteTextOf(_db, itemId))?.trim() ?? '';
    final pieces = text.isEmpty
        ? const <TextPart>[]
        : splitIntoParts(text, maxChars: kNoteEmbeddingPieceChars);
    final hashes = [for (final piece in pieces) _hashOf(piece.text)];

    // Lo que ya está y describe el mismo tramo, queda; lo de un tramo que
    // cambió, o que ya no existe, se va.
    final stored = await (_db.select(
      _db.noteEmbeddings,
    )..where((e) => e.itemId.equals(itemId))).get();
    final current = <int>{};
    final stale = <int>[];
    for (final row in stored) {
      if (row.seq < hashes.length && hashes[row.seq] == row.textHash) {
        current.add(row.seq);
      } else {
        stale.add(row.seq);
      }
    }
    if (stale.isNotEmpty) {
      await (_db.delete(
        _db.noteEmbeddings,
      )..where((e) => e.itemId.equals(itemId) & e.seq.isIn(stale))).go();
    }

    final missing = [
      for (var seq = 0; seq < pieces.length; seq++)
        if (!current.contains(seq)) seq,
    ];
    // Por tandas, guardando cada una, como los fragmentos de una fuente.
    for (var start = 0; start < missing.length; start += batchSize) {
      final batch = missing.sublist(
        start,
        (start + batchSize).clamp(0, missing.length),
      );
      final vectors = await _embeddings.embedBatch([
        for (final seq in batch) pieces[seq].text,
      ]);

      final now = _clock();
      await _db.batch((b) {
        for (var i = 0; i < batch.length; i++) {
          b.insert(
            _db.noteEmbeddings,
            NoteEmbeddingsCompanion.insert(
              itemId: itemId,
              seq: batch[i],
              vector: encodeEmbeddingVector(vectors[i]),
              textHash: hashes[batch[i]],
              modelVersion: modelVersion,
              createdAt: now,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }
    return missing.length;
  }

  static String _hashOf(String text) =>
      sha256.convert(utf8.encode(text)).toString();
}
