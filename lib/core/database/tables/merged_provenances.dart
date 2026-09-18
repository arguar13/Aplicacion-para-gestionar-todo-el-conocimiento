import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// La procedencia de un elemento que se fusionó dentro de otro — F7,
/// deduplicación.
///
/// Fusionar dos duplicados conserva un solo `item`, con las dos
/// renditions de texto (ver `MergeDuplicateItemsUseCase`); el que se
/// descarta se borra de verdad, y con él su propia fila de `source`. Sin
/// esta tabla, "fusionar conservando ambas procedencias" perdería de
/// dónde salió el descartado en el momento en que su fila desaparece.
/// Es una copia congelada, no una referencia viva: no hace falta que
/// seguir siendo consistente con nada más una vez guardada.
///
/// No toca el supuesto de "una sola procedencia por elemento"
/// (`KnowledgeItem.source`) que asume el resto de la app — esta tabla es
/// aparte, de solo lectura para mostrar en el detalle, nunca la fuente
/// de verdad de nada.
@DataClassName('MergedProvenanceRow')
@TableIndex(name: 'idx_merged_provenances_item', columns: {#itemId})
class MergedProvenances extends Table {
  TextColumn get id => text()();

  /// El elemento que sobrevivió a la fusión.
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get sourceKind => textEnum<SourceKind>()();
  TextColumn get url => text().nullable()();
  TextColumn get authorName => text().nullable()();
  TextColumn get authorUrl => text().nullable()();
  DateTimeColumn get publishedAt => dateTime().nullable()();

  /// Cuándo se había capturado el elemento descartado, no cuándo se
  /// fusionó — eso es [mergedAt].
  DateTimeColumn get capturedAt => dateTime()();

  DateTimeColumn get mergedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
