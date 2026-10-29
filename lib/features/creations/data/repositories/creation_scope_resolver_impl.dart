import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_sql.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_resolver.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';

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
