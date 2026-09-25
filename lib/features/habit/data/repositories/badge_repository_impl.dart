import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/habit/data/services/habit_activity_days.dart';
import 'package:sinapsis/features/habit/domain/entities/badge_kind.dart';
import 'package:sinapsis/features/habit/domain/repositories/badge_repository.dart';
import 'package:sinapsis/features/habit/domain/services/complete_topic_branch.dart';
import 'package:sinapsis/features/habit/domain/services/month_of_weekly_consolidation.dart';

/// [BadgeRepository] sobre la base (F17, D7).
///
/// «Una contradicción resuelta» reusa `relations.reviewedAt` —F9, la
/// pantalla de Tensión, «cuándo se marcó como revisada»—, ya pensado
/// exactamente para distinguir esto de un vínculo que desaparece por
/// cualquier otro motivo: no hace falta inventar nada nuevo.
///
/// «Un tema completo de punta a punta» es la única insignia cara: junta el
/// árbol de Temas, a qué fuentes activas está asignado cada valor, y qué
/// fuentes cubre alguna nota viva madura, en unas pocas consultas por
/// lotes —nunca una por rama, que con miles de valores posibles sería
/// prohibitivo—, y deja el recorrido del árbol a [hasCompleteTopicBranch],
/// puro.
class BadgeRepositoryImpl implements BadgeRepository {
  const BadgeRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;

  @override
  Future<Set<BadgeKind>> earned() async {
    return {
      if (await _hasFirstMatureNote()) BadgeKind.firstMatureNote,
      if (await _hasTenLivingNotes()) BadgeKind.tenLivingNotes,
      if (await _hasHundredReviews()) BadgeKind.hundredReviews,
      if (await _hasContradictionResolved()) BadgeKind.contradictionResolved,
      if (await _hasCompleteTopicBranchNow()) BadgeKind.completeTopicBranch,
      if (await _hasMonthOfWeeklyConsolidationNow())
        BadgeKind.monthOfWeeklyConsolidation,
    };
  }

  @override
  Stream<Set<BadgeKind>> watch() {
    return watchQuery(
      db: _db,
      tables: [
        _db.knowledgeNotes,
        _db.knowledgeEntries,
        _db.reviewLogs,
        _db.relations,
        _db.propertyValues,
        _db.itemPropertyValues,
        _db.inlineLinks,
        _db.fieldVersions,
        _db.habitEvents,
      ],
      read: earned,
      telemetry: _telemetry,
      hint: 'BadgeRepositoryImpl.watch',
    );
  }

  Future<bool> _hasFirstMatureNote() async {
    final notes = _db.knowledgeNotes;
    final entries = _db.knowledgeEntries;
    final row =
        await (_db.select(notes).join([
                innerJoin(entries, entries.id.equalsExp(notes.itemId)),
              ])
              ..where(
                notes.maturity.equalsValue(NoteMaturity.mature) &
                    itemIsActive(_db, entries.id),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<bool> _hasTenLivingNotes() async {
    final notes = _db.knowledgeNotes;
    final entries = _db.knowledgeEntries;
    final count = notes.itemId.count();
    final row =
        await (_db.selectOnly(notes)
              ..addColumns([count])
              ..join([innerJoin(entries, entries.id.equalsExp(notes.itemId))])
              ..where(
                notes.noteKind.equalsValue(NoteKind.living) &
                    itemIsActive(_db, entries.id),
              ))
            .getSingle();
    return (row.read(count) ?? 0) >= 10;
  }

  Future<bool> _hasHundredReviews() async {
    final logs = _db.reviewLogs;
    final count = logs.id.count();
    final row = await (_db.selectOnly(logs)..addColumns([count])).getSingle();
    return (row.read(count) ?? 0) >= 100;
  }

  Future<bool> _hasContradictionResolved() async {
    final relations = _db.relations;
    final row =
        await (_db.select(relations)
              ..where(
                (r) =>
                    r.kind.equalsValue(RelationKind.contradicts) &
                    r.reviewedAt.isNotNull() &
                    itemIsActive(_db, r.fromItemId) &
                    itemIsActive(_db, r.toItemId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<bool> _hasCompleteTopicBranchNow() async {
    final definitionId = await temaDefinitionId(_db);
    final values = _db.propertyValues;
    final valueRows =
        await (_db.selectOnly(values)
              ..addColumns([values.id, values.parentId])
              ..where(values.definitionId.equals(definitionId)))
            .get();
    final tree = VocabularyTree([
      for (final row in valueRows)
        (id: row.read(values.id)!, parentId: row.read(values.parentId)),
    ]);

    final sourcesByTema = await _sourcesByTema(definitionId);
    if (sourcesByTema.isEmpty) return false;
    final coveredSourceIds = await _sourcesCoveredByMatureLivingNotes();

    return hasCompleteTopicBranch(
      temaTree: tree,
      sourcesByTema: sourcesByTema,
      coveredSourceIds: coveredSourceIds,
    );
  }

  /// Cada fuente ACTIVA asignada a un valor de Tema, agrupada por ese
  /// valor —una sola consulta por lotes, no una por rama—.
  Future<Map<String, Set<String>>> _sourcesByTema(String definitionId) async {
    final assignments = _db.itemPropertyValues;
    final values = _db.propertyValues;
    final entries = _db.knowledgeEntries;
    final rows =
        await (_db.select(assignments).join([
              innerJoin(
                values,
                values.id.equalsExp(assignments.propertyValueId),
              ),
              innerJoin(entries, entries.id.equalsExp(assignments.itemId)),
            ])..where(
              values.definitionId.equals(definitionId) &
                  entries.kind.equalsValue(ItemKind.source) &
                  itemIsActive(_db, entries.id),
            ))
            .get();

    final result = <String, Set<String>>{};
    for (final row in rows) {
      final assignment = row.readTable(assignments);
      (result[assignment.propertyValueId] ??= {}).add(assignment.itemId);
    }
    return result;
  }

  /// Las fuentes que alguna nota viva madura y activa cita —mismos dos
  /// caminos que `BibliographyRepository.sourcesCitedBy` (F15): una
  /// relación `extractedFrom`/`cites`, o un enlace en línea—, para todas
  /// las notas maduras de una vez.
  Future<Set<String>> _sourcesCoveredByMatureLivingNotes() async {
    final notes = _db.knowledgeNotes;
    final entries = _db.knowledgeEntries;
    final noteRows =
        await (_db.select(notes).join([
              innerJoin(entries, entries.id.equalsExp(notes.itemId)),
            ])..where(
              notes.noteKind.equalsValue(NoteKind.living) &
                  notes.maturity.equalsValue(NoteMaturity.mature) &
                  itemIsActive(_db, entries.id),
            ))
            .get();
    final matureNoteIds = {
      for (final row in noteRows) row.readTable(notes).itemId,
    };
    if (matureNoteIds.isEmpty) return const {};

    final relations = _db.relations;
    final relationRows =
        await (_db.select(relations)..where(
              (r) =>
                  r.fromItemId.isIn(matureNoteIds) &
                  r.kind.isInValues(const [
                    RelationKind.extractedFrom,
                    RelationKind.cites,
                  ]),
            ))
            .get();
    final links = _db.inlineLinks;
    final linkRows =
        await (_db.select(links)..where(
              (l) => l.fromItemId.isIn(matureNoteIds) & l.toItemId.isNotNull(),
            ))
            .get();

    return {
      for (final relation in relationRows) relation.toItemId,
      for (final link in linkRows) ?link.toItemId,
    };
  }

  Future<bool> _hasMonthOfWeeklyConsolidationNow() async {
    final activeDays = await HabitActivityDays(_db).all();
    return hasMonthOfWeeklyConsolidation(activeDays, today: _clock());
  }
}
