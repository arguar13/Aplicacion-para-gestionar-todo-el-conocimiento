import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_fuzzy_index.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_fuzzy_match_repository.dart';

/// [ReferenceFuzzyMatchRepository] sobre la base.
///
/// Tres consultas —títulos con su año, el primer autor de cada obra, y el
/// nombre de esos autores—, nunca una por fuente: se resuelve en Dart cuál
/// es el «primer» autor (el de menor `position` con rol autor) porque
/// SQLite no tiene una forma directa de pedir «el mínimo de cada grupo»
/// sin una subconsulta correlacionada por fila, y acá conviene más una
/// pasada en memoria sobre una tabla que no crece con el texto de nadie.
class ReferenceFuzzyMatchRepositoryImpl
    implements ReferenceFuzzyMatchRepository {
  ReferenceFuzzyMatchRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ReferenceFuzzyIndex> buildIndex() async {
    final entries = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    final contributors = _db.sourceContributors;
    final values = _db.propertyValues;

    final titleYear = <String, ({String title, int? year})>{};
    final titleRows = await (_db.select(entries).join([
      innerJoin(sources, sources.itemId.equalsExp(entries.id)),
    ])..where(entries.isActive)).get();
    for (final row in titleRows) {
      final entry = row.readTable(entries);
      final source = row.readTable(sources);
      if (entry.title.trim().isEmpty) continue;
      titleYear[entry.id] = (
        title: entry.title,
        year: source.publishedAt?.year,
      );
    }

    final firstAuthorId = <String, String>{};
    final bestPosition = <String, int>{};
    final authorRows =
        await (_db.select(contributors).join([
              innerJoin(entries, entries.id.equalsExp(contributors.itemId)),
            ])..where(
              entries.isActive &
                  contributors.role.equalsValue(ContributorRole.author),
            ))
            .get();
    for (final row in authorRows) {
      final contributor = row.readTable(contributors);
      final current = bestPosition[contributor.itemId];
      if (current == null || contributor.position < current) {
        bestPosition[contributor.itemId] = contributor.position;
        firstAuthorId[contributor.itemId] = contributor.propertyValueId;
      }
    }

    final familyByValueId = <String, String>{};
    final neededIds = firstAuthorId.values.toSet();
    if (neededIds.isNotEmpty) {
      final valueRows = await (_db.select(
        values,
      )..where((v) => v.id.isIn(neededIds))).get();
      for (final value in valueRows) {
        final family = value.nameFamily;
        if (family != null && family.trim().isNotEmpty) {
          familyByValueId[value.id] = normalizeVocabularyLabel(family);
        }
      }
    }

    final byTitle = <String, List<ReferenceFuzzyCandidate>>{};
    for (final entry in titleYear.entries) {
      final key = normalizeVocabularyLabel(entry.value.title);
      if (key.isEmpty) continue;
      final authorValueId = firstAuthorId[entry.key];
      byTitle
          .putIfAbsent(key, () => [])
          .add(
            ReferenceFuzzyCandidate(
              itemId: entry.key,
              title: entry.value.title,
              year: entry.value.year,
              firstAuthorFamily: authorValueId == null
                  ? null
                  : familyByValueId[authorValueId],
            ),
          );
    }

    return ReferenceFuzzyIndex(byTitle);
  }
}
