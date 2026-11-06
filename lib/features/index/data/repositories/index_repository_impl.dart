import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/index/data/repositories/index_query_sql.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/repositories/index_repository.dart';
import 'package:sinapsis/features/index/domain/services/index_order.dart';
import 'package:sinapsis/features/processed/domain/services/headings/settle_headings.dart';

/// [IndexRepository] sobre `processed_headings` (F46, v51) y lo que ya está en
/// Procesado: el nombre de cada documento y sus temas se leen de donde están.
/// Ver `index_query_sql.dart` para qué índice usa cada lectura.
class IndexRepositoryImpl implements IndexRepository {
  IndexRepositoryImpl({
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

  /// Quien escribe el elemento del documento: ver [KnowledgeEntryWriter].
  KnowledgeEntryWriter get _writer =>
      KnowledgeEntryWriter(_db, clock: _clock, ids: _ids);

  Stream<T> _watch<T>(String name, Future<T> Function() read) => watchQuery(
    db: _db,
    tables: indexTables(_db),
    read: read,
    telemetry: _telemetry,
    hint: 'IndexRepositoryImpl.$name',
  );

  Future<List<QueryRow>> _select(
    String sql, [
    List<Variable<Object>> variables = const [],
  ]) => _db
      .customSelect(
        sql,
        variables: variables,
        readsFrom: indexTables(_db).toSet(),
      )
      .get();

  // --- El árbol -------------------------------------------------------------

  @override
  Stream<List<IndexTopic>> watchTopics() => _watch('watchTopics', () async {
    final topics = <IndexTopic>[];
    IndexTopic? untopiced;
    for (final row in await _select(indexTopicsSql)) {
      final count = row.read<int>('documents');
      if (count == 0) continue;
      final spaceId = row.read<String?>('space_id');
      final topic = IndexTopic(
        spaceId: spaceId,
        name: row.read<String?>('name') ?? '',
        documentCount: count,
      );
      if (spaceId == null) {
        untopiced = topic;
      } else {
        topics.add(topic);
      }
    }
    return [..._byName(topics, (t) => t.name), ?untopiced];
  });

  @override
  Stream<List<IndexDocument>> watchDocumentsOf(String? spaceId) => _watch(
    'watchDocumentsOf',
    () async => _byName(
      _documentsFrom(
        spaceId == null
            ? await _select(indexUntopicedDocumentsSql)
            : await _select(indexDocumentsOfTopicSql, [
                Variable.withString(spaceId),
              ]),
      ),
      (d) => d.title,
    ),
  );

  @override
  Stream<List<IndexDocument>> watchDocuments(IndexDocumentOrder order) =>
      _watch('watchDocuments', () async {
        final documents = _documentsFrom(await _select(indexDocumentsSql));
        return switch (order) {
          IndexDocumentOrder.title => _byName(documents, (d) => d.title),
          IndexDocumentOrder.recent =>
            documents..sort((a, b) {
              final byDate = b.createdAt.compareTo(a.createdAt);
              return byDate != 0 ? byDate : a.id.compareTo(b.id);
            }),
        };
      });

  @override
  Stream<List<IndexEntry>> watchEntries(String documentId) =>
      _watch('watchEntries', () async {
        final entries = [
          for (final row in await _select(indexEntriesSql, [
            Variable.withString(documentId),
          ]))
            _entryFrom(row),
        ];
        // Los capítulos —o «Texto completo»— primero y las imágenes después,
        // cada clase en el orden en que vino: el del índice.
        return [
          for (final entry in entries)
            if (!entry.isImage) entry,
          for (final entry in entries)
            if (entry.isImage) entry,
        ];
      });

  List<IndexDocument> _documentsFrom(List<QueryRow> rows) => [
    for (final row in rows)
      IndexDocument(
        id: row.read<String>('id'),
        title: row.read<String>('title'),
        sourceKind: SourceKind.values.byName(row.read<String>('source_kind')),
        createdAt: row.read<DateTime>('created_at'),
        chapterCount: row.read<int>('chapters'),
        imageCount: row.read<int>('images'),
        hasText: row.read<bool>('has_text'),
        indexed: row.read<bool>('indexed'),
        spaceIds: _spaceIdsOf(row),
      ),
  ];

  // --- La búsqueda ----------------------------------------------------------

  @override
  Stream<List<IndexSearchHit>> watchSearch(String query, {int limit = 200}) {
    final match = buildSearchQuery(query);
    if (match.isEmpty) return Stream.value(const []);
    return _watch('watchSearch', () async {
      final rows = await _select(indexSearchSql, [
        Variable.withString(match),
        Variable.withInt(limit),
      ]);
      final ancestors = await _ancestorsOf([
        for (final row in rows)
          if (row.read<String>('origin') != IndexEntryOrigin.image.name)
            row.read<int>('row_key'),
      ]);
      final hits = [
        for (final row in rows)
          IndexSearchHit(
            entry: _entryFrom(row),
            documentTitle: row.read<String>('document_title'),
            sourceKind: SourceKind.values.byName(
              row.read<String>('source_kind'),
            ),
            spaceIds: _spaceIdsOf(row),
            ancestors: ancestors[row.read<int>('row_key')] ?? const [],
          ),
      ];
      // Las que mejor coincidían entraron en el corte; se muestran en el orden
      // del Índice: por documento y, dentro de él, como en el árbol.
      final keyed =
          [
            for (final hit in hits)
              (key: indexSortKey(hit.documentTitle), hit: hit),
          ]..sort((a, b) {
            final byTitle = a.key.compareTo(b.key);
            if (byTitle != 0) return byTitle;
            final x = a.hit.entry;
            final y = b.hit.entry;
            final byDocument = x.documentId.compareTo(y.documentId);
            if (byDocument != 0) return byDocument;
            final byKind = (x.isImage ? 1 : 0) - (y.isImage ? 1 : 0);
            return byKind != 0 ? byKind : x.position.compareTo(y.position);
          });
      return [for (final entry in keyed) entry.hit];
    });
  }

  /// Los capítulos que contienen a cada una de [keys], del nivel 1 hacia
  /// abajo, por la clave de la entrada.
  Future<Map<int, List<IndexEntry>>> _ancestorsOf(List<int> keys) async {
    if (keys.isEmpty) return const {};
    final chains = <int, List<IndexEntry>>{};
    for (final row in await _select(indexAncestorsSql(keys.length), [
      for (final key in keys) Variable.withInt(key),
    ])) {
      chains.putIfAbsent(row.read<int>('hit'), () => []).add(_entryFrom(row));
    }
    for (final chain in chains.values) {
      chain.sort((a, b) => a.level.compareTo(b.level));
    }
    return chains;
  }

  // --- El relleno -----------------------------------------------------------

  @override
  Stream<IndexProgress> watchProgress() => _watch('watchProgress', () async {
    final row = (await _select(indexProgressSql)).single;
    return IndexProgress(
      documents: row.read<int>('documents'),
      indexedDocuments: row.read<int>('indexed'),
      untitledImages: row.read<int>('untitled'),
    );
  });

  // --- Escribir -------------------------------------------------------------

  @override
  Future<Either<Failure, Unit>> renameImage(
    String imageId,
    String title,
  ) => _guard('renameImage', () async {
    final settled = collapseSpaces(title);
    if (settled.isEmpty) {
      return left(
        const Failure.validation(message: 'Una imagen no se queda sin título.'),
      );
    }
    final image = await (_db.select(
      _db.processedImages,
    )..where((i) => i.renditionId.equals(imageId))).getSingleOrNull();
    if (image == null) {
      return left(const Failure.validation(message: 'La imagen ya no está.'));
    }
    if (image.title == settled) return right(unit);
    await _db.transaction(() async {
      await (_db.update(_db.processedImages)
            ..where((i) => i.renditionId.equals(imageId)))
          .write(ProcessedImagesCompanion(title: Value(settled)));
      // Renombrar una imagen es tocar el documento, como quitarla.
      await _writer.markContentChanged(image.documentId);
    });
    return right(unit);
  });

  // --- Filas ----------------------------------------------------------------

  IndexEntry _entryFrom(QueryRow row) => IndexEntry(
    key: row.read<int>('row_key'),
    documentId: row.read<String>('document_id'),
    origin: IndexEntryOrigin.values.byName(row.read<String>('origin')),
    level: row.read<int>('level'),
    position: row.read<int>('position'),
    title: row.read<String>('title'),
    textStart: row.read<int?>('text_start'),
    textEnd: row.read<int?>('text_end'),
    textPage: row.read<int?>('text_page'),
    pdfPage: row.read<int?>('pdf_page'),
    imageId: row.read<String?>('image_id'),
  );

  List<String> _spaceIdsOf(QueryRow row) {
    final joined = row.read<String?>('space_ids');
    if (joined == null || joined.isEmpty) return const [];
    return joined.split(indexSpaceIdSeparator)..sort();
  }

  /// [items] de la A a la Z por [nameOf], sin mayúsculas ni acentos. La clave
  /// de cada uno se arma una vez, no en cada comparación.
  List<T> _byName<T>(List<T> items, String Function(T) nameOf) {
    final keyed =
        [
          for (final item in items)
            (key: indexSortKey(nameOf(item)), item: item),
        ]..sort((a, b) {
          final byKey = a.key.compareTo(b.key);
          return byKey != 0 ? byKey : nameOf(a.item).compareTo(nameOf(b.item));
        });
    return [for (final entry in keyed) entry.item];
  }

  Future<Either<Failure, T>> _guard<T>(
    String name,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Un TypeError de una fila rara es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'IndexRepositoryImpl.$name');
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
