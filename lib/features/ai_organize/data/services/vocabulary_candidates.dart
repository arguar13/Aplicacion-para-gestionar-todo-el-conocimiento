import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_organize/domain/services/vocabulary_budget.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// Cuántos valores del vocabulario, como mucho, se describen con vectores
/// por cada elemento que se organiza (F27): un vocabulario de miles se
/// describe de a partes, elemento tras elemento, sin que el primero espere
/// minutos. EmbeddingGemma con un rótulo de pocas palabras tarda poco; 256
/// son ocho tandas de [kVocabularyEmbeddingBatch]. Los que todavía no tienen
/// vector compiten por si el elemento los nombra y por su uso.
const kMaxNewValueVectorsPerItem = 256;

/// De a cuántos rótulos se piden los vectores: la misma tanda que los
/// fragmentos (`ChunkEmbeddingIndexerImpl.batchSize`).
const kVocabularyEmbeddingBatch = 32;

/// El vocabulario de texto de la persona, con lo que dice qué tan pertinente
/// es cada valor para un elemento (F27): cuánto se usa, sus alias y el
/// parecido de su vector con el del elemento. Lo que elige qué parte ve el
/// modelo es `selectVocabularyForPrompt`; esto junta los datos.
///
/// Los vectores de los valores se guardan (`property_value_embedding`) con el
/// rótulo que describen: se calculan una vez, y de nuevo solo si el valor se
/// renombra.
class VocabularyCandidatesReader {
  const VocabularyCandidatesReader({
    required AppDatabase database,
    required EmbeddingService embeddings,
    required Clock clock,
    this.modelVersion = kEmbeddingModelVersion,
  }) : _db = database,
       _embeddings = embeddings,
       _clock = clock;

  final AppDatabase _db;
  final EmbeddingService _embeddings;
  final Clock _clock;

  /// El mismo modelo que los vectores de los fragmentos.
  final String modelVersion;

  /// Las categorías de texto con sus valores, puntuables contra [itemText]
  /// —lo que el modelo va a ver del elemento—. Antes, describe con vectores
  /// hasta [kMaxNewValueVectorsPerItem] valores que no tienen o que se
  /// renombraron, los más usados primero.
  Future<List<VocabularyCategoryCandidates>> read(String itemText) async {
    final definitions = await (_db.select(
      _db.propertyDefinitions,
    )..where((d) => d.type.equalsValue(PropertyValueType.text))).get();
    if (definitions.isEmpty) return const [];
    final definitionIds = [for (final d in definitions) d.id];

    final values = await _db
        .customSelect(
          '''
          SELECT v.id, v.definition_id, v.value,
                 (SELECT COUNT(*) FROM item_property_values a
                   WHERE a.property_value_id = v.id) AS uses,
                 e.label AS embedded_label
            FROM property_values v
            LEFT JOIN property_value_embedding e ON e.value_id = v.id
           WHERE v.definition_id IN (${_marks(definitionIds.length)})
           ORDER BY uses DESC, v.value''',
          variables: [for (final id in definitionIds) Variable.withString(id)],
          readsFrom: {
            _db.propertyValues,
            _db.itemPropertyValues,
            _db.propertyValueEmbeddings,
          },
        )
        .get();

    final aliases = <String, List<String>>{};
    for (final alias in await (_db.select(
      _db.propertyAliases,
    )..where((a) => a.definitionId.isIn(definitionIds))).get()) {
      (aliases[alias.propertyValueId] ??= []).add(alias.alias);
    }

    await _describeMissing([
      for (final row in values)
        if (row.readNullable<String>('embedded_label') !=
            row.read<String>('value'))
          (id: row.read<String>('id'), label: row.read<String>('value')),
    ]);

    final similarity = await _similarities(itemText);

    final byDefinition = <String, List<VocabularyValueCandidate>>{};
    for (final row in values) {
      final id = row.read<String>('id');
      (byDefinition[row.read<String>('definition_id')] ??= []).add(
        VocabularyValueCandidate(
          label: row.read<String>('value'),
          aliases: aliases[id] ?? const [],
          uses: row.read<int>('uses'),
          similarity: similarity[id],
        ),
      );
    }
    return [
      for (final definition in definitions)
        VocabularyCategoryCandidates(
          definitionId: definition.id,
          name: definition.name,
          values: byDefinition[definition.id] ?? const [],
        ),
    ];
  }

  /// Calcula y guarda el vector de hasta [kMaxNewValueVectorsPerItem] de
  /// [missing], por tandas: cada tanda queda guardada.
  Future<void> _describeMissing(
    List<({String id, String label})> missing,
  ) async {
    final now = missing.take(kMaxNewValueVectorsPerItem).toList();
    for (
      var start = 0;
      start < now.length;
      start += kVocabularyEmbeddingBatch
    ) {
      final batch = now.sublist(
        start,
        (start + kVocabularyEmbeddingBatch).clamp(0, now.length),
      );
      final vectors = await _embeddings.embedBatch([
        for (final value in batch) value.label,
      ]);
      final at = _clock();
      await _db.batch((b) {
        for (var i = 0; i < batch.length; i++) {
          b.insert(
            _db.propertyValueEmbeddings,
            PropertyValueEmbeddingsCompanion.insert(
              valueId: batch[i].id,
              label: batch[i].label,
              vector: encodeEmbeddingVector(vectors[i]),
              modelVersion: modelVersion,
              createdAt: at,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }
  }

  /// El coseno entre el vector de [itemText] y el de cada valor que lo tiene
  /// al día —el de un valor renombrado y todavía sin recalcular no cuenta—.
  /// La cuenta, fuera del hilo de la interfaz: miles de vectores.
  Future<Map<String, double>> _similarities(String itemText) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT e.value_id, e.vector FROM property_value_embedding e
            JOIN property_values v ON v.id = e.value_id
           WHERE e.label = v.value''',
          readsFrom: {_db.propertyValueEmbeddings, _db.propertyValues},
        )
        .get();
    if (rows.isEmpty) return const {};
    final item = await _embeddings.embed(itemText);
    return compute(_cosines, (
      item: item,
      values: {
        for (final row in rows)
          row.read<String>('value_id'): row.read<Uint8List>('vector'),
      },
    ));
  }

  static String _marks(int count) => List.filled(count, '?').join(', ');
}

Map<String, double> _cosines(
  ({List<double> item, Map<String, Uint8List> values}) input,
) => {
  for (final MapEntry(key: id, value: blob) in input.values.entries)
    id: cosineSimilarity(input.item, decodeEmbeddingVector(blob)),
};
