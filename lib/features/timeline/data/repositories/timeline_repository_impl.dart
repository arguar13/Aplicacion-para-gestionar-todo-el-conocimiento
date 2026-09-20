import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/repositories/timeline_repository.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

class TimelineRepositoryImpl implements TimelineRepository {
  const TimelineRepositoryImpl({
    required AppDatabase database,
    required LibraryRepository library,
    required TelemetryService telemetry,
  }) : _db = database,
       _library = library,
       _telemetry = telemetry;

  final AppDatabase _db;
  final LibraryRepository _library;
  final TelemetryService _telemetry;

  @override
  Stream<List<TimelineEvent>> watchEvents(LibraryQuery filter) {
    return watchQuery(
      db: _db,
      // Las que componen un evento —el elemento, su fuente, su subtipo y el
      // valor de fecha que tiene puesto— y las que usa la biblioteca para
      // decidir qué elementos entran (el texto vive en las formas).
      tables: [
        _db.knowledgeEntries,
        _db.knowledgeSources,
        _db.renditions,
        _db.knowledgeNotes,
        _db.propertyValues,
        _db.itemPropertyValues,
      ],
      read: () => _read(filter),
      telemetry: _telemetry,
      hint: 'TimelineRepositoryImpl.watchEvents',
    );
  }

  Future<List<TimelineEvent>> _read(LibraryQuery filter) async {
    final allowed = await _allowedItemIds(filter);
    final rows = await _datedRows().get();

    final events = <TimelineEvent>[];
    for (final row in rows) {
      final itemId = row.read(_db.knowledgeEntries.id)!;
      if (allowed != null && !allowed.contains(itemId)) continue;
      events.add(_toEvent(itemId, row));
    }
    return events..sort(compareTimelineEvents);
  }

  /// Los elementos que pasan el filtro, o `null` si no hay filtro y pasan
  /// todos —así no se pide la lista entera de identificadores para nada—.
  ///
  /// El filtro se resuelve en Dart sobre los eventos y no con un `IN (...)`
  /// en la consulta: una bóveda grande sin restricción de fecha puede pasar
  /// el límite de variables de SQLite.
  Future<Set<String>?> _allowedItemIds(LibraryQuery filter) async {
    if (!filter.isFiltered) return null;

    final result = await _library.matchingIds(
      filter.copyWith(limit: null, offset: 0),
    );
    return result.fold(
      (failure) => throw _FilterFailed(failure),
      (ids) => ids.toSet(),
    );
  }

  /// Un renglón por cada fecha de hecho puesta en algún elemento.
  ///
  /// Solo las columnas que hacen falta: son miles de renglones, y armar los
  /// objetos de fila de las cinco tablas para cada uno es trabajo tirado.
  JoinedSelectStatement<HasResultSet, dynamic> _datedRows() {
    final placed = _db.itemPropertyValues;
    final values = _db.propertyValues;
    final definitions = _db.propertyDefinitions;
    final items = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    final notes = _db.knowledgeNotes;

    return _db.selectOnly(placed)
      ..join([
        innerJoin(values, values.id.equalsExp(placed.propertyValueId)),
        innerJoin(definitions, definitions.id.equalsExp(values.definitionId)),
        innerJoin(items, items.id.equalsExp(placed.itemId)),
        // Una nota no tiene fila de fuente: por eso `LEFT`.
        leftOuterJoin(sources, sources.itemId.equalsExp(items.id)),
        leftOuterJoin(notes, notes.itemId.equalsExp(items.id)),
      ])
      ..addColumns([
        items.id,
        items.title,
        sources.sourceType,
        notes.noteKind,
        values.dateFromYear,
        values.dateFromMonth,
        values.dateFromDay,
        values.datePrecision,
        values.dateIsCirca,
      ])
      ..where(
        definitions.isSystem.equals(true) &
            definitions.name.lower().equals(
              kFechaDelHechoCategoryName.toLowerCase(),
            ) &
            values.datePrecision.isNotNull() &
            items.isActive,
      );
  }

  TimelineEvent _toEvent(String itemId, TypedResult row) {
    final values = _db.propertyValues;
    // El filtro de `_datedRows` ya excluye los valores sin precisión.
    final precision = row.readWithConverter(values.datePrecision)!;
    return TimelineEvent(
      itemId: itemId,
      title: row.read(_db.knowledgeEntries.title)!,
      date: HistoricalDate.fromStored(
        astronomicalYear: row.read(values.dateFromYear)!,
        precision: precision,
        month: row.read(values.dateFromMonth),
        day: row.read(values.dateFromDay),
        isCirca: row.read(values.dateIsCirca),
      ),
      sourceKind:
          row.readWithConverter(_db.knowledgeSources.sourceType) ??
          SourceKind.manualNote,
      noteKind: row.readWithConverter(_db.knowledgeNotes.noteKind),
    );
  }
}

/// La biblioteca no pudo resolver el filtro. Viaja como error del stream, que
/// es como esta lectura avisa de sus fallos; la biblioteca ya lo registró.
class _FilterFailed implements Exception {
  const _FilterFailed(this.failure);

  final Failure failure;

  @override
  String toString() =>
      'No se pudo resolver el filtro de la línea de tiempo: ${failure.message}';
}
