import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';

/// La extensión de [KnowledgeEntries] para lo capturado del exterior: su
/// procedencia y el estado de su procesamiento.
///
/// El texto íntegro NO está acá: vive UNA vez, en la forma de texto principal
/// del elemento (`renditions`), nunca editado ni resumido. Los chunks lo
/// parten para recuperarlo y citarlo, y su índice de texto lo indexa; ninguno
/// lo reemplaza. Hasta F10 esta tabla tenía además una copia (`full_text`).
///
/// `itemId` es la propia clave primaria: una fila de `source` pertenece a un
/// solo `item`. Antes de F10 la tabla vieja de fuentes podía estar compartida
/// por varios elementos cuando el mismo archivo se capturaba dos veces; la
/// migración que pobló esta tabla duplicó esos datos, una fila por elemento.
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

  /// El idioma del original, como código de dos letras: ver
  /// `Source.language` (F22, esquema v32).
  TextColumn get language => text().nullable()();

  /// «Solo el libro» (F30, v38, decisión 68): el texto se soltó a propósito y
  /// queda el archivo. La cola no se lo vuelve a extraer sola —sin esta marca,
  /// un documento sin texto es uno por leer—; «Volver a extraer», pedido a
  /// mano, sí, y al traer el texto la quita. Ver `Source.onlyFile`.
  ///
  /// Es una decisión de este dispositivo sobre su copia y no un campo con
  /// linaje: no se registra en `field_version` ni se fusiona campo a campo.
  /// Viaja con un elemento NUEVO —su fila de `source` se copia entera, y
  /// llega sin texto—, pero no cambia la de un elemento que la otra bóveda ya
  /// tiene con su texto: una fusión no borra textos.
  BoolColumn get onlyFile => boolean().withDefault(const Constant(false))();

  /// SHA-256 del texto de la forma principal SIN normalizar — sirve de guarda
  /// de idempotencia para el chunking (`chunkAndPersistSource`: "¿ya
  /// corrió?"), no para comparar contra otro elemento.
  TextColumn get contentHash => text()();

  /// SHA-256 del texto normalizado (minúsculas, sin puntuación, espacios
  /// colapsados) — F7, deduplicación: detecta duplicados exactos entre dos
  /// elementos aunque difieran en formato.
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
