import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/repositories/dated_event_repository.dart';

/// [DatedEventRepository] sobre la base (`dated_events`, v44).
class DatedEventRepositoryImpl implements DatedEventRepository {
  DatedEventRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Stream<List<DatedEvent>> watchForItem(String itemId) => watchQuery(
    db: _db,
    tables: [_db.datedEvents],
    read: () => _readForItem(itemId),
    telemetry: _telemetry,
    hint: 'DatedEventRepositoryImpl.watchForItem',
  );

  Future<List<DatedEvent>> _readForItem(String itemId) async {
    final rows =
        await (_db.select(_db.datedEvents)
              ..where((e) => e.itemId.equals(itemId))
              ..orderBy([
                (e) => OrderingTerm.asc(e.dateFromYear),
                (e) => OrderingTerm.asc(e.dateFromMonth),
                (e) => OrderingTerm.asc(e.dateFromDay),
                (e) => OrderingTerm.asc(e.createdAt),
                (e) => OrderingTerm.asc(e.id),
              ]))
            .get();
    return [for (final row in rows) datedEventFromRow(row)];
  }

  @override
  Future<Either<Failure, DatedEvent>> add(
    String itemId,
    DatedEventInput input,
  ) async {
    final problem = input.problem;
    if (problem != null) return left(Failure.validation(message: problem));
    try {
      return await _db.transaction(() async {
        if (!await _renditionBelongsTo(input.renditionId, itemId)) {
          return left(_foreignRendition);
        }
        final now = _clock();
        final companion = _companionOf(
          input,
          id: _ids.next(),
          itemId: itemId,
          origin: ContentOrigin.user,
          now: now,
        );
        final row = await _db.into(_db.datedEvents).insertReturning(companion);
        return right(datedEventFromRow(row));
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'DatedEventRepositoryImpl.add'));
    }
  }

  @override
  Future<Either<Failure, int>> addFromAi({
    required String itemId,
    required String runId,
    required List<DatedEventInput> drafts,
  }) async {
    try {
      return await _db.transaction(() async {
        final run = await (_db.select(
          _db.aiRuns,
        )..where((r) => r.id.equals(runId))).getSingleOrNull();
        if (run == null || run.itemId != itemId) return left(_foreignRun);

        // Lo que ya hay en el elemento, de quien sea: lo mismo no se pone dos
        // veces.
        final seen = <String>{
          for (final row in await (_db.select(
            _db.datedEvents,
          )..where((e) => e.itemId.equals(itemId))).get())
            if (row.excerpt != null)
              _keyOf(datedEventFromRow(row).date, row.excerpt!),
        };

        var added = 0;
        for (final draft in drafts) {
          // La IA siempre cita: un hecho suyo sin fragmento no se puede
          // revisar, ni reconocer como repetido, ni como «no era».
          final excerpt = draft.excerpt;
          if (draft.problem != null ||
              excerpt == null ||
              excerpt.trim().isEmpty) {
            continue;
          }
          if (!await _renditionBelongsTo(draft.renditionId, itemId)) continue;

          if (!seen.add(_keyOf(draft.date, excerpt))) continue;
          if (await isAiRejected(
            _db,
            kind: AiRejectionKind.datedEvent,
            itemId: itemId,
            fingerprint: datedEventRejectionFingerprint(
              date: draft.date,
              excerpt: excerpt,
            ),
          )) {
            continue;
          }

          await _db
              .into(_db.datedEvents)
              .insert(
                _companionOf(
                  draft,
                  id: _ids.next(),
                  itemId: itemId,
                  origin: ContentOrigin.ai,
                  aiRunId: runId,
                  now: _clock(),
                ),
              );
          added++;
        }
        return right(added);
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'DatedEventRepositoryImpl.addFromAi'),
      );
    }
  }

  @override
  Future<Either<Failure, DatedEvent>> update(
    String id, {
    required String title,
    required HistoricalDate date,
    HistoricalDate? end,
  }) async {
    final problem = DatedEventInput(title: title, date: date, end: end).problem;
    if (problem != null) return left(Failure.validation(message: problem));
    try {
      final start = date.rangeStart;
      final updated =
          await (_db.update(
            _db.datedEvents,
          )..where((e) => e.id.equals(id))).writeReturning(
            DatedEventsCompanion(
              title: Value(title.trim()),
              dateFromYear: Value(start.year),
              dateFromMonth: Value(start.month),
              dateFromDay: Value(start.day),
              datePrecision: Value(date.precision),
              dateIsCirca: Value(date.isCirca),
              dateEndYear: Value(end?.rangeStart.year),
              dateEndMonth: Value(end?.rangeStart.month),
              dateEndDay: Value(end?.rangeStart.day),
              dateEndPrecision: Value(end?.precision),
              // Editar es adoptar (F27): deja de ser de la IA.
              origin: const Value(ContentOrigin.user),
              aiRunId: const Value(null),
              updatedAt: Value(_clock()),
            ),
          );
      final row = updated.singleOrNull;
      if (row == null) return left(_gone);
      return right(datedEventFromRow(row));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'DatedEventRepositoryImpl.update'),
      );
    }
  }

  @override
  Future<Either<Failure, DatedEventRemoval>> remove(String id) async {
    try {
      return await _db.transaction(() async {
        final row = await (_db.select(
          _db.datedEvents,
        )..where((e) => e.id.equals(id))).getSingleOrNull();
        if (row == null) return left(_gone);
        final event = datedEventFromRow(row);

        // Quitar uno de la IA es decirle que «no era»: se recuerda para que no
        // vuelva en la pasada siguiente. Uno de la persona simplemente se va.
        final rejectionId = event.isAi
            ? await rememberAiRejection(
                _db,
                ids: _ids,
                now: _clock(),
                kind: AiRejectionKind.datedEvent,
                itemId: event.itemId,
                fingerprint: datedEventRejectionFingerprint(
                  date: event.date,
                  excerpt: event.excerpt ?? event.title,
                ),
                subjectId: event.id,
              )
            : null;
        await (_db.delete(_db.datedEvents)..where((e) => e.id.equals(id))).go();
        return right(DatedEventRemoval(event: event, rejectionId: rejectionId));
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'DatedEventRepositoryImpl.remove'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> undoRemove(DatedEventRemoval removal) async {
    try {
      await _db.transaction(() async {
        final event = removal.event;
        // Pasó un rato: la pasada o el texto pueden haberse ido. El hecho
        // vuelve igual, sin lo que ya no existe.
        final runExists =
            event.aiRunId != null &&
            await (_db.select(_db.aiRuns)
                      ..where((r) => r.id.equals(event.aiRunId!)))
                    .getSingleOrNull() !=
                null;
        final textExists =
            event.renditionId != null &&
            await _renditionBelongsTo(event.renditionId, event.itemId);
        await _db
            .into(_db.datedEvents)
            .insert(
              _rowCompanion(event).copyWith(
                aiRunId: Value(runExists ? event.aiRunId : null),
                renditionId: Value(textExists ? event.renditionId : null),
                startOffset: Value(textExists ? event.startOffset : null),
                endOffset: Value(textExists ? event.endOffset : null),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (removal.rejectionId case final rejectionId?) {
          await forgetAiRejection(_db, rejectionId);
        }
      });
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'DatedEventRepositoryImpl.undoRemove'),
      );
    }
  }

  /// Que [renditionId] —si hay— sea una forma de texto de [itemId]: la cita
  /// de un hecho es de un texto de SU elemento.
  ///
  /// O de su fuente, si [itemId] es un documento procesado (F41, paso 6): un
  /// procesado no tiene formas propias, y lo que se cita de una parte copiada
  /// tal cual está, letra por letra, en el original. Ahí se abre la cita.
  Future<bool> _renditionBelongsTo(String? renditionId, String itemId) async {
    if (renditionId == null) return true;
    final rendition =
        await (_db.selectOnly(_db.renditions)
              ..addColumns([_db.renditions.itemId])
              ..where(_db.renditions.id.equals(renditionId)))
            .getSingleOrNull();
    final owner = rendition?.read(_db.renditions.itemId);
    if (owner == null) return false;
    if (owner == itemId) return true;
    final processed = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(itemId))).getSingleOrNull();
    return processed?.sourceItemId == owner;
  }

  DatedEventsCompanion _companionOf(
    DatedEventInput input, {
    required String id,
    required String itemId,
    required ContentOrigin origin,
    required DateTime now,
    String? aiRunId,
  }) {
    final start = input.date.rangeStart;
    final end = input.end?.rangeStart;
    return DatedEventsCompanion.insert(
      id: id,
      itemId: itemId,
      renditionId: Value(input.renditionId),
      title: input.title.trim(),
      dateFromYear: start.year,
      dateFromMonth: start.month,
      dateFromDay: start.day,
      datePrecision: input.date.precision,
      dateIsCirca: Value(input.date.isCirca),
      dateEndYear: Value(end?.year),
      dateEndMonth: Value(end?.month),
      dateEndDay: Value(end?.day),
      dateEndPrecision: Value(input.end?.precision),
      startOffset: Value(input.startOffset),
      endOffset: Value(input.endOffset),
      excerpt: Value(input.excerpt),
      origin: Value(origin),
      aiRunId: Value(aiRunId),
      createdAt: now,
      updatedAt: now,
    );
  }

  /// La fila de [event] tal cual, para devolverla a la base.
  DatedEventsCompanion _rowCompanion(DatedEvent event) {
    final start = event.date.rangeStart;
    final end = event.end?.rangeStart;
    return DatedEventsCompanion.insert(
      id: event.id,
      itemId: event.itemId,
      renditionId: Value(event.renditionId),
      title: event.title,
      dateFromYear: start.year,
      dateFromMonth: start.month,
      dateFromDay: start.day,
      datePrecision: event.date.precision,
      dateIsCirca: Value(event.date.isCirca),
      dateEndYear: Value(end?.year),
      dateEndMonth: Value(end?.month),
      dateEndDay: Value(end?.day),
      dateEndPrecision: Value(event.end?.precision),
      startOffset: Value(event.startOffset),
      endOffset: Value(event.endOffset),
      excerpt: Value(event.excerpt),
      origin: Value(event.origin),
      aiRunId: Value(event.aiRunId),
      createdAt: event.createdAt,
      updatedAt: event.updatedAt,
    );
  }

  static const _gone = Failure.unexpected(
    message: 'El hecho ya no existe; puede que se haya borrado.',
  );

  static const _foreignRun = Failure.validation(
    message: 'Esa pasada no es de este elemento.',
  );

  static const _foreignRendition = Failure.validation(
    message: 'Ese texto no es de este elemento.',
  );

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y atrapar solo `Exception` lo
  /// dejaría escapar dejando a quien llamó esperando una respuesta que
  /// nunca llega.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}

/// El hecho que guarda [row].
DatedEvent datedEventFromRow(DatedEventRow row) {
  final endYear = row.dateEndYear;
  return DatedEvent(
    id: row.id,
    itemId: row.itemId,
    renditionId: row.renditionId,
    title: row.title,
    date: HistoricalDate.fromStored(
      astronomicalYear: row.dateFromYear,
      precision: row.datePrecision,
      month: row.dateFromMonth,
      day: row.dateFromDay,
      isCirca: row.dateIsCirca,
    ),
    end: endYear == null
        ? null
        : HistoricalDate.fromStored(
            astronomicalYear: endYear,
            // Las cuatro del fin vienen juntas (lo hace cumplir la base).
            precision: row.dateEndPrecision!,
            month: row.dateEndMonth,
            day: row.dateEndDay,
            isCirca: row.dateIsCirca,
          ),
    startOffset: row.startOffset,
    endOffset: row.endOffset,
    excerpt: row.excerpt,
    origin: row.origin,
    aiRunId: row.aiRunId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

/// Qué hace que dos hechos sean el mismo: la fecha y la cita, normalizadas.
/// Es la misma huella con que se recuerda un «no era».
String _keyOf(HistoricalDate date, String excerpt) =>
    datedEventRejectionFingerprint(date: date, excerpt: excerpt);
