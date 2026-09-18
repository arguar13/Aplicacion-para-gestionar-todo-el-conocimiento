import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';

/// La extensión de [KnowledgeEntries] para lo capturado del exterior:
/// procedencia, y el texto íntegro, nunca editado ni resumido.
///
/// A diferencia de la tabla vieja `Sources` —que puede estar compartida
/// por varios `Items` cuando el mismo archivo se captura dos veces—, acá
/// `itemId` es la propia clave primaria: una fila de `source` pertenece a
/// un solo `item`. Es una divergencia semántica real entre los dos
/// esquemas, no un detalle de implementación — la migración que puebla
/// esta tabla duplica los datos de una fuente compartida, una fila por
/// cada `item` que la referenciaba.
@DataClassName('KnowledgeSourceRow')
@TableIndex(name: 'idx_knowledge_sources_content_hash', columns: {#contentHash})
@TableIndex(name: 'idx_knowledge_sources_dedup_hash', columns: {#dedupHash})
@TableIndex(
  name: 'idx_knowledge_sources_processing_status',
  columns: {#processingStatus},
)
class KnowledgeSources extends Table {
  @override
  String get tableName => 'source';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceType => textEnum<SourceKind>()();
  TextColumn get originUrl => text().nullable()();
  TextColumn get authorName => text().nullable()();
  TextColumn get authorUrl => text().nullable()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get originalBlobPath => text().nullable()();

  /// El texto ÍNTEGRO, para siempre. Nunca se resume ni se reescribe.
  TextColumn get fullText => text().withDefault(const Constant(''))();

  /// SHA-256 de [fullText] SIN normalizar — sirve de guarda de
  /// idempotencia para el chunking (`chunkAndPersistSource`: "¿ya
  /// corrió?"), no para comparar contra otro elemento.
  TextColumn get contentHash => text()();

  /// SHA-256 de [fullText] normalizado (minúsculas, sin puntuación,
  /// espacios colapsados) — F7, deduplicación: detecta duplicados
  /// exactos entre dos elementos aunque difieran en formato.
  TextColumn get dedupHash => text().nullable()();

  /// Huella de 64 bits para casi-duplicados — F7, deduplicación. Ver
  /// `DedupFingerprint`.
  TextColumn get simhash => text().nullable()();

  TextColumn get processingStatus => textEnum<SourceProcessingStatus>()();
  TextColumn get processingError => text().nullable()();
  IntColumn get processingAttempts =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}
