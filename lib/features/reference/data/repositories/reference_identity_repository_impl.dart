import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_identity_index.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_identity_repository.dart';

/// [ReferenceIdentityRepository] sobre la base.
///
/// Dos consultas —una por `doi`/`isbn` (con sus índices en `source_
/// reference`), otra por `origin_url`—, nunca una por fuente: el DOI y el
/// ISBN no necesitan normalizarse de nuevo porque ya se guardan
/// normalizados (D3); la URL sí, porque `origin_url` guarda el enlace tal
/// como se capturó.
class ReferenceIdentityRepositoryImpl implements ReferenceIdentityRepository {
  ReferenceIdentityRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ReferenceIdentityIndex> buildIndex() async {
    final entries = _db.knowledgeEntries;
    final references = _db.sourceReferences;
    final sources = _db.knowledgeSources;

    final byDoi = <String, String>{};
    final byIsbn = <String, String>{};
    final refRows =
        await (_db.select(references).join([
              innerJoin(entries, entries.id.equalsExp(references.itemId)),
            ])..where(
              entries.isActive &
                  (references.doi.isNotNull() | references.isbn.isNotNull()),
            ))
            .get();
    for (final row in refRows) {
      final reference = row.readTable(references);
      final doi = reference.doi;
      if (doi != null) byDoi[doi] = reference.itemId;
      final isbn = reference.isbn;
      if (isbn != null) byIsbn[isbn] = reference.itemId;
    }

    final byUrl = <String, String>{};
    final urlRows = await (_db.select(sources).join([
      innerJoin(entries, entries.id.equalsExp(sources.itemId)),
    ])..where(entries.isActive & sources.originUrl.isNotNull())).get();
    for (final row in urlRows) {
      final source = row.readTable(sources);
      final canonical = canonicalUrl(source.originUrl!);
      if (canonical != null) byUrl[canonical] = source.itemId;
    }

    return ReferenceIdentityIndex(byDoi: byDoi, byIsbn: byIsbn, byUrl: byUrl);
  }
}
