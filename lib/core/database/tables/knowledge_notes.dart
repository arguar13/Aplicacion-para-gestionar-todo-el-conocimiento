import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';

/// La extensión de [KnowledgeEntries] para lo que el usuario construye:
/// mutable, con un subtipo y una madurez. La mayoría no tiene procedencia
/// propia; un derivado (F16) sí, la suya: qué modelo la escribió y cuándo.
@DataClassName('KnowledgeNoteRow')
@TableIndex(name: 'idx_knowledge_notes_dedup_hash', columns: {#dedupHash})
class KnowledgeNotes extends Table {
  @override
  String get tableName => 'note';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get noteKind => textEnum<NoteKind>()();
  TextColumn get maturity => textEnum<NoteMaturity>()();

  /// SHA-256 del contenido normalizado (minúsculas, sin puntuación,
  /// espacios colapsados) — F7, deduplicación. A diferencia de
  /// `KnowledgeSources`, acá no hay ningún `contentHash` previo que
  /// preservar: una nota es mutable, así que este valor se
  /// recalcula en cada guardado, sin guarda de idempotencia — ver
  /// `LibraryRepositoryImpl.save()`.
  TextColumn get dedupHash => text().nullable()();

  /// Huella de 64 bits para casi-duplicados — F7, deduplicación. Ver
  /// `DedupFingerprint`.
  TextColumn get simhash => text().nullable()();

  /// Qué modelo la escribió (F16, D3): nulo para toda nota que el usuario
  /// escribió de punta a punta —la inmensa mayoría—. Se pone una sola vez,
  /// al nacer como derivado; no se toca después.
  TextColumn get generatedByModel => text().nullable()();

  /// Cuándo se generó. Nulo exactamente cuando [generatedByModel] lo es —
  /// los dos juntos, o ninguno—.
  DateTimeColumn get generatedAt => dateTime().nullable()();

  /// Si el usuario ya tocó el contenido después de generarse: en falso al
  /// nacer, pasa a verdadero la primera vez que edita —«pasa a ser suya»—.
  /// Sin fecha ni historial propios: `field_versions` ya anota cuándo se
  /// tocó una forma de contenido, esto solo dice si esa primera vez ya
  /// pasó. Siempre en falso para una nota que no es un derivado.
  BoolColumn get derivedEdited =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}
