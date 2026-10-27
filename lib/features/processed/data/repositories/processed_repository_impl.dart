import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_query_sql.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_section_planner.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

/// [ProcessedRepository] sobre la base (`processed_documents` y
/// `processed_parts`, v45).
///
/// El elemento del procesado —su fila de `item` y su `note`— lo escribe
/// [KnowledgeEntryWriter], como todo elemento; sus partes, este repositorio. La
/// fuente solo se lee.
class ProcessedRepositoryImpl implements ProcessedRepository {
  ProcessedRepositoryImpl({
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

  KnowledgeEntryWriter get _writer =>
      KnowledgeEntryWriter(_db, clock: _clock, ids: _ids);

  /// Cuántos ids entran en una sola consulta: por debajo del tope de
  /// parámetros de SQLite.
  static const _idsPerQuery = 400;

  List<TableInfo<dynamic, dynamic>> get _listTables => [
    _db.processedDocuments,
    _db.processedParts,
    _db.knowledgeEntries,
    _db.itemSpaces,
  ];

  // --- La lista ---------------------------------------------------------

  @override
  Stream<List<ProcessedDocumentSummary>> watchDocuments(ProcessedQuery query) =>
      watchQuery(
        db: _db,
        tables: _listTables,
        read: () => _list(query),
        telemetry: _telemetry,
        hint: 'ProcessedRepositoryImpl.watchDocuments',
      );

  @override
  Stream<int> watchCount(ProcessedQuery query) => watchQuery(
    db: _db,
    tables: _listTables,
    read: () async {
      final (:sql, :variables) = ProcessedQuerySql(query).count();
      final row = await _db.customSelect(sql, variables: variables).getSingle();
      return row.read<int>('n');
    },
    telemetry: _telemetry,
    hint: 'ProcessedRepositoryImpl.watchCount',
  );

  @override
  Future<Either<Failure, List<String>>> matchingIds(ProcessedQuery query) =>
      _guard('matchingIds', () async => right(await _matching(query)));

  Future<List<String>> _matching(ProcessedQuery query) async {
    final (:sql, :variables) = ProcessedQuerySql(query).ids();
    final rows = await _db.customSelect(sql, variables: variables).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  Future<List<ProcessedDocumentSummary>> _list(ProcessedQuery query) async =>
      _summariesOf(await _matching(query));

  /// Las filas de [ids], en ese orden: el elemento, su procesado, cuántas
  /// partes tiene cada sección y sus temas. Nada que mida el texto.
  Future<List<ProcessedDocumentSummary>> _summariesOf(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final heads = <String, QueryRow>{};
    final counts = <String, Map<ProcessedSection, int>>{};
    final spaces = <String, Set<String>>{};
    for (var start = 0; start < ids.length; start += _idsPerQuery) {
      final slice = ids.skip(start).take(_idsPerQuery).toList();
      final marks = List.filled(slice.length, '?').join(', ');
      final variables = [for (final id in slice) Variable.withString(id)];
      for (final row
          in await _db
              .customSelect(
                'SELECT item.id AS id, item.title AS title, '
                'item.created_at AS created_at, item.updated_at AS updated_at, '
                'pd.source_item_id AS source_item_id, '
                'pd.source_kind AS source_kind '
                'FROM processed_documents pd JOIN item ON item.id = pd.item_id '
                'WHERE item.id IN ($marks)',
                variables: variables,
              )
              .get()) {
        heads[row.read<String>('id')] = row;
      }
      for (final row
          in await _db
              .customSelect(
                'SELECT document_id, section, COUNT(*) AS n '
                'FROM processed_parts WHERE document_id IN ($marks) '
                'GROUP BY document_id, section',
                variables: variables,
              )
              .get()) {
        (counts[row.read<String>('document_id')] ??= {})[ProcessedSection.values
            .byName(row.read<String>('section'))] = row.read<int>(
          'n',
        );
      }
      for (final row in await (_db.select(
        _db.itemSpaces,
      )..where((s) => s.itemId.isIn(slice))).get()) {
        (spaces[row.itemId] ??= {}).add(row.spaceId);
      }
    }
    return [
      for (final id in ids)
        if (heads[id] case final head?)
          ProcessedDocumentSummary(
            id: id,
            title: head.read<String>('title'),
            sourceKind: SourceKind.values.byName(
              head.read<String>('source_kind'),
            ),
            createdAt: head.read<DateTime>('created_at'),
            updatedAt: head.read<DateTime>('updated_at'),
            partCounts: counts[id] ?? const {},
            sourceItemId: head.readNullable<String>('source_item_id'),
            spaceIds: spaces[id] ?? const {},
          ),
    ];
  }

  @override
  Stream<Set<String>> watchProcessedSourceIds() => watchQuery(
    db: _db,
    tables: [_db.processedDocuments, _db.knowledgeEntries],
    read: () async {
      final rows = await _db
          .customSelect(
            'SELECT pd.source_item_id AS id FROM processed_documents pd '
            'JOIN item ON item.id = pd.item_id '
            'WHERE $kActiveItemSql AND pd.source_item_id IS NOT NULL',
          )
          .get();
      return {for (final row in rows) row.read<String>('id')};
    },
    telemetry: _telemetry,
    hint: 'ProcessedRepositoryImpl.watchProcessedSourceIds',
  );

  // --- Un documento --------------------------------------------------------

  @override
  Stream<ProcessedDocument?> watchDocument(String documentId) => watchQuery(
    db: _db,
    tables: _listTables,
    read: () => _document(documentId),
    telemetry: _telemetry,
    hint: 'ProcessedRepositoryImpl.watchDocument',
  );

  @override
  Stream<ProcessedDocument?> watchForSource(String sourceItemId) => watchQuery(
    db: _db,
    tables: _listTables,
    read: () async {
      final row = await (_db.select(
        _db.processedDocuments,
      )..where((d) => d.sourceItemId.equals(sourceItemId))).getSingleOrNull();
      return row == null ? null : _document(row.itemId);
    },
    telemetry: _telemetry,
    hint: 'ProcessedRepositoryImpl.watchForSource',
  );

  Future<ProcessedDocument?> _document(String documentId) async {
    final summaries = await _summariesOf([documentId]);
    if (summaries.isEmpty) return null;
    final summary = summaries.single;
    final entry = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(documentId))).getSingle();
    final stats = {
      for (final row
          in await _db
              .customSelect(
                'SELECT section, COUNT(*) AS n, SUM(length(content)) AS chars, '
                'SUM(edited) AS edited FROM processed_parts '
                'WHERE document_id = ? GROUP BY section',
                variables: [Variable.withString(documentId)],
              )
              .get())
        ProcessedSection.values.byName(
          row.read<String>('section'),
        ): ProcessedSectionStats(
          parts: row.read<int>('n'),
          characters: row.read<int>('chars'),
          edited: row.read<int>('edited'),
        ),
    };
    ProcessedSourceLink? source;
    if (summary.sourceItemId case final sourceId?) {
      final row = await (_db.select(
        _db.knowledgeEntries,
      )..where((e) => e.id.equals(sourceId))).getSingleOrNull();
      if (row != null) {
        source = ProcessedSourceLink(
          itemId: row.id,
          title: row.title,
          inTrash: row.deletedAt != null,
        );
      }
    }
    return ProcessedDocument(
      summary: summary,
      stats: stats,
      inTrash: entry.deletedAt != null,
      source: source,
    );
  }

  @override
  Future<Either<Failure, ProcessedDocumentStatus>> statusOf(
    String documentId,
  ) => _guard('statusOf', () async => right(await _status(documentId)));

  Future<ProcessedDocumentStatus> _status(String documentId) async {
    final row =
        await (_db.select(_db.processedDocuments).join([
              innerJoin(
                _db.knowledgeEntries,
                _db.knowledgeEntries.id.equalsExp(
                  _db.processedDocuments.itemId,
                ),
              ),
            ])..where(_db.processedDocuments.itemId.equals(documentId)))
            .getSingleOrNull();
    if (row == null) return ProcessedDocumentStatus.absent;
    return row.readTable(_db.knowledgeEntries).deletedAt == null
        ? ProcessedDocumentStatus.active
        : ProcessedDocumentStatus.trashed;
  }

  @override
  Stream<List<ProcessedPart>> watchParts(
    String documentId,
    ProcessedSection section, {
    int offset = 0,
    int? limit,
  }) => watchQuery(
    db: _db,
    tables: [_db.processedParts],
    read: () async {
      final query = _db.select(_db.processedParts)
        ..where(
          (p) =>
              p.documentId.equals(documentId) & p.section.equalsValue(section),
        )
        ..orderBy([
          (p) => OrderingTerm.asc(p.position),
          (p) => OrderingTerm.asc(p.id),
        ]);
      if (limit != null) query.limit(limit, offset: offset);
      return [for (final row in await query.get()) processedPartFromRow(row)];
    },
    telemetry: _telemetry,
    hint: 'ProcessedRepositoryImpl.watchParts',
  );

  @override
  Future<Either<Failure, List<ProcessedPart>>> partsOf(
    String documentId, {
    Set<ProcessedSection>? sections,
  }) =>
      _guard('partsOf', () async => right(await _parts(documentId, sections)));

  Future<List<ProcessedPart>> _parts(
    String documentId,
    Set<ProcessedSection>? sections,
  ) async {
    final rows =
        await (_db.select(_db.processedParts)
              ..where((p) {
                final ofDocument = p.documentId.equals(documentId);
                return sections == null
                    ? ofDocument
                    : ofDocument &
                          p.section.isIn([for (final s in sections) s.name]);
              })
              ..orderBy([
                (p) => OrderingTerm.asc(p.section),
                (p) => OrderingTerm.asc(p.position),
                (p) => OrderingTerm.asc(p.id),
              ]))
            .get();
    final parts = [for (final row in rows) processedPartFromRow(row)];
    // Por sección en el orden en que se leen, no en el alfabético de su
    // nombre; dentro de cada una, en su lugar.
    return parts..sort((a, b) {
      final bySection = a.section.index.compareTo(b.section.index);
      if (bySection != 0) return bySection;
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
    });
  }

  // --- La fuente, solo para leer -------------------------------------------

  @override
  Future<Either<Failure, ProcessedSourceMaterial>> materialOf(
    String sourceItemId, {
    bool countWords = true,
  }) => _guard('materialOf', () async {
    final entry = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(sourceItemId) & e.isActive)).getSingleOrNull();
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceItemId))).getSingleOrNull();
    if (entry == null || entry.kind != ItemKind.source || source == null) {
      return left(
        const Failure.validation(
          message:
              'Solo se procesa una fuente de la Biblioteca que no esté '
              'en la papelera.',
        ),
      );
    }
    final text = await sourceTextRenditionInfo(_db, sourceItemId);
    var words = 0;
    if (countWords && text != null) {
      final content = await _textOf(text.id);
      words = await runProcessedWork(
        processedWordCount,
        content,
        size: content.length,
      );
    }
    final sentences = text == null
        ? const <StudyMarkRow>[]
        : await (_db.select(_db.studyMarks)
                ..where(
                  (m) =>
                      m.renditionId.equals(text.id) &
                      m.kind.isIn([
                        StudyMarkKind.summary.name,
                        StudyMarkKind.synthesis.name,
                      ]),
                )
                ..orderBy([
                  (m) => OrderingTerm.asc(m.startOffset),
                  (m) => OrderingTerm.asc(m.endOffset),
                  (m) => OrderingTerm.asc(m.id),
                ]))
              .get();
    List<ProcessedSentence> of(StudyMarkKind kind) => [
      for (final mark in sentences)
        if (mark.kind == kind)
          ProcessedSentence(
            studyMarkId: mark.id,
            anchor: ProcessedAnchor(
              renditionId: mark.renditionId,
              start: mark.startOffset,
              end: mark.endOffset,
            ),
            content: mark.excerpt,
          ),
    ];
    return right(
      ProcessedSourceMaterial(
        sourceItemId: sourceItemId,
        title: entry.title,
        sourceKind: source.sourceType,
        textRenditionId: text?.id,
        textCharacters: text?.length ?? 0,
        textWords: words,
        summary: of(StudyMarkKind.summary),
        synthesis: of(StudyMarkKind.synthesis),
      ),
    );
  });

  Future<String> _textOf(String renditionId) async {
    final r = _db.renditions;
    final row =
        await (_db.selectOnly(r)
              ..addColumns([r.content])
              ..where(r.id.equals(renditionId)))
            .getSingle();
    return row.read(r.content)!;
  }

  @override
  Future<Either<Failure, ProcessedSourceText?>> sourceText(
    String sourceItemId, {
    String? renditionId,
  }) => _guard('sourceText', () async {
    final id =
        renditionId ?? (await sourceTextRenditionInfo(_db, sourceItemId))?.id;
    if (id == null) return right(null);
    final r = _db.renditions;
    final row =
        await (_db.selectOnly(r)
              ..addColumns([r.content])
              ..where(
                r.id.equals(id) &
                    r.itemId.equals(sourceItemId) &
                    r.content.isNotNull() &
                    r.textOf.isNull(),
              ))
            .getSingleOrNull();
    final content = row?.read(r.content);
    return right(
      content == null
          ? null
          : ProcessedSourceText(renditionId: id, text: content),
    );
  });

  // --- Escribir ------------------------------------------------------------

  @override
  Future<Either<Failure, ProcessUndo>> commit(ProcessedCommit commit) => _guard(
    'commit',
    () async {
      final documentId = processedDocumentIdFor(commit.sourceItemId);
      try {
        return right(await _db.transaction(() => _commit(documentId, commit)));
      } on _Stale catch (stale) {
        return left(Failure.validation(message: stale.message));
      }
    },
  );

  Future<ProcessUndo> _commit(String documentId, ProcessedCommit commit) async {
    final status = await _status(documentId);
    if (status != commit.expectedStatus) {
      throw const _Stale('El documento procesado cambió mientras tanto.');
    }
    final sections = {for (final plan in commit.plans) plan.section};
    final previous = status == ProcessedDocumentStatus.absent
        ? const <ProcessedPart>[]
        : await _parts(documentId, sections);
    for (final plan in commit.plans) {
      final now = {
        for (final part in previous)
          if (part.section == plan.section) part.id,
      };
      final planned = {
        for (final part in plan.parts)
          if (part is KeptPart) part.part.id,
        for (final part in plan.removed) part.id,
      };
      if (now.length != planned.length || !now.containsAll(planned)) {
        throw const _Stale(
          'Las partes del documento procesado cambiaron mientras tanto.',
        );
      }
    }

    final at = _clock();
    switch (status) {
      case ProcessedDocumentStatus.absent:
        await _create(documentId, commit.sourceItemId, at);
      case ProcessedDocumentStatus.trashed:
        await _writer.restore([documentId]);
      case ProcessedDocumentStatus.active:
        break;
    }

    var changed = status != ProcessedDocumentStatus.active;
    for (final plan in commit.plans) {
      if (plan.isNoOp) continue;
      changed = true;
      await _applyPlan(documentId, plan, at);
    }
    if (changed) await _writer.markContentChanged(documentId);

    return ProcessUndo(
      documentId: documentId,
      previousStatus: status,
      previous: {
        for (final section in sections)
          section: [
            for (final part in previous)
              if (part.section == section) part,
          ],
      },
    );
  }

  /// El elemento del procesado de [sourceItemId], con el título y el tipo de
  /// su fuente. Nace sin temas: la IA lo organiza con lo que se eligió
  /// (decisión F), no con lo de la fuente.
  Future<void> _create(
    String documentId,
    String sourceItemId,
    DateTime at,
  ) async {
    final entry = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(sourceItemId) & e.isActive)).getSingleOrNull();
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceItemId))).getSingleOrNull();
    if (entry == null || entry.kind != ItemKind.source || source == null) {
      throw const _Stale('La fuente ya no está en la Biblioteca.');
    }
    await _writer.upsert(
      KnowledgeItem(
        id: documentId,
        title: entry.title,
        source: Source(
          id: documentId,
          kind: SourceKind.manualNote,
          capturedAt: at,
        ),
        processingState: ProcessingState.ready,
        createdAt: at,
        updatedAt: at,
      ),
      noteKind: NoteKind.processed,
    );
    await _db
        .into(_db.processedDocuments)
        .insert(
          ProcessedDocumentsCompanion.insert(
            itemId: documentId,
            sourceItemId: Value(sourceItemId),
            sourceKind: source.sourceType,
            createdAt: at,
          ),
        );
  }

  /// Deja la sección de [plan] como dice: se van las que salen, las que se
  /// quedan pasan a su lugar y entran las nuevas, todas en una tanda.
  Future<void> _applyPlan(
    String documentId,
    SectionPlan plan,
    DateTime at,
  ) async {
    final removed = [for (final part in plan.removed) part.id];
    for (var start = 0; start < removed.length; start += _idsPerQuery) {
      final slice = removed.skip(start).take(_idsPerQuery).toList();
      await (_db.delete(
        _db.processedParts,
      )..where((p) => p.id.isIn(slice))).go();
    }
    await _db.batch((batch) {
      for (var position = 0; position < plan.parts.length; position++) {
        switch (plan.parts[position]) {
          case KeptPart(:final part) when part.position != position:
            batch.update(
              _db.processedParts,
              ProcessedPartsCompanion(position: Value(position)),
              where: (p) => p.id.equals(part.id),
            );
          case KeptPart():
            break;
          case NewPart(:final candidate):
            final anchor = candidate.anchor;
            batch.insert(
              _db.processedParts,
              ProcessedPartsCompanion.insert(
                id: _ids.next(),
                documentId: documentId,
                section: plan.section,
                position: position,
                content: candidate.content,
                origin: candidate.origin,
                sourceRenditionId: Value(anchor?.renditionId),
                sourceStart: Value(anchor?.start),
                sourceEnd: Value(anchor?.end),
                createdAt: at,
                updatedAt: at,
              ),
            );
        }
      }
    });
  }

  @override
  Future<Either<Failure, Unit>> undo(ProcessUndo undo) =>
      _guard('undo', () async {
        final id = undo.documentId;
        final status = await _status(id);
        if (status == ProcessedDocumentStatus.absent) {
          // Lo que nació y ya se borró no tiene nada que deshacer; lo que
          // existía y ya no está, sí, y no se puede.
          return undo.previousStatus == ProcessedDocumentStatus.absent
              ? right(unit)
              : left(
                  const Failure.validation(
                    message: 'El documento procesado ya no existe.',
                  ),
                );
        }
        await _db.transaction(() async {
          if (undo.previousStatus == ProcessedDocumentStatus.absent) {
            // Nació con este procesado: deshacer es que no exista. Por el
            // escritor, como todo borrado de un elemento —primero a la
            // papelera, después de verdad—, y con él se van sus partes.
            await _writer.trash([id]);
            await _writer.purge(id);
            return;
          }
          for (final MapEntry(key: section, value: parts)
              in undo.previous.entries) {
            await (_db.delete(_db.processedParts)..where(
                  (p) =>
                      p.documentId.equals(id) & p.section.equalsValue(section),
                ))
                .go();
            await _insertParts(parts);
          }
          if (undo.previousStatus == ProcessedDocumentStatus.trashed &&
              status == ProcessedDocumentStatus.active) {
            await _writer.trash([id]);
          }
          await _writer.markContentChanged(id);
        });
        return right(unit);
      });

  /// Vuelve a poner [parts] tal como estaban —su id, su texto, su lugar, su
  /// ancla—. La forma de la fuente pudo irse mientras tanto: la parte vuelve
  /// igual, con sus posiciones y sin el enlace.
  Future<void> _insertParts(List<ProcessedPart> parts) async {
    if (parts.isEmpty) return;
    final renditionIds = {for (final p in parts) ?p.sourceRenditionId};
    final alive = <String>{};
    final wanted = renditionIds.toList();
    for (var start = 0; start < wanted.length; start += _idsPerQuery) {
      final slice = wanted.skip(start).take(_idsPerQuery).toList();
      final r = _db.renditions;
      alive.addAll(
        await (_db.selectOnly(r)
              ..addColumns([r.id])
              ..where(r.id.isIn(slice)))
            .map((row) => row.read(r.id)!)
            .get(),
      );
    }
    await _db.batch((batch) {
      for (final part in parts) {
        final renditionId = part.sourceRenditionId;
        batch.insert(
          _db.processedParts,
          ProcessedPartsCompanion.insert(
            id: part.id,
            documentId: part.documentId,
            section: part.section,
            position: part.position,
            content: part.content,
            origin: part.origin,
            edited: Value(part.edited),
            sourceRenditionId: Value(
              renditionId != null && alive.contains(renditionId)
                  ? renditionId
                  : null,
            ),
            sourceStart: Value(part.sourceStart),
            sourceEnd: Value(part.sourceEnd),
            createdAt: part.createdAt,
            updatedAt: part.updatedAt,
          ),
        );
      }
    });
  }

  @override
  Future<Either<Failure, ProcessedPart>> editPart(
    String partId,
    String content,
  ) => _guard('editPart', () async {
    if (content.trim().isEmpty) {
      return left(
        const Failure.validation(
          message: 'Una parte vacía no se guarda: para sacarla, quitala.',
        ),
      );
    }
    final before = await _part(partId);
    if (before == null) return left(_missingPart);
    if (before.content == content) return right(before);
    await _db.transaction(() async {
      await (_db.update(
        _db.processedParts,
      )..where((p) => p.id.equals(partId))).write(
        ProcessedPartsCompanion(
          content: Value(content),
          edited: Value(before.origin == ProcessedPartOrigin.copied),
          updatedAt: Value(_clock()),
        ),
      );
      await _writer.markContentChanged(before.documentId);
    });
    return right(before);
  });

  @override
  Future<Either<Failure, ProcessedPart>> removePart(String partId) =>
      _guard('removePart', () async {
        final before = await _part(partId);
        if (before == null) return left(_missingPart);
        await _db.transaction(() async {
          await (_db.delete(
            _db.processedParts,
          )..where((p) => p.id.equals(partId))).go();
          await _shift(before, by: -1);
          await _writer.markContentChanged(before.documentId);
        });
        return right(before);
      });

  @override
  Future<Either<Failure, Unit>> restorePart(ProcessedPart part) =>
      _guard('restorePart', () async {
        if (await _status(part.documentId) == ProcessedDocumentStatus.absent) {
          return left(
            const Failure.validation(
              message: 'El documento procesado ya no existe.',
            ),
          );
        }
        await _db.transaction(() async {
          final current = await _part(part.id);
          if (current != null) {
            await (_db.update(
              _db.processedParts,
            )..where((p) => p.id.equals(part.id))).write(
              ProcessedPartsCompanion(
                content: Value(part.content),
                edited: Value(part.edited),
                updatedAt: Value(part.updatedAt),
              ),
            );
          } else {
            await _shift(part, by: 1);
            await _insertParts([part]);
          }
          await _writer.markContentChanged(part.documentId);
        });
        return right(unit);
      });

  /// Corre [by] lugares las partes de la sección de [part] que van desde su
  /// lugar en adelante: para cerrar el hueco de una que se va, o abrírselo a
  /// una que vuelve.
  Future<void> _shift(ProcessedPart part, {required int by}) =>
      _db.customUpdate(
        'UPDATE processed_parts SET position = position + ? '
        'WHERE document_id = ? AND section = ? AND position >= ?',
        variables: [
          Variable.withInt(by),
          Variable.withString(part.documentId),
          Variable.withString(part.section.name),
          Variable.withInt(by < 0 ? part.position + 1 : part.position),
        ],
        updates: {_db.processedParts},
      );

  Future<ProcessedPart?> _part(String partId) async {
    final row = await (_db.select(
      _db.processedParts,
    )..where((p) => p.id.equals(partId))).getSingleOrNull();
    return row == null ? null : processedPartFromRow(row);
  }

  static const _missingPart = Failure.validation(
    message: 'Esa parte ya no está en el documento procesado.',
  );

  Future<Either<Failure, T>> _guard<T>(
    String name,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Un TypeError de una fila rara es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ProcessedRepositoryImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}

/// El documento no está como cuando se armó el plan: no se guarda nada.
class _Stale implements Exception {
  const _Stale(this.message);
  final String message;
}

/// La parte que guarda [row].
ProcessedPart processedPartFromRow(ProcessedPartRow row) => ProcessedPart(
  id: row.id,
  documentId: row.documentId,
  section: row.section,
  position: row.position,
  content: row.content,
  origin: row.origin,
  edited: row.edited,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  sourceRenditionId: row.sourceRenditionId,
  sourceStart: row.sourceStart,
  sourceEnd: row.sourceEnd,
);
