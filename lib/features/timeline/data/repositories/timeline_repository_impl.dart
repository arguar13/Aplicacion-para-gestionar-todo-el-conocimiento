import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/processed_entries.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/repositories/timeline_repository.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

/// [TimelineRepository] contra la base.
///
/// **Lo que entra** (F41, paso 6): la línea de tiempo se arma con lo
/// procesado, no con la Biblioteca. Entran las fechas de los documentos
/// procesados —las que puso la IA al organizarlos y las que la persona les
/// agregó— y los hechos que la persona escribió a mano en una nota suya, como
/// los «Hechos sueltos», que no salen de ninguna fuente. Lo que las fuentes ya
/// tenían queda en ellas y no se ve acá: empieza de cero.
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
      // Las que componen un evento —el elemento, su fuente, su subtipo, el
      // valor de fecha que tiene puesto y los hechos fechados de su texto— y
      // las que usa la biblioteca para decidir qué elementos entran (el texto
      // vive en las formas).
      tables: [
        _db.knowledgeEntries,
        _db.knowledgeSources,
        _db.renditions,
        _db.knowledgeNotes,
        _db.propertyValues,
        _db.itemPropertyValues,
        _db.datedEvents,
        // Lo procesado (F41, paso 6): qué entra, y dónde buscan el texto los
        // filtros.
        _db.processedDocuments,
        _db.processedParts,
      ],
      read: () => _read(filter),
      telemetry: _telemetry,
      hint: 'TimelineRepositoryImpl.watchEvents',
    );
  }

  Future<List<TimelineEvent>> _read(LibraryQuery filter) async {
    final allowed = await _allowedItemIds(filter);
    final rows = await _datedRows(filter.scope).get();
    final facts = await _datedEventRows(filter.scope).get();

    // Los dos orígenes pasan por el mismo filtro: qué elementos entran lo
    // decide la biblioteca, sea cual sea el hecho.
    final events = <TimelineEvent>[];
    for (final row in rows) {
      final itemId = row.read(_db.knowledgeEntries.id)!;
      if (allowed != null && !allowed.contains(itemId)) continue;
      events.add(_toEvent(itemId, row));
    }
    for (final row in facts) {
      final itemId = row.read(_db.datedEvents.itemId)!;
      if (allowed != null && !allowed.contains(itemId)) continue;
      events.add(_toDatedEvent(itemId, row));
    }
    return events..sort(compareTimelineEvents);
  }

  /// Los elementos que pasan el filtro, o `null` si no hay filtro y pasan
  /// todos —así no se pide la lista entera de identificadores para nada—.
  ///
  /// El filtro se resuelve en Dart sobre los eventos y no con un `IN (...)`
  /// en la consulta: una bóveda grande sin restricción de fecha puede pasar
  /// el límite de variables de SQLite.
  ///
  /// Se resuelve en el corpus de [filter] (F41, paso 6): en lo procesado, el
  /// texto se busca en lo que la persona eligió de cada fuente, y el tipo es el
  /// de la fuente. Un filtro que solo dice qué documentos —el chip
  /// «Documento»— no pregunta nada: son esos, también una nota de la persona
  /// como «Hechos sueltos».
  Future<Set<String>?> _allowedItemIds(LibraryQuery filter) async {
    if (!filter.isFiltered) return null;
    final ids = filter.ids;
    if (ids != null && !filter.copyWith(ids: null).isFiltered) return ids;

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
  JoinedSelectStatement<HasResultSet, dynamic> _datedRows(LibraryScope scope) {
    final placed = _db.itemPropertyValues;
    final values = _db.propertyValues;
    final definitions = _db.propertyDefinitions;
    final items = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    final notes = _db.knowledgeNotes;
    final processed = _db.processedDocuments;

    return _db.selectOnly(placed)
      ..join([
        innerJoin(values, values.id.equalsExp(placed.propertyValueId)),
        innerJoin(definitions, definitions.id.equalsExp(values.definitionId)),
        innerJoin(items, items.id.equalsExp(placed.itemId)),
        // Una nota no tiene fila de fuente: por eso `LEFT`.
        leftOuterJoin(sources, sources.itemId.equalsExp(items.id)),
        leftOuterJoin(notes, notes.itemId.equalsExp(items.id)),
        // El tipo de un documento procesado es el de su fuente (F41, paso 6).
        leftOuterJoin(processed, processed.itemId.equalsExp(items.id)),
      ])
      ..addColumns([
        items.id,
        items.title,
        sources.sourceType,
        processed.sourceKind,
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
            items.isActive &
            switch (scope) {
              LibraryScope.processed => _isProcessed,
              LibraryScope.library => _isProcessed.not(),
            },
      );
  }

  /// Que el elemento sea un documento procesado (F41, paso 6), en las
  /// consultas de abajo, donde `item` es la tabla de los elementos.
  ///
  /// La línea de tiempo lee lo procesado; la Biblioteca —su calendario, que
  /// reusa esta lectura— lee sus fuentes y sus notas, como su lista.
  static final _isProcessed = CustomExpression<bool>(isProcessedSql('item.id'));

  /// Un hecho que la persona escribió a mano en una nota suya —«Hechos
  /// sueltos», una nota viva—: también es de la línea de tiempo, aunque no
  /// salga de ninguna fuente procesada.
  static final _ownNoteFact = CustomExpression<bool>(
    "item.kind = '${ItemKind.note.name}' "
    "AND dated_events.origin = '${ContentOrigin.user.name}'",
  );

  /// Un renglón por cada hecho fechado dentro de un documento (F40), de un
  /// elemento fuera de la papelera. Las mismas columnas mínimas que
  /// [_datedRows], por lo mismo, más de qué elemento es el texto de la cita: el
  /// de un procesado está en su fuente (F41, paso 6).
  JoinedSelectStatement<HasResultSet, dynamic> _datedEventRows(
    LibraryScope scope,
  ) {
    final facts = _db.datedEvents;
    final items = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    final notes = _db.knowledgeNotes;
    final processed = _db.processedDocuments;
    final quoted = _db.renditions;

    return _db.selectOnly(facts)
      ..join([
        innerJoin(items, items.id.equalsExp(facts.itemId)),
        leftOuterJoin(sources, sources.itemId.equalsExp(items.id)),
        leftOuterJoin(notes, notes.itemId.equalsExp(items.id)),
        // El tipo de un documento procesado es el de su fuente (F41, paso 6).
        leftOuterJoin(processed, processed.itemId.equalsExp(items.id)),
        leftOuterJoin(quoted, quoted.id.equalsExp(facts.renditionId)),
      ])
      ..addColumns([
        facts.id,
        facts.itemId,
        facts.renditionId,
        facts.title,
        facts.dateFromYear,
        facts.dateFromMonth,
        facts.dateFromDay,
        facts.datePrecision,
        facts.dateIsCirca,
        facts.dateEndYear,
        facts.dateEndMonth,
        facts.dateEndDay,
        facts.dateEndPrecision,
        facts.startOffset,
        facts.endOffset,
        facts.excerpt,
        facts.origin,
        items.title,
        sources.sourceType,
        processed.sourceKind,
        notes.noteKind,
        quoted.itemId,
      ])
      ..where(
        items.isActive &
            switch (scope) {
              LibraryScope.processed => _isProcessed | _ownNoteFact,
              LibraryScope.library => _isProcessed.not(),
            },
      );
  }

  TimelineEvent _toDatedEvent(String itemId, TypedResult row) {
    final facts = _db.datedEvents;
    final isCirca = row.read(facts.dateIsCirca) ?? false;
    final endYear = row.read(facts.dateEndYear);
    final endPrecision = row.readWithConverter(facts.dateEndPrecision);
    return TimelineEvent(
      itemId: itemId,
      title: row.read(facts.title)!,
      itemTitle: row.read(_db.knowledgeEntries.title),
      date: HistoricalDate.fromStored(
        astronomicalYear: row.read(facts.dateFromYear)!,
        precision: row.readWithConverter(facts.datePrecision)!,
        month: row.read(facts.dateFromMonth),
        day: row.read(facts.dateFromDay),
        isCirca: isCirca,
      ),
      // Las cuatro del fin vienen juntas, o ninguna (lo hace cumplir la base).
      end: endYear == null
          ? null
          : HistoricalDate.fromStored(
              astronomicalYear: endYear,
              precision: endPrecision!,
              month: row.read(facts.dateEndMonth),
              day: row.read(facts.dateEndDay),
              isCirca: isCirca,
            ),
      sourceKind:
          row.readWithConverter(_db.knowledgeSources.sourceType) ??
          row.readWithConverter(_db.processedDocuments.sourceKind) ??
          SourceKind.manualNote,
      noteKind: row.readWithConverter(_db.knowledgeNotes.noteKind),
      datedEventId: row.read(facts.id),
      renditionId: row.read(facts.renditionId),
      quoteItemId: row.read(_db.renditions.itemId),
      startOffset: row.read(facts.startOffset),
      endOffset: row.read(facts.endOffset),
      excerpt: row.read(facts.excerpt),
      origin: row.readWithConverter(facts.origin),
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
          row.readWithConverter(_db.processedDocuments.sourceKind) ??
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
