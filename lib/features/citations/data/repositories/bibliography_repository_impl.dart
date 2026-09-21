import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// [BibliographyRepository] sobre la base.
///
/// Una bibliografía de miles de fuentes son unas pocas consultas, no una por
/// fuente: los elementos y sus fuentes por tandas de identificadores, y sus
/// datos bibliográficos con `ReferenceReader`, que también lee por tandas. De
/// lo que hay que citar lee lo que la cita necesita y nada más: ni el texto
/// —que es lo que pesa—, ni las formas, ni los chunks.
class BibliographyRepositoryImpl implements BibliographyRepository {
  BibliographyRepositoryImpl(this._db) : _references = ReferenceReader(_db);

  final AppDatabase _db;
  final ReferenceReader _references;

  /// Cuántos ids entran en una sola consulta: por debajo del tope de
  /// parámetros de SQLite.
  static const _idsPerQuery = 400;

  @override
  Future<List<BibliographySource>> sourcesOf(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    final entries = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;

    final rows = <String, ({String title, KnowledgeSourceRow source})>{};
    for (var start = 0; start < ids.length; start += _idsPerQuery) {
      final slice = ids.skip(start).take(_idsPerQuery).toList();
      // Unir con `source` deja afuera lo que no es una fuente —una nota no
      // tiene fila ahí—, y la papelera se deja afuera por el mismo camino que
      // en el resto de las lecturas.
      final query = _db.select(entries).join([
        innerJoin(sources, sources.itemId.equalsExp(entries.id)),
      ])..where(entries.id.isIn(slice) & entries.isActive);
      for (final row in await query.get()) {
        final entry = row.readTable(entries);
        rows[entry.id] = (title: entry.title, source: row.readTable(sources));
      }
    }

    final references = await _references.readMany(rows.keys);
    return [
      for (final id in ids)
        if (rows[id] case final row?)
          BibliographySource(
            itemId: id,
            source: _citationSource(
              row.title,
              row.source,
              references[id] ?? const ReferenceData(),
            ),
          ),
    ];
  }

  /// Lo que hace falta para citar una fuente, a partir de lo que guarda.
  CitationSource _citationSource(
    String title,
    KnowledgeSourceRow source,
    ReferenceData reference,
  ) => CitationSource(
    title: title,
    reference: reference,
    date: PublicationDate.fromStored(
      source.publishedAt,
      reference.publicationPrecision,
    ),
    url: source.originUrl,
    authorName: source.authorName,
    capturedAt: source.capturedAt,
    kind: source.sourceType,
  );

  @override
  Future<List<BibliographySource>> sourcesMatching(LibraryQuery query) async {
    // El mismo SQL que arma la Biblioteca, sin su orden ni su página: «qué
    // elementos entran» tiene una sola respuesta.
    final sql = LibraryQuerySql(query.copyWith(limit: null, offset: 0)).ids();
    final rows = await _db
        .customSelect(sql.sql, variables: sql.variables)
        .get();
    return sourcesOf([for (final row in rows) row.read<String>('id')]);
  }

  @override
  Future<List<BibliographySource>> sourcesOfSpace(String spaceId) =>
      sourcesMatching(LibraryQuery(spaceId: spaceId));

  @override
  Future<List<BibliographySource>> sourcesOfBranch(String valueId) =>
      sourcesMatching(LibraryQuery(propertyValueIds: {valueId}));

  @override
  Future<List<BibliographySource>> sourcesCitedBy(String noteId) async {
    final relations =
        await (_db.select(_db.relations)..where(
              (r) =>
                  r.fromItemId.equals(noteId) &
                  r.kind.isInValues(const [
                    RelationKind.extractedFrom,
                    RelationKind.cites,
                  ]),
            ))
            .get();
    final links =
        await (_db.select(_db.inlineLinks)..where(
              (l) => l.fromItemId.equals(noteId) & l.toItemId.isNotNull(),
            ))
            .get();
    return sourcesOf({
      for (final relation in relations) relation.toItemId,
      for (final link in links) ?link.toItemId,
    });
  }
}
