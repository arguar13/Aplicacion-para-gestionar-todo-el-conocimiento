import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_sql.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_resolver.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';

/// Cada documento procesado vivo con lo que dice su fila del selector de
/// Repasar (F43, M11), en UNA lectura: sus tarjetas y las de su fuente, si
/// tiene resumen o síntesis y cuántas creaciones lo usan.
///
/// Lo de cada documento es una búsqueda por clave —las tarjetas por
/// `idx_flashcards_item`, las partes por `idx_processed_parts_document`—, y
/// las creaciones se cuentan una sola vez para todos, agrupadas: contarlas por
/// documento abriría las fuentes de cada creación una vez por documento. Es la
/// regla de `creationsOfDocumentSql`: las creadas sobre él y las que lo
/// leyeron, cada una una vez.
@visibleForTesting
final creationScopeDocumentsSql =
    """
SELECT item.id AS id,
       item.title AS title,
       d.source_item_id AS source_item_id,
       (SELECT COUNT(*) FROM flashcards f
         WHERE f.item_id = item.id) AS own_cards,
       (SELECT COUNT(*) FROM flashcards f
          JOIN item source ON source.id = f.item_id
         WHERE f.item_id = d.source_item_id
           AND ${activeItemSql('source')}) AS source_cards,
       EXISTS (SELECT 1 FROM processed_parts p
                WHERE p.document_id = item.id
                  AND p.section = '${ProcessedSection.summary.name}')
         AS has_summary,
       EXISTS (SELECT 1 FROM processed_parts p
                WHERE p.document_id = item.id
                  AND p.section = '${ProcessedSection.synthesis.name}')
         AS has_synthesis,
       COALESCE(made.n, 0) AS creations
  FROM processed_documents d
  JOIN item ON item.id = d.item_id
  LEFT JOIN (
    SELECT document, COUNT(*) AS n FROM (
      SELECT c.id AS id, c.scope_id AS document
        FROM study_creations c
       WHERE c.deleted_at IS NULL
         AND c.scope_kind = '${ProcessedDocumentScope.key}'
      UNION
      SELECT c.id AS id, s.value AS document
        FROM study_creations c, json_each(c.source_ids_json) s
       WHERE c.deleted_at IS NULL)
     GROUP BY document) made ON made.document = item.id
 WHERE $kActiveItemSql""";

/// [CreationScopeResolver] sobre la base (F43).
///
/// Qué documentos tiene un recorte lo dicen las mismas consultas de siempre
/// —[ProcessedRepository.matchingIds] y [NotebookRepository.memberIds]—; acá
/// solo se cuenta y se nombra. Las listas de ids viajan a SQLite como UN JSON
/// (`json_each(?)`), no como un parámetro por id: «Todo lo procesado» con
/// diez mil documentos es una sola variable.
class CreationScopeResolverImpl implements CreationScopeResolver {
  CreationScopeResolverImpl({
    required AppDatabase database,
    required ProcessedRepository processed,
    required NotebookRepository notebooks,
    required TelemetryService telemetry,
  }) : _db = database,
       _processed = processed,
       _notebooks = notebooks,
       _telemetry = telemetry;

  final AppDatabase _db;
  final ProcessedRepository _processed;
  final NotebookRepository _notebooks;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, List<String>>> documentIds(CreationScope scope) =>
      switch (scope) {
        AllProcessed() => _processed.matchingIds(const ProcessedQuery()),
        // Por la misma consulta y no por su clave: así un documento en la
        // papelera, o que ya no es un procesado, no tiene nada que leer.
        ProcessedDocumentScope(:final documentId) => _processed.matchingIds(
          ProcessedQuery(ids: {documentId}),
        ),
        NotebookScope(:final notebookId) => _notebooks.memberIds(notebookId),
        TopicScope(:final valueId) => _processed.matchingIds(
          ProcessedQuery(propertyValueIds: {valueId}),
        ),
        SpaceScope(:final spaceId) => _processed.matchingIds(
          ProcessedQuery(spaceId: spaceId),
        ),
      };

  @override
  Future<Either<Failure, Set<String>?>> studyItemIds(String scopeKey) =>
      _guard('studyItemIds', () async {
        final scope = CreationScope.parse(scopeKey);
        if (scope == null) {
          return left(
            Failure.validation(message: 'Recorte de Procesado raro: $scopeKey'),
          );
        }
        if (scope.isAll) return right(null);
        final documents = await documentIds(scope);
        return documents.match(left, (ids) async {
          return right({...ids, ...await _sourceItemIdsOf(ids)});
        });
      });

  @override
  Future<Either<Failure, List<CreationSource>>> sourcesOf(
    List<String> documentIds,
  ) => _guard('sourcesOf', () async {
    if (documentIds.isEmpty) return right(const []);
    final ids = jsonEncode(documentIds);
    final summary = ProcessedSection.summary.name;
    final synthesis = ProcessedSection.synthesis.name;
    final keywords = ProcessedSection.keywords.name;
    // Una fila por id pedido, exista o no: lo que ya no es un procesado vivo
    // sale como «fuente borrada», sin título.
    final rows = await _db
        .customSelect(
          '''
          SELECT wanted.value AS document_id,
                 item.title AS title,
                 (item.id IS NOT NULL AND ${activeItemSql('item')}
                   AND d.item_id IS NOT NULL) AS live,
                 d.source_item_id AS source_item_id,
                 EXISTS (SELECT 1 FROM processed_parts p
                          WHERE p.document_id = wanted.value
                            AND p.section = '$summary') AS has_summary,
                 EXISTS (SELECT 1 FROM processed_parts p
                          WHERE p.document_id = wanted.value
                            AND p.section = '$synthesis') AS has_synthesis,
                 EXISTS (SELECT 1 FROM processed_parts p
                          WHERE p.document_id = wanted.value
                            AND p.section = '$keywords') AS has_keywords,
                 (SELECT COUNT(*) FROM flashcards f
                    JOIN item card_item ON card_item.id = f.item_id
                   WHERE ${activeItemSql('card_item')}
                     AND (f.item_id = wanted.value
                          OR f.item_id = d.source_item_id)) AS cards,
                 (SELECT COUNT(*) FROM study_creations c
                   WHERE ${creationsOfDocumentSql('wanted.value')}
                 ) AS creations
            FROM json_each(?) wanted
            LEFT JOIN item ON item.id = wanted.value
            LEFT JOIN processed_documents d ON d.item_id = wanted.value
           ORDER BY wanted.key''',
          variables: [Variable.withString(ids)],
          readsFrom: _tables,
        )
        .get();
    return right([
      for (final row in rows)
        CreationSource(
          documentId: row.read<String>('document_id'),
          title: row.readNullable<String>('title') ?? '',
          isLive: row.read<bool>('live'),
          sourceItemId: row.readNullable<String>('source_item_id'),
          hasSummary: row.read<bool>('has_summary'),
          hasSynthesis: row.read<bool>('has_synthesis'),
          hasKeywords: row.read<bool>('has_keywords'),
          cards: row.read<int>('cards'),
          creations: row.read<int>('creations'),
        ),
    ]);
  });

  @override
  Stream<CreationScopeSummary> watchSummary(CreationScope scope) => watchQuery(
    db: _db,
    tables: _tables,
    read: () => _summaryOf(scope),
    telemetry: _telemetry,
    hint: 'CreationScopeResolverImpl.watchSummary',
  );

  Future<CreationScopeSummary> _summaryOf(CreationScope scope) async {
    final name = await _nameOf(scope);
    final exists = scope.isAll || name != null;
    final documents = exists
        ? (await documentIds(scope)).getRight().toNullable() ?? const []
        : const <String>[];
    final cards = scope.isAll
        ? await _scalar(
            'SELECT COUNT(*) AS n FROM flashcards f '
            'JOIN item ON item.id = f.item_id WHERE $kActiveItemSql',
          )
        : await _cardsOf({...documents, ...await _sourceItemIdsOf(documents)});
    final creations = creationsInScopeSql(scope);
    return CreationScopeSummary(
      scope: scope,
      name: name,
      documents: documents.length,
      cards: cards,
      creations: await _scalar(
        'SELECT COUNT(*) AS n FROM study_creations c WHERE ${creations.sql}',
        creations.variables,
      ),
      exists: exists,
    );
  }

  @override
  Stream<CreationScopeCatalog> watchCatalog(Set<CreationScope> topics) =>
      watchQuery(
        db: _db,
        tables: _tables,
        read: () => _catalogOf(topics),
        telemetry: _telemetry,
        hint: 'CreationScopeResolverImpl.watchCatalog',
      );

  /// El catálogo del selector, en lote: cada documento con lo suyo en una
  /// lectura, «Todo» en otra, las creaciones de los cuadernos y los temas en
  /// otra, los cuadernos en dos, los nombres de los temas en una por clase y
  /// qué documentos tiene cada cuaderno y cada tema en una cada doscientos.
  /// Nada depende de cuántos documentos hay.
  ///
  /// Las tarjetas de un cuaderno o un tema se suman acá, por elemento, de las
  /// que ya trajo la lectura de los documentos: las suyas y las de su fuente,
  /// cada elemento una vez, como `_cardsOf`.
  Future<CreationScopeCatalog> _catalogOf(Set<CreationScope> requested) async {
    final documents = await _documentFacts();
    final cardsByItem = <String, int>{
      for (final d in documents) ...{
        d.id: d.ownCards,
        if (d.sourceItemId case final source?) source: d.sourceCards,
      },
    };
    final sourceOf = {
      for (final d in documents)
        if (d.sourceItemId case final source?) d.id: source,
    };
    int cardsOf(Set<String> documentIds) => {
      ...documentIds,
      for (final id in documentIds) ?sourceOf[id],
    }.fold(0, (sum, item) => sum + (cardsByItem[item] ?? 0));

    final made = await _creationsByScope();
    final totals = await _db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM flashcards f '
          'JOIN item ON item.id = f.item_id WHERE $kActiveItemSql) AS cards, '
          '(SELECT COUNT(*) FROM study_creations c '
          'WHERE c.deleted_at IS NULL) AS creations',
        )
        .getSingle();
    final notebooks = await _notebooks.resolveAllQueries();
    final topics = await _topicNamesOf(requested);
    final members = switch (await _processed.matchingIdsOfMany({
      for (final n in notebooks) NotebookScope(n.id).storageKey: n.query,
      for (final scope in topics.keys)
        scope.storageKey: switch (scope) {
          SpaceScope(:final spaceId) => ProcessedQuery(spaceId: spaceId),
          _ => ProcessedQuery(propertyValueIds: {scope.id!}),
        },
    })) {
      Right(:final value) => value,
      Left(:final value) => throw StateError(value.toString()),
    };

    CreationScopeLine lineOf(CreationScope scope, String name) {
      final ids = members[scope.storageKey] ?? const <String>{};
      return CreationScopeLine(
        scope: scope,
        name: name,
        documents: ids.length,
        cards: cardsOf(ids),
        creations: made[scope.storageKey] ?? 0,
      );
    }

    return CreationScopeCatalog(
      all: CreationScopeLine(
        scope: const CreationScope.allProcessed(),
        name: '',
        documents: documents.length,
        cards: totals.read<int>('cards'),
        creations: totals.read<int>('creations'),
      ),
      documents: [
        for (final d in documents)
          CreationScopeLine(
            scope: CreationScope.document(d.id),
            name: d.title,
            documents: 1,
            cards: cardsOf({d.id}),
            creations: d.creations,
            hasSummary: d.hasSummary,
            hasSynthesis: d.hasSynthesis,
          ),
      ],
      notebooks: [
        for (final n in notebooks) lineOf(CreationScope.notebook(n.id), n.name),
      ],
      topics: [
        for (final MapEntry(key: scope, value: name) in topics.entries)
          lineOf(scope, name),
      ],
    );
  }

  /// Cada documento procesado vivo con lo que dice su fila, en UNA lectura
  /// ([creationScopeDocumentsSql]).
  Future<List<_DocumentFacts>> _documentFacts() async {
    final rows = await _db.customSelect(creationScopeDocumentsSql).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          sourceItemId: row.readNullable<String>('source_item_id'),
          ownCards: row.read<int>('own_cards'),
          sourceCards: row.read<int>('source_cards'),
          hasSummary: row.read<bool>('has_summary'),
          hasSynthesis: row.read<bool>('has_synthesis'),
          creations: row.read<int>('creations'),
        ),
    ];
  }

  /// Las creaciones vivas de cada cuaderno y cada tema, por la clave del
  /// recorte, en una lectura: la regla de `creationsInScopeSql` para ellos.
  Future<Map<String, int>> _creationsByScope() async {
    final rows = await _db
        .customSelect(
          'SELECT c.scope_kind AS kind, c.scope_id AS id, COUNT(*) AS n '
          'FROM study_creations c WHERE c.deleted_at IS NULL '
          'AND c.scope_id IS NOT NULL '
          "AND c.scope_kind <> '${ProcessedDocumentScope.key}' "
          'GROUP BY c.scope_kind, c.scope_id',
        )
        .get();
    return {
      for (final row in rows)
        if (CreationScope.fromParts(
              row.read<String>('kind'),
              row.read<String>('id'),
            )
            case final scope?)
          scope.storageKey: row.read<int>('n'),
    };
  }

  /// El nombre de cada tema y cada espacio de [scopes] que existe: una lectura
  /// por clase, para todos.
  Future<Map<CreationScope, String>> _topicNamesOf(
    Set<CreationScope> scopes,
  ) async {
    final values = [
      for (final s in scopes)
        if (s is TopicScope) s.valueId,
    ];
    final spaces = [
      for (final s in scopes)
        if (s is SpaceScope) s.spaceId,
    ];
    Future<Map<String, String>> namesIn(String sql, List<String> ids) async {
      if (ids.isEmpty) return const {};
      final rows = await _db
          .customSelect(sql, variables: [Variable.withString(jsonEncode(ids))])
          .get();
      return {
        for (final row in rows)
          row.read<String>('id'): row.read<String>('name'),
      };
    }

    final valueNames = await namesIn(
      'SELECT id, value AS name FROM property_values '
      'WHERE id IN (SELECT value FROM json_each(?))',
      values,
    );
    final spaceNames = await namesIn(
      'SELECT id, name FROM spaces '
      'WHERE id IN (SELECT value FROM json_each(?))',
      spaces,
    );
    return {
      for (final s in scopes)
        if (s case TopicScope(:final valueId) when valueNames[valueId] != null)
          s: valueNames[valueId]!
        else if (s case SpaceScope(
          :final spaceId,
        ) when spaceNames[spaceId] != null)
          s: spaceNames[spaceId]!,
    };
  }

  /// El nombre de lo que apunta [scope]; `null` en «Todo» y si ya no existe.
  /// Un documento en la papelera ya no es del recorte: tampoco tiene nombre.
  Future<String?> _nameOf(CreationScope scope) async {
    final (sql, id) = switch (scope) {
      AllProcessed() => (null, null),
      ProcessedDocumentScope(:final documentId) => (
        'SELECT item.title AS name FROM item '
            'JOIN processed_documents d ON d.item_id = item.id '
            'WHERE item.id = ? AND $kActiveItemSql',
        documentId,
      ),
      NotebookScope(:final notebookId) => (
        'SELECT name FROM notebook WHERE id = ?',
        notebookId,
      ),
      TopicScope(:final valueId) => (
        'SELECT value AS name FROM property_values WHERE id = ?',
        valueId,
      ),
      SpaceScope(:final spaceId) => (
        'SELECT name FROM spaces WHERE id = ?',
        spaceId,
      ),
    };
    if (sql == null || id == null) return null;
    final row = await _db
        .customSelect(sql, variables: [Variable.withString(id)])
        .getSingleOrNull();
    return row?.read<String>('name');
  }

  /// Las fuentes de la Biblioteca de [documentIds] que siguen enlazadas: las
  /// tarjetas que cada documento muestra en «De la fuente».
  Future<Set<String>> _sourceItemIdsOf(List<String> documentIds) async {
    if (documentIds.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          'SELECT d.source_item_id AS id FROM processed_documents d '
          'WHERE d.item_id IN (SELECT value FROM json_each(?)) '
          'AND d.source_item_id IS NOT NULL',
          variables: [Variable.withString(jsonEncode(documentIds))],
        )
        .get();
    return {for (final row in rows) row.read<String>('id')};
  }

  /// Las tarjetas de [itemIds] cuyos elementos están vivos.
  Future<int> _cardsOf(Set<String> itemIds) async {
    if (itemIds.isEmpty) return 0;
    return _scalar(
      'SELECT COUNT(*) AS n FROM flashcards f '
      'JOIN item ON item.id = f.item_id '
      'WHERE f.item_id IN (SELECT value FROM json_each(?)) '
      'AND $kActiveItemSql',
      [Variable.withString(jsonEncode(itemIds.toList()))],
    );
  }

  Future<int> _scalar(
    String sql, [
    List<Variable<Object>> variables = const [],
  ]) async => (await _db.customSelect(sql, variables: variables).getSingle())
      .read<int>('n');

  /// Lo que puede cambiar un recorte, sus cifras o su nombre.
  Set<TableInfo<dynamic, dynamic>> get _tables => {
    _db.knowledgeEntries,
    _db.processedDocuments,
    _db.processedParts,
    _db.flashcards,
    _db.notebooks,
    _db.notebookItems,
    _db.itemPropertyValues,
    _db.propertyValues,
    _db.spaces,
    _db.itemSpaces,
    _db.studyCreations,
  };

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
        hint: 'CreationScopeResolverImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}

/// Lo de un documento procesado vivo que lee el catálogo del selector.
typedef _DocumentFacts = ({
  String id,
  String title,
  String? sourceItemId,
  int ownCards,
  int sourceCards,
  bool hasSummary,
  bool hasSynthesis,
  int creations,
});
