import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_row_mapping.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/core/util/text_anchor_locator.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_original_trash.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_query_sql.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_rows.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_section_planner.dart';
import 'package:sinapsis/features/processed/domain/services/processed_study_layout.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

export 'package:sinapsis/features/processed/data/repositories/processed_rows.dart'
    show processedPartFromRow;

/// La subcarpeta del procesado donde va la copia de su original.
const kProcessedOriginalFolder = 'original';

/// [ProcessedRepository] sobre la base (`processed_documents`,
/// `processed_parts` y `processed_originals`) y el almacén de archivos.
///
/// El elemento del procesado —su fila de `item` y su `note`— lo escribe
/// [KnowledgeEntryWriter], como todo elemento; sus partes y la copia de su
/// original, este repositorio. La fuente solo se lee: su texto, sus marcas de
/// estudio, su archivo —para copiarlo—.
class ProcessedRepositoryImpl implements ProcessedRepository {
  ProcessedRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required FileStore files,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _files = files,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final FileStore _files;
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
    _db.processedOriginals,
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
  /// partes tiene cada sección, si tiene la copia del original y sus temas.
  /// Nada que mida el texto.
  Future<List<ProcessedDocumentSummary>> _summariesOf(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final heads = <String, QueryRow>{};
    final counts = <String, Map<ProcessedSection, int>>{};
    final spaces = <String, Set<String>>{};
    final withOriginal = <String>{};
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
      withOriginal.addAll(
        await (_db.selectOnly(_db.processedOriginals)
              ..addColumns([_db.processedOriginals.documentId])
              ..where(_db.processedOriginals.documentId.isIn(slice)))
            .map((row) => row.read(_db.processedOriginals.documentId)!)
            .get(),
      );
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
            hasOriginal: withOriginal.contains(id),
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

  // --- La copia del original -----------------------------------------------

  @override
  Stream<ProcessedOriginal?> watchOriginal(String documentId) => watchQuery(
    db: _db,
    tables: [_db.processedOriginals, _db.renditions],
    read: () => _original(documentId),
    telemetry: _telemetry,
    hint: 'ProcessedRepositoryImpl.watchOriginal',
  );

  @override
  Future<Either<Failure, ProcessedOriginal?>> originalOf(String documentId) =>
      _guard('originalOf', () async => right(await _original(documentId)));

  Future<ProcessedOriginal?> _original(String documentId) async {
    final row =
        await (_db.select(_db.processedOriginals).join([
              innerJoin(
                _db.renditions,
                _db.renditions.id.equalsExp(_db.processedOriginals.renditionId),
              ),
            ])..where(_db.processedOriginals.documentId.equals(documentId)))
            .getSingleOrNull();
    if (row == null) return null;
    final original = row.readTable(_db.processedOriginals);
    final rendition = row.readTable(_db.renditions);
    return ProcessedOriginal(
      documentId: documentId,
      renditionId: rendition.id,
      relativePath: rendition.relativePath!,
      kind: rendition.kind,
      sizeBytes: rendition.sizeBytes ?? 0,
      copiedAt: original.copiedAt,
      sourceFilePath: original.sourceFilePath,
      mimeType: rendition.mimeType,
    );
  }

  @override
  Stream<ProcessedOriginalMarks?> watchOriginalMarks(String documentId) =>
      watchQuery(
        db: _db,
        tables: [
          _db.processedOriginals,
          _db.processedParts,
          _db.processedDocuments,
          _db.knowledgeSources,
          _db.renditions,
        ],
        read: () => _originalMarks(documentId),
        telemetry: _telemetry,
        hint: 'ProcessedRepositoryImpl.watchOriginalMarks',
      );

  /// Lo elegido del procesado, sobre el texto de la fuente con que se
  /// corresponde la copia —o nada, si ese texto ya no es el mismo—.
  Future<ProcessedOriginalMarks?> _originalMarks(String documentId) async {
    final original = await (_db.select(
      _db.processedOriginals,
    )..where((o) => o.documentId.equals(documentId))).getSingleOrNull();
    if (original == null) return null;
    final sourceKey = await _syncedSourceText(documentId, original.textHash);
    if (sourceKey == null) return null;
    final marks = <StudyMark>[];
    final fragments = <ProcessedSpan>[];
    for (final part in await _parts(documentId, kSectionsMarkedOnOriginal)) {
      final anchor = part.anchor;
      if (anchor == null || anchor.renditionId != sourceKey) continue;
      if (!part.isVerbatim) continue;
      switch (part.section) {
        case ProcessedSection.summary:
        case ProcessedSection.synthesis:
          marks.add(
            StudyMark(
              id: part.id,
              kind: part.section == ProcessedSection.summary
                  ? StudyMarkKind.summary
                  : StudyMarkKind.synthesis,
              origin: ContentOrigin.user,
              start: anchor.start,
              end: anchor.end,
            ),
          );
        case ProcessedSection.keywords:
          for (var i = 0; i < part.spans.length; i++) {
            final span = part.spans[i];
            marks.add(
              StudyMark(
                id: '${part.id}#$i',
                kind: StudyMarkKind.keyword,
                origin: ContentOrigin.user,
                start: anchor.start + span.start,
                end: anchor.start + span.end,
              ),
            );
          }
        case ProcessedSection.fragments:
          fragments.add(ProcessedSpan(start: anchor.start, end: anchor.end));
        case ProcessedSection.text || ProcessedSection.notes:
          break;
      }
    }
    marks.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
    fragments.sort((a, b) => a.start.compareTo(b.start));
    return ProcessedOriginalMarks(
      sourceKey: sourceKey,
      study: DocumentStudy(marks: marks, analyzedUntil: 0, complete: true),
      fragments: fragments,
    );
  }

  /// El `content_hash` de la fuente de [documentId] ahora, o `null` si no tiene
  /// texto o ya no está.
  Future<String?> _sourceTextHash(String documentId) async {
    final document = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(documentId))).getSingleOrNull();
    final sourceId = document?.sourceItemId;
    if (sourceId == null) return null;
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceId))).getSingleOrNull();
    final hash = source?.contentHash;
    return hash == null || hash.isEmpty ? null : hash;
  }

  /// La forma de texto de la fuente de [documentId], si su texto sigue siendo
  /// el que tenía al copiarse el original ([textHash]); `null` si no.
  Future<String?> _syncedSourceText(String documentId, String? textHash) async {
    if (textHash == null) return null;
    final document = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(documentId))).getSingleOrNull();
    final sourceId = document?.sourceItemId;
    if (sourceId == null) return null;
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceId))).getSingleOrNull();
    if (source == null || source.contentHash != textHash) return null;
    return (await sourceTextRenditionInfo(_db, sourceId))?.id;
  }

  @override
  Future<Either<Failure, StagedOriginal>> stageOriginal(String sourceItemId) =>
      _guard('stageOriginal', () async {
        final source = await _liveSource(sourceItemId);
        if (source == null) return left(_notASource);
        final offer = await _originalOffer(source.$2);
        if (offer == null) {
          return left(
            const Failure.validation(
              message: 'Esta fuente no tiene un original que copiar.',
            ),
          );
        }
        // La copia la hace el almacén, en el disco: ni pasa por la memoria ni
        // por este hilo.
        final copy = await _files.copy(
          offer.relativePath,
          id: processedDocumentIdFor(sourceItemId),
          folder: kProcessedOriginalFolder,
        );
        if (copy == null) {
          return left(
            const Failure.validation(
              message: 'El archivo de la fuente ya no está.',
            ),
          );
        }
        final hash = source.$2.contentHash;
        return right(
          StagedOriginal(
            relativePath: copy,
            sizeBytes: await _files.sizeOf(copy) ?? offer.sizeBytes,
            kind: offer.kind,
            sourceFilePath: offer.relativePath,
            sourceFileSize: offer.sizeBytes,
            textHash: hash.isEmpty ? null : hash,
          ),
        );
      });

  @override
  Future<void> discardStagedOriginal(StagedOriginal staged) async {
    try {
      await _files.delete(staged.relativePath);
      // Lo que no se pudo borrar queda: es un archivo de más, no uno de menos.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ProcessedRepositoryImpl.discardStagedOriginal',
      );
    }
  }

  /// El original de [source], si se puede copiar: el archivo de un documento
  /// de texto o la página web archivada, mientras esté.
  Future<ProcessedOriginalOffer?> _originalOffer(
    KnowledgeSourceRow source,
  ) async {
    final path = source.originalBlobPath;
    if (path == null) return null;
    if (source.sourceType != SourceKind.document &&
        source.sourceType != SourceKind.webPage) {
      return null;
    }
    final size = await _files.sizeOf(path);
    if (size == null) return null;
    final RenditionKind kind;
    if (source.sourceType == SourceKind.webPage) {
      kind = RenditionKind.html;
    } else {
      final head = await _files.readHead(path);
      final format = head == null
          ? FileFormat.unknown
          : detectFileFormat(head, name: p.basename(path));
      kind = format == FileFormat.pdf
          ? RenditionKind.pdf
          : RenditionKind.document;
    }
    return ProcessedOriginalOffer(
      relativePath: path,
      sizeBytes: size,
      kind: kind,
    );
  }

  // --- Estudiar el procesado -----------------------------------------------

  @override
  Future<Either<Failure, ProcessedStudyText?>> studyTextOf(String documentId) =>
      _guard('studyTextOf', () async {
        final layout = await pagesLayoutOf(_db, documentId);
        final markdown = await processedTextIsMarkdown(_db, documentId);
        if (layout != null) {
          final pages =
              await (_db.selectOnly(_db.processedParts)
                    ..addColumns([_db.processedParts.content])
                    ..where(
                      _db.processedParts.documentId.equals(documentId) &
                          _db.processedParts.section.equalsValue(
                            ProcessedSection.text,
                          ),
                    )
                    ..orderBy([
                      OrderingTerm.asc(_db.processedParts.position),
                      OrderingTerm.asc(_db.processedParts.id),
                    ]))
                  .map((row) => row.read(_db.processedParts.content)!)
                  .get();
          final size = layout.pagesLength;
          final content = await runProcessedWork(_join, pages, size: size);
          return right(
            ProcessedStudyText(
              key: processedStudyKeyFor(documentId),
              documentId: documentId,
              content: content,
              markdown: markdown,
              layout: layout,
            ),
          );
        }
        // Sin «Texto»: el de la fuente, si la copia del original es de él.
        final original = await (_db.select(
          _db.processedOriginals,
        )..where((o) => o.documentId.equals(documentId))).getSingleOrNull();
        final renditionId = original == null
            ? null
            : await _syncedSourceText(documentId, original.textHash);
        if (renditionId == null) return right(null);
        return right(
          ProcessedStudyText(
            key: processedStudyKeyFor(documentId),
            documentId: documentId,
            content: await _textOf(renditionId),
            markdown: markdown,
            layout: ProcessedStudyLayout.source(renditionId),
          ),
        );
      });

  // --- La fuente, solo para leer -------------------------------------------

  /// La fuente viva [sourceItemId]: su fila de `item` y la de `source`.
  Future<(KnowledgeEntryRow, KnowledgeSourceRow)?> _liveSource(
    String sourceItemId,
  ) async {
    final entry = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(sourceItemId) & e.isActive)).getSingleOrNull();
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceItemId))).getSingleOrNull();
    if (entry == null || entry.kind != ItemKind.source || source == null) {
      return null;
    }
    return (entry, source);
  }

  static const _notASource = Failure.validation(
    message:
        'Solo se procesa una fuente de la Biblioteca que no esté en la '
        'papelera.',
  );

  @override
  Future<Either<Failure, ProcessedSourceMaterial>> materialOf(
    String sourceItemId, {
    bool countWords = true,
  }) => _guard('materialOf', () async {
    final live = await _liveSource(sourceItemId);
    if (live == null) return left(_notASource);
    final (entry, source) = live;
    final text = await sourceTextRenditionInfo(_db, sourceItemId);
    final marks = text == null
        ? const <StudyMarkRow>[]
        : await (_db.select(_db.studyMarks)
                ..where((m) => m.renditionId.equals(text.id))
                ..orderBy([
                  (m) => OrderingTerm.asc(m.startOffset),
                  (m) => OrderingTerm.asc(m.endOffset),
                  (m) => OrderingTerm.asc(m.id),
                ]))
              .get();
    final keywordMarks = [
      for (final mark in marks)
        if (mark.kind == StudyMarkKind.keyword) mark,
    ];
    // El texto se trae solo si hace falta: para contar sus palabras o para
    // ubicar las palabras clave en sus oraciones. Las dos cosas, en otro hilo.
    String? content;
    if (text != null && (countWords || keywordMarks.isNotEmpty)) {
      content = await _textOf(text.id);
    }
    var words = 0;
    if (countWords && content != null) {
      words = await runProcessedWork(
        processedWordCount,
        content,
        size: content.length,
      );
    }
    var keywords = const <ProcessedKeywordSentence>[];
    if (content != null && keywordMarks.isNotEmpty && text != null) {
      final sentences = await runProcessedWork(_sentencesInWorker, (
        content: content,
        markdown: extractedTextIsMarkdown(sourceFor(entry, source)),
      ), size: content.length);
      keywords = _keywordSentences(text.id, content, sentences, keywordMarks);
    }
    List<ProcessedSentence> of(StudyMarkKind kind) => [
      for (final mark in marks)
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
        keywords: keywords,
        original: await _originalOffer(source),
      ),
    );
  });

  /// Las oraciones de [sentences] que tienen alguna de [marks] adentro, cada
  /// una con las suyas, en orden.
  static List<ProcessedKeywordSentence> _keywordSentences(
    String renditionId,
    String content,
    List<StudySentence> sentences,
    List<StudyMarkRow> marks,
  ) {
    final result = <ProcessedKeywordSentence>[];
    var next = 0;
    for (final sentence in sentences) {
      while (next < marks.length && marks[next].startOffset < sentence.start) {
        next++;
      }
      final inside = <ProcessedKeyword>[];
      for (var i = next; i < marks.length; i++) {
        final mark = marks[i];
        if (mark.startOffset >= sentence.end) break;
        if (mark.endOffset > sentence.end) continue;
        inside.add(
          ProcessedKeyword(
            studyMarkId: mark.id,
            start: mark.startOffset,
            end: mark.endOffset,
            word: content.substring(mark.startOffset, mark.endOffset),
          ),
        );
      }
      if (inside.isEmpty) continue;
      result.add(
        ProcessedKeywordSentence(
          anchor: ProcessedAnchor(
            renditionId: renditionId,
            start: sentence.start,
            end: sentence.end,
          ),
          content: content.substring(sentence.start, sentence.end),
          keywords: inside,
        ),
      );
    }
    return result;
  }

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

    // Antes de tocar el texto, dónde estaba cada parte en el texto propio y
    // hasta dónde estaba estudiado: deshacer lo devuelve.
    final textPlan = commit.plans
        .where((plan) => plan.section == ProcessedSection.text)
        .firstOrNull;
    final textChanges = textPlan != null && !textPlan.isNoOp;
    final textRanges = textChanges
        ? await _textRangesOf(documentId)
        : const <String, ProcessedSpan?>{};
    final study = textChanges ? await _studyProgressOf(documentId) : null;

    var changed = status != ProcessedDocumentStatus.active;
    for (final plan in commit.plans) {
      if (plan.isNoOp) continue;
      changed = true;
      await _applyPlan(documentId, plan, at);
    }
    final original = commit.original == null
        ? null
        : await _applyOriginal(documentId, commit.original!, at);
    if (original != null) changed = true;
    if (changed) {
      await _relayout(documentId);
      if (textChanges) await _resetStudy(documentId);
      await _writer.markContentChanged(documentId);
    }

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
      textRanges: textRanges,
      study: study,
      original: original,
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
    final live = await _liveSource(sourceItemId);
    if (live == null) {
      throw const _Stale('La fuente ya no está en la Biblioteca.');
    }
    final (entry, source) = live;
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
                spans: Value(
                  encodeProcessedSpans(plan.section, candidate.spans),
                ),
                createdAt: at,
                updatedAt: at,
              ),
            );
        }
      }
    });
  }

  /// Hace con la copia del original lo que dice [plan] y devuelve cómo
  /// deshacerlo, o `null` si no cambió nada.
  Future<ProcessedOriginalUndo?> _applyOriginal(
    String documentId,
    ProcessedOriginalPlan plan,
    DateTime at,
  ) async {
    switch (plan) {
      case RemoveOriginal():
        final trashed = await trashProcessedOriginal(
          _db,
          documentId: documentId,
          ids: _ids,
          at: at,
        );
        return trashed == null
            ? null
            : ProcessedOriginalUndo(trashedId: trashed);
      case RefreshOriginal():
        final current = await (_db.select(
          _db.processedOriginals,
        )..where((o) => o.documentId.equals(documentId))).getSingleOrNull();
        final textHash = await _sourceTextHash(documentId);
        if (current == null || current.textHash == textHash) return null;
        await (_db.update(_db.processedOriginals)
              ..where((o) => o.documentId.equals(documentId)))
            .write(ProcessedOriginalsCompanion(textHash: Value(textHash)));
        return ProcessedOriginalUndo(
          refreshed: true,
          previousTextHash: current.textHash,
        );
      case PutOriginal(:final staged):
        final trashed = await trashProcessedOriginal(
          _db,
          documentId: documentId,
          ids: _ids,
          at: at,
        );
        final renditionId = processedOriginalRenditionIdFor(documentId);
        await _db
            .into(_db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: renditionId,
                itemId: documentId,
                kind: staged.kind,
                relativePath: Value(staged.relativePath),
                isPrimary: false,
                mimeType: Value(staged.mimeType),
                sizeBytes: Value(staged.sizeBytes),
                createdAt: at,
              ),
            );
        await _db
            .into(_db.processedOriginals)
            .insert(
              ProcessedOriginalsCompanion.insert(
                documentId: documentId,
                renditionId: renditionId,
                sourceFilePath: staged.sourceFilePath,
                sourceFileSize: staged.sourceFileSize,
                textHash: Value(staged.textHash),
                copiedAt: at,
              ),
            );
        return ProcessedOriginalUndo(
          copiedPath: staged.relativePath,
          trashedId: trashed,
        );
    }
  }

  /// Vuelve a ubicar en el texto propio (decisión I) las páginas de
  /// [documentId] —una detrás de la otra— y lo demás: lo copiado de la fuente
  /// letra por letra va donde su página de la fuente lo pone, y lo estudiado en
  /// el procesado se queda donde estaba si el texto ahí sigue siendo el suyo.
  /// Sin páginas, nada tiene lugar en un texto propio: el de la fuente se
  /// mira por el ancla.
  Future<void> _relayout(String documentId) async {
    final parts = await _parts(documentId, null);
    final pages = [
      for (final part in parts)
        if (part.section == ProcessedSection.text) part,
    ];
    final ranges = <String, ProcessedSpan?>{};
    var at = 0;
    final placed = <ProcessedTextPage>[];
    for (final page in pages) {
      final end = at + page.content.length;
      ranges[page.id] = ProcessedSpan(start: at, end: end);
      placed.add(
        ProcessedTextPage(
          partId: page.id,
          start: at,
          end: end,
          source: page.isPristineCopy ? page.anchor : null,
        ),
      );
      at = end;
    }
    final layout = ProcessedStudyLayout.pages(placed);
    String? joined;
    for (final part in parts) {
      if (part.section == ProcessedSection.text ||
          part.section == ProcessedSection.notes) {
        continue;
      }
      if (pages.isEmpty) {
        ranges[part.id] = null;
        continue;
      }
      // Dónde estaría: lo que dice su ancla en la fuente, si es su letra; si
      // no, lo que ya tenía, si es propia. Y en los dos casos, solo si el
      // texto propio ahí es de verdad el suyo: un ancla puede haber quedado
      // vieja, y una página, cambiar debajo.
      final anchor = part.anchor;
      final candidate =
          (anchor != null && part.isVerbatim ? layout.ownOf(anchor) : null) ??
          (part.isStudiedHere ? part.textRange : null);
      if (candidate == null) {
        ranges[part.id] = null;
        continue;
      }
      final own = joined ??= await runProcessedWork<List<String>, String>(
        _join,
        [for (final page in pages) page.content],
        size: layout.pagesLength,
      );
      ranges[part.id] =
          candidate.end <= own.length &&
              own.substring(candidate.start, candidate.end) == part.content
          ? candidate
          : null;
    }
    await _writeTextRanges(parts, ranges);
  }

  /// Escribe [ranges] —por id de parte— solo donde cambió algo.
  Future<void> _writeTextRanges(
    List<ProcessedPart> parts,
    Map<String, ProcessedSpan?> ranges,
  ) => _db.batch((batch) {
    for (final part in parts) {
      if (!ranges.containsKey(part.id)) continue;
      final range = ranges[part.id];
      if (range == part.textRange) continue;
      batch.update(
        _db.processedParts,
        ProcessedPartsCompanion(
          textStart: Value(range?.start),
          textEnd: Value(range?.end),
        ),
        where: (p) => p.id.equals(part.id),
      );
    }
  });

  /// Dónde está cada parte de [documentId] en el texto propio.
  Future<Map<String, ProcessedSpan?>> _textRangesOf(String documentId) async {
    final pp = _db.processedParts;
    final rows =
        await (_db.selectOnly(pp)
              ..addColumns([pp.id, pp.textStart, pp.textEnd])
              ..where(pp.documentId.equals(documentId)))
            .get();
    return {
      for (final row in rows)
        row.read(pp.id)!: switch ((
          row.read(pp.textStart),
          row.read(pp.textEnd),
        )) {
          (final int start, final int end) => ProcessedSpan(
            start: start,
            end: end,
          ),
          _ => null,
        },
    };
  }

  Future<({int analyzedUntil, DateTime? completedAt})> _studyProgressOf(
    String documentId,
  ) async {
    final row = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(documentId))).getSingle();
    return (
      analyzedUntil: row.studyAnalyzedUntil,
      completedAt: row.studyCompletedAt,
    );
  }

  /// El texto propio cambió: lo estudiado en él se vuelve a analizar desde el
  /// principio —lo hecho queda; las posiciones de antes ya no valen—.
  Future<void> _resetStudy(String documentId) =>
      (_db.update(
        _db.processedDocuments,
      )..where((d) => d.itemId.equals(documentId))).write(
        const ProcessedDocumentsCompanion(
          studyAnalyzedUntil: Value(0),
          studyCompletedAt: Value(null),
        ),
      );

  @override
  Future<Either<Failure, Unit>> undo(
    ProcessUndo undo,
  ) => _guard('undo', () async {
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
    final filesToDelete = <String>[];
    await _db.transaction(() async {
      if (undo.previousStatus == ProcessedDocumentStatus.absent) {
        // Nació con este procesado: deshacer es que no exista. Por el
        // escritor, como todo borrado de un elemento —primero a la papelera,
        // después de verdad—, y con él se van sus partes y su original.
        await _writer.trash([id]);
        await _writer.purge(id);
        if (undo.original?.copiedPath case final path?) filesToDelete.add(path);
        return;
      }
      for (final MapEntry(key: section, value: parts)
          in undo.previous.entries) {
        await (_db.delete(_db.processedParts)..where(
              (p) => p.documentId.equals(id) & p.section.equalsValue(section),
            ))
            .go();
        await _insertParts(parts);
      }
      if (undo.textRanges.isNotEmpty) {
        await _writeTextRanges(await _parts(id, null), {
          for (final part in await _parts(id, null))
            if (undo.textRanges.containsKey(part.id))
              part.id: undo.textRanges[part.id],
        });
      }
      if (undo.study case final study?) {
        await (_db.update(
          _db.processedDocuments,
        )..where((d) => d.itemId.equals(id))).write(
          ProcessedDocumentsCompanion(
            studyAnalyzedUntil: Value(study.analyzedUntil),
            studyCompletedAt: Value(study.completedAt),
          ),
        );
      }
      if (undo.original case final original?) {
        filesToDelete.addAll(await _undoOriginal(id, original));
      }
      if (undo.previousStatus == ProcessedDocumentStatus.trashed &&
          status == ProcessedDocumentStatus.active) {
        await _writer.trash([id]);
      }
      await _writer.markContentChanged(id);
    });
    for (final path in filesToDelete) {
      await discardStagedOriginal(
        StagedOriginal(
          relativePath: path,
          sizeBytes: 0,
          kind: RenditionKind.document,
          sourceFilePath: path,
          sourceFileSize: 0,
        ),
      );
    }
    return right(unit);
  });

  /// Deshace lo que se le hizo a la copia del original y devuelve los archivos
  /// que quedan sin usar: la copia que se había hecho.
  Future<List<String>> _undoOriginal(
    String documentId,
    ProcessedOriginalUndo undo,
  ) async {
    final orphaned = <String>[];
    if (undo.refreshed) {
      await (_db.update(
        _db.processedOriginals,
      )..where((o) => o.documentId.equals(documentId))).write(
        ProcessedOriginalsCompanion(textHash: Value(undo.previousTextHash)),
      );
    }
    if (undo.copiedPath case final path?) {
      await (_db.delete(_db.renditions)..where(
            (r) =>
                r.itemId.equals(documentId) &
                r.id.equals(processedOriginalRenditionIdFor(documentId)) &
                r.relativePath.equals(path),
          ))
          .go();
      orphaned.add(path);
    }
    if (undo.trashedId case final trashedId?) {
      final row = await (_db.select(
        _db.trashedContents,
      )..where((t) => t.id.equals(trashedId))).getSingleOrNull();
      if (row != null) await restoreTrashedProcessedOriginal(_db, row);
    }
    return orphaned;
  }

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
        batch.insert(
          _db.processedParts,
          processedPartCompanion(
            part,
            renditionAlive: alive.contains(part.sourceRenditionId),
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
          spans: Value(
            encodeProcessedSpans(
              before.section,
              relocateKeywordSpans(before, content),
            ),
          ),
        ),
      );
      if (before.section == ProcessedSection.text) {
        await _pageResized(before, content);
      } else if (before.textRange != null) {
        // Una oración editada ya no es el texto propio letra por letra.
        await (_db.update(
          _db.processedParts,
        )..where((p) => p.id.equals(partId))).write(
          const ProcessedPartsCompanion(
            textStart: Value(null),
            textEnd: Value(null),
          ),
        );
      }
      await _writer.markContentChanged(before.documentId);
    });
    return right(before);
  });

  /// La página [page] pasó a decir [content] (o se fue, con `null`): lo que le
  /// sigue en el texto propio se corre, lo que estaba adentro se vuelve a
  /// buscar en su texto nuevo —o se queda sin lugar—, y lo estudiado se vuelve
  /// a analizar desde el principio. Sin traer el libro: solo esa página.
  Future<void> _pageResized(ProcessedPart page, String? content) async {
    final range = page.textRange;
    final documentId = page.documentId;
    if (range != null) {
      final newLength = content?.length ?? 0;
      final delta = newLength - (range.end - range.start);
      final inside = [
        for (final part in await _parts(documentId, null))
          if (part.section != ProcessedSection.text &&
              part.textRange != null &&
              part.textRange!.start < range.end &&
              part.textRange!.end > range.start)
            part,
      ];
      if (delta != 0) {
        await _db.customUpdate(
          'UPDATE processed_parts '
          'SET text_start = text_start + ?, text_end = text_end + ? '
          'WHERE document_id = ? AND text_start >= ?',
          variables: [
            Variable.withInt(delta),
            Variable.withInt(delta),
            Variable.withString(documentId),
            Variable.withInt(range.end),
          ],
          updates: {_db.processedParts},
        );
      }
      if (content != null) {
        await (_db.update(
          _db.processedParts,
        )..where((p) => p.id.equals(page.id))).write(
          ProcessedPartsCompanion(textEnd: Value(range.start + newLength)),
        );
      }
      final locator = content == null ? null : ExcerptLocator(content);
      await _db.batch((batch) {
        for (final part in inside) {
          final own = part.textRange!;
          final found = own.start >= range.start && own.end <= range.end
              ? locator?.locate(part.content, near: own.start - range.start)
              : null;
          final fits =
              found != null &&
              content!.substring(found.start, found.end) == part.content;
          batch.update(
            _db.processedParts,
            ProcessedPartsCompanion(
              textStart: Value(fits ? range.start + found.start : null),
              textEnd: Value(fits ? range.start + found.end : null),
            ),
            where: (p) => p.id.equals(part.id),
          );
        }
      });
    }
    await _resetStudy(documentId);
  }

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
          if (before.section == ProcessedSection.text) {
            await _pageResized(before, null);
          }
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
                spans: Value(encodeProcessedSpans(part.section, part.spans)),
              ),
            );
            if (part.section == ProcessedSection.text) {
              await _pageResized(current, part.content);
            } else {
              await (_db.update(
                _db.processedParts,
              )..where((p) => p.id.equals(part.id))).write(
                ProcessedPartsCompanion(
                  textStart: Value(part.textStart),
                  textEnd: Value(part.textEnd),
                ),
              );
            }
          } else {
            await _shift(part, by: 1);
            if (part.section == ProcessedSection.text) {
              await _pageInserted(part);
            }
            await _insertParts([part]);
          }
          await _writer.markContentChanged(part.documentId);
        });
        return right(unit);
      });

  /// La página [page] vuelve a su lugar: lo que le sigue en el texto propio se
  /// corre para dejarle su espacio, y lo estudiado se vuelve a analizar.
  Future<void> _pageInserted(ProcessedPart page) async {
    final range = page.textRange;
    if (range != null) {
      final length = page.content.length;
      await _db.customUpdate(
        'UPDATE processed_parts '
        'SET text_start = text_start + ?, text_end = text_end + ? '
        'WHERE document_id = ? AND text_start >= ?',
        variables: [
          Variable.withInt(length),
          Variable.withInt(length),
          Variable.withString(page.documentId),
          Variable.withInt(range.start),
        ],
        updates: {_db.processedParts},
      );
    }
    await _resetStudy(page.documentId);
  }

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

/// Los tramos de las palabras clave de [part] en su texto nuevo [content]:
/// cada palabra se busca, en orden, a partir de donde terminó la anterior; la
/// que ya no está se va. Fuera de las palabras clave, ninguno.
List<ProcessedSpan> relocateKeywordSpans(ProcessedPart part, String content) {
  if (part.section != ProcessedSection.keywords) return const [];
  final spans = <ProcessedSpan>[];
  var from = 0;
  for (final span in part.spans) {
    final word = part.content.substring(span.start, span.end);
    final at = content.indexOf(word, from);
    if (at < 0) continue;
    spans.add(span.copyWith(start: at, end: at + word.length));
    from = at + word.length;
  }
  return spans;
}

String _join(List<String> pages) => pages.join();

List<StudySentence> _sentencesInWorker(({String content, bool markdown}) job) =>
    splitStudySentences(job.content, markdown: job.markdown);

/// El documento no está como cuando se armó el plan: no se guarda nada.
class _Stale implements Exception {
  const _Stale(this.message);
  final String message;
}
