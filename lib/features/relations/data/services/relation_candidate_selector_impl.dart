import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/note_text.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';

/// Cuántos caracteres del primer chunk de un candidato se muestran como
/// excerpt — mismo límite que ya usa el diálogo manual de sugerencias del
/// grafo (`ai_suggest_relations_dialog.dart`), para que el LLM reciba un
/// fragmento de tamaño consistente sin importar por qué vía llegó.
const _excerptMaxLength = 280;

/// [RelationCandidateSelector] contra `AppDatabase`: lee los embeddings ya
/// persistidos por `ChunkEmbeddingIndexer` —los de los fragmentos de las
/// fuentes y los de los tramos de las notas—, sin calcular ninguno nuevo —
/// si el semilla o un candidato todavía no tienen embeddings, simplemente
/// no participan de la preselección.
class RelationCandidateSelectorImpl implements RelationCandidateSelector {
  const RelationCandidateSelectorImpl({required AppDatabase database})
    : _db = database;

  final AppDatabase _db;

  @override
  Future<List<ScoredRelationCandidate>> selectCandidates({
    required String seedItemId,
    int limit = 15,
    double minSimilarity = 0.5,
  }) => _rank(
    seedItemId: seedItemId,
    limit: limit,
    minSimilarity: minSimilarity,
    includeNotes: true,
  );

  @override
  Future<List<ScoredRelationCandidate>> selectSourceCandidates({
    required String seedItemId,
    int limit = 15,
    double minSimilarity = 0.5,
  }) => _rank(
    seedItemId: seedItemId,
    limit: limit,
    minSimilarity: minSimilarity,
    includeNotes: false,
  );

  /// Los candidatos más parecidos a [seedItemId]; las notas, si
  /// [includeNotes].
  Future<List<ScoredRelationCandidate>> _rank({
    required String seedItemId,
    required int limit,
    required double minSimilarity,
    required bool includeNotes,
  }) async {
    // El semilla se describe por sus fragmentos si es una fuente, o por sus
    // tramos si es una nota (F27): uno de los dos está vacío.
    final seedVectors = <Uint8List>[
      ...await _blobsFor(
        await (_db.selectOnly(_db.chunks)
              ..addColumns([_db.chunks.id])
              ..where(_db.chunks.itemId.equals(seedItemId)))
            .map((row) => row.read(_db.chunks.id)!)
            .get(),
      ),
      ...(await _noteVectors(only: seedItemId))[seedItemId] ?? const [],
    ];
    if (seedVectors.isEmpty) return const [];

    // Solo de elementos vivos: sugerir vincular con algo que está en la
    // papelera sería mandar al usuario a un elemento que ya borró.
    //
    // Solo qué fragmento es de qué elemento, sin su texto (F21): con diez
    // libros son diez mil fragmentos, y traer el texto de todos para
    // quedarse al final con el extracto de quince era cargar en memoria la
    // bóveda entera cada vez que se procesaba algo.
    final chunkId = _db.chunks.id;
    final chunkItemId = _db.chunks.itemId;
    final rows =
        await (_db.selectOnly(_db.chunks)
              ..addColumns([chunkId, chunkItemId])
              ..where(
                chunkItemId.equals(seedItemId).not() &
                    itemIsActive(_db, chunkItemId),
              ))
            .get();
    final chunkIdsByItem = <String, List<String>>{};
    for (final row in rows) {
      chunkIdsByItem
          .putIfAbsent(row.read(chunkItemId)!, () => [])
          .add(row.read(chunkId)!);
    }

    final vectorsByItem = <String, List<Uint8List>>{};
    for (final MapEntry(key: itemId, value: chunkIds)
        in chunkIdsByItem.entries) {
      final vectors = await _blobsFor(chunkIds);
      if (vectors.isNotEmpty) vectorsByItem[itemId] = vectors;
    }
    // Las notas, por los vectores de sus tramos (F27): son candidatas igual
    // que las fuentes.
    if (includeNotes) {
      for (final MapEntry(key: itemId, value: vectors) in (await _noteVectors(
        except: seedItemId,
      )).entries) {
        (vectorsByItem[itemId] ??= []).addAll(vectors);
      }
    }

    // Decodificar y promediar miles de vectores —diez libros son diez mil—
    // fuera del hilo de la interfaz: en el teléfono trababa la pantalla un
    // segundo o más cada vez que algo terminaba de procesarse, y crecía con
    // la bóveda (F21).
    final scores = await compute(_scoreCandidates, (
      seed: seedVectors,
      others: vectorsByItem,
      minSimilarity: minSimilarity,
    ));

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // El título y el extracto, solo de los que quedaron.
    final scored = <ScoredRelationCandidate>[];
    for (final MapEntry(key: itemId, value: score) in ranked) {
      if (scored.length == limit) break;

      final title = await _titleFor(itemId);
      if (title == null) continue;

      scored.add(
        ScoredRelationCandidate(
          itemId: itemId,
          title: title,
          excerpt: await _excerptFor(itemId),
          score: score,
        ),
      );
    }
    return scored;
  }

  /// Los vectores guardados de [chunkIds], sin decodificar.
  Future<List<Uint8List>> _blobsFor(List<String> chunkIds) async {
    if (chunkIds.isEmpty) return const [];
    final vector = _db.embeddings.vector;
    return (_db.selectOnly(_db.embeddings)
          ..addColumns([vector])
          ..where(_db.embeddings.chunkId.isIn(chunkIds)))
        .map((row) => row.read(vector)!)
        .get();
  }

  Future<String?> _titleFor(String itemId) async {
    final row = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.isActive)).getSingleOrNull();
    return row?.title;
  }

  /// Los vectores guardados de las notas vivas, sin decodificar, por nota:
  /// [only] la de esa, o todas menos [except].
  Future<Map<String, List<Uint8List>>> _noteVectors({
    String? only,
    String? except,
  }) async {
    final notes = _db.noteEmbeddings;
    var filter = itemIsActive(_db, notes.itemId);
    if (only != null) filter &= notes.itemId.equals(only);
    if (except != null) filter &= notes.itemId.equals(except).not();
    final query = _db.selectOnly(notes)
      ..addColumns([notes.itemId, notes.vector])
      ..where(filter);
    final byItem = <String, List<Uint8List>>{};
    for (final row in await query.get()) {
      final itemId = row.read(notes.itemId)!;
      final vector = row.read(notes.vector)!;
      (byItem[itemId] ??= []).add(vector);
    }
    return byItem;
  }

  /// El comienzo de [itemId]: su primer fragmento si es una fuente, o el
  /// principio de su texto si es una nota.
  Future<String> _excerptFor(String itemId) async {
    final first =
        await (_db.select(_db.chunks)
              ..where((c) => c.itemId.equals(itemId))
              ..orderBy([(c) => OrderingTerm.asc(c.seq)])
              ..limit(1))
            .getSingleOrNull();
    final content = (first?.content ?? await noteTextOf(_db, itemId) ?? '')
        .trim();
    return content.length > _excerptMaxLength
        ? '${content.substring(0, _excerptMaxLength)}…'
        : content;
  }
}

/// Qué tan parecido es cada elemento de `others` a `seed`, por el coseno
/// entre los centros de sus vectores; solo los que llegan a
/// `minSimilarity`. En un isolate aparte: ver
/// [RelationCandidateSelectorImpl.selectCandidates].
Map<String, double> _scoreCandidates(
  ({
    List<Uint8List> seed,
    Map<String, List<Uint8List>> others,
    double minSimilarity,
  })
  input,
) {
  List<double> centroidOf(List<Uint8List> blobs) =>
      centroid([for (final blob in blobs) decodeEmbeddingVector(blob)]);

  final seedCentroid = centroidOf(input.seed);
  return {
    for (final MapEntry(key: itemId, value: blobs) in input.others.entries)
      if (cosineSimilarity(seedCentroid, centroidOf(blobs)) case final score
          when score >= input.minSimilarity)
        itemId: score,
  };
}
