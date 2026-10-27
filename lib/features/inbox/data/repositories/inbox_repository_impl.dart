import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/database/text_presence.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_source.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/inbox/domain/entities/source_extent.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';

class InboxRepositoryImpl implements InboxRepository {
  const InboxRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;

  /// Quien escribe el estado, el subtipo y la madurez: ver
  /// [KnowledgeEntryWriter].
  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  /// Lo que espera en la Bandeja: una fuente fuera de la papelera sobre la que
  /// nadie decidió todavía (`InboxStatus.pending`). Desde F41, apenas se
  /// guarda, tenga su texto o no —lo que todavía no lo tiene espera con su
  /// tarjeta, ver [PendingText]—. Un solo criterio para el mazo, la lista de
  /// la cola, la insignia, el panel de salud y el contador; la sección
  /// «Bandeja» de los filtros dice lo mismo con `InboxStatus.itemStates`.
  Expression<bool> _isPending($KnowledgeEntriesTable e) =>
      e.kind.equalsValue(ItemKind.source) &
      e.state.isIn([
        for (final state in InboxStatus.pending.itemStates) state.name,
      ]) &
      e.isActive;

  /// El orden de la Bandeja: el de llegada, ver [watchPendingIds]. El `id`
  /// desempata dos que se guardaron en el mismo instante —una importación—,
  /// para que el mazo y la lista no las den vuelta entre una lectura y otra.
  List<OrderingTerm> _arrivalOrder($KnowledgeEntriesTable e) => [
    OrderingTerm(expression: e.createdAt),
    OrderingTerm(expression: e.id),
  ];

  /// En qué está el texto de la fila: si tiene alguno ([hasTextSql]) y en qué
  /// está su procesamiento. Ver [PendingText.of].
  static PendingText _pendingTextOf({
    required bool hasText,
    required SourceProcessingStatus? status,
  }) =>
      PendingText.of(hasText: hasText, processing: processingStateFor(status));

  @override
  Stream<List<String>> watchPendingIds() {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries],
      read: () async {
        final rows =
            await (_db.select(_db.knowledgeEntries)
                  ..where(_isPending)
                  ..orderBy([
                    for (final term in _arrivalOrder(_db.knowledgeEntries))
                      (_) => term,
                  ]))
                .get();
        return rows.map((row) => row.id).toList();
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchPendingIds',
    );
  }

  @override
  Stream<List<PendingSource>> watchPending() {
    final entries = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    final hasText = CustomExpression<bool>(hasTextSql('item'));
    return watchQuery(
      db: _db,
      tables: [entries, sources, _db.renditions],
      read: () async {
        // Un `innerJoin`: una fuente siempre tiene su fila de `source` —la
        // escriben juntas `save()` y el espejo—, y sin ella no habría tipo
        // ni fecha que mostrar.
        final rows =
            await (_db.select(entries).join([
                    innerJoin(sources, sources.itemId.equalsExp(entries.id)),
                  ])
                  ..addColumns([hasText])
                  ..where(_isPending(entries))
                  ..orderBy(_arrivalOrder(entries)))
                .get();
        return [
          for (final row in rows)
            PendingSource(
              id: row.readTable(entries).id,
              title: row.readTable(entries).title,
              kind: row.readTable(sources).sourceType,
              capturedAt: row.readTable(sources).capturedAt,
              text: _pendingTextOf(
                hasText: row.read(hasText) ?? false,
                status: row.readTable(sources).processingStatus,
              ),
            ),
        ];
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchPending',
    );
  }

  @override
  Stream<PendingText?> watchPendingText(String itemId) {
    final entries = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    final hasText = CustomExpression<bool>(hasTextSql('item'));
    return watchQuery(
      db: _db,
      tables: [sources, _db.renditions],
      read: () async {
        // El mismo criterio que [watchPending], sobre una sola fuente: la
        // tarjeta y la lista no pueden decir cosas distintas.
        final row =
            await (_db.select(entries).join([
                    innerJoin(sources, sources.itemId.equalsExp(entries.id)),
                  ])
                  ..addColumns([hasText])
                  ..where(entries.id.equals(itemId)))
                .getSingleOrNull();
        if (row == null) return null;
        return _pendingTextOf(
          hasText: row.read(hasText) ?? false,
          status: row.readTable(sources).processingStatus,
        );
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchPendingText',
    );
  }

  @override
  Stream<InboxStanding?> watchStanding(String itemId) {
    final entries = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    return watchQuery(
      db: _db,
      tables: [entries, sources, _db.fieldVersions],
      read: () async {
        final row =
            await (_db.select(entries).join([
                  leftOuterJoin(sources, sources.itemId.equalsExp(entries.id)),
                ])..where(entries.id.equals(itemId) & entries.isActive))
                .getSingleOrNull();
        if (row == null) return null;
        final entry = row.readTable(entries);
        final status = InboxStatus.of(entry.kind, entry.state);
        if (status == null) return null;

        // Desde cuándo: la última vez que se cambió el estado, que ya
        // registra la versión por campo (F11) —ver [InboxStanding.since]—.
        final version =
            await (_db.select(_db.fieldVersions)..where(
                  (f) =>
                      f.itemId.equals(itemId) &
                      f.fieldName.equals(EntryField.state),
                ))
                .getSingleOrNull();
        return InboxStanding(
          status: status,
          since: version?.updatedAt,
          // Una referencia bibliográfica no trae texto que procesar: no entra
          // a la Bandeja, tampoco de vuelta (F41, decisión E).
          canReturn:
              row.readTableOrNull(sources)?.sourceType != SourceKind.reference,
        );
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchStanding',
    );
  }

  @override
  Stream<SourceExtent> watchExtent(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.chunks],
      read: () async {
        // De los fragmentos del texto del elemento, que ya llevan la página
        // de cada uno y el momento en que termina: ver [SourceExtent].
        final row = await _db
            .customSelect(
              'SELECT MAX(page_number) AS pages, MAX(end_ms) AS end_ms '
              'FROM chunks WHERE item_id = ?',
              variables: [Variable.withString(itemId)],
              readsFrom: {_db.chunks},
            )
            .getSingle();
        final pages = row.readNullable<int>('pages');
        final endMs = row.readNullable<int>('end_ms');
        return SourceExtent(
          pages: pages == null || pages <= 0 ? null : pages,
          duration: endMs == null || endMs <= 0
              ? null
              : Duration(milliseconds: endMs),
        );
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchExtent',
    );
  }

  @override
  Future<Either<Failure, Unit>> transitionState({
    required String itemId,
    required ItemState to,
  }) async {
    try {
      if (!await _writer.setState(itemId, to)) {
        return left(
          const Failure.unexpected(
            message: 'El elemento ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.transitionState'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> returnToInbox(String itemId) async {
    try {
      final source = await (_db.select(
        _db.knowledgeSources,
      )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
      // El estado de espera con que nacería hoy: ver [returnToInbox].
      final waiting = source == null
          ? null
          : initialItemStateFor(processingStateFor(source.processingStatus));
      if (waiting == null || !await _writer.setState(itemId, waiting)) {
        return left(
          const Failure.unexpected(
            message:
                'La fuente ya no existe; puede que se haya borrado para '
                'siempre.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.returnToInbox'),
      );
    }
  }

  @override
  Stream<List<NoteReference>> watchLivingNotes({String? searchText}) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries, _db.knowledgeNotes],
      read: () async {
        final trimmed = searchText?.trim();

        final query =
            _db.select(_db.knowledgeEntries).join([
              innerJoin(
                _db.knowledgeNotes,
                _db.knowledgeNotes.itemId.equalsExp(_db.knowledgeEntries.id),
              ),
            ])..where(
              _db.knowledgeEntries.kind.equalsValue(ItemKind.note) &
                  _db.knowledgeNotes.noteKind.equalsValue(NoteKind.living) &
                  _db.knowledgeEntries.isActive,
            );

        if (trimmed != null && trimmed.isNotEmpty) {
          query.where(
            _db.knowledgeEntries.title.lower().contains(trimmed.toLowerCase()),
          );
        }

        query.orderBy([OrderingTerm(expression: _db.knowledgeEntries.title)]);

        final rows = await query.get();
        return rows.map((row) {
          final entry = row.readTable(_db.knowledgeEntries);
          return NoteReference(
            id: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
          );
        }).toList();
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchLivingNotes',
    );
  }

  @override
  Stream<NoteMaturity?> watchNoteMaturity(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeNotes],
      read: () async {
        final row = await (_db.select(
          _db.knowledgeNotes,
        )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
        return row?.maturity;
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchNoteMaturity',
    );
  }

  @override
  Stream<NoteKind?> watchNoteKind(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeNotes],
      read: () async {
        final row = await (_db.select(
          _db.knowledgeNotes,
        )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
        return row?.noteKind;
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchNoteKind',
    );
  }

  @override
  Future<Either<Failure, Unit>> setNoteMaturity({
    required String itemId,
    required NoteMaturity maturity,
  }) async {
    try {
      if (!await _writer.setMaturity(itemId, maturity)) {
        return left(
          const Failure.unexpected(
            message: 'La nota ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.setNoteMaturity'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> setNoteKind({
    required String itemId,
    required NoteKind kind,
  }) async {
    try {
      if (!await _writer.setNoteKind(itemId, kind)) {
        return left(
          const Failure.unexpected(
            message: 'La nota ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.setNoteKind'),
      );
    }
  }

  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
