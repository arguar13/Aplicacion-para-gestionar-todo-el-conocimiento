import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/health/domain/entities/grown_note.dart';
import 'package:sinapsis/features/health/domain/entities/note_composition.dart';
import 'package:sinapsis/features/health/domain/repositories/health_repository.dart';

/// Cuántos ids entran en un `IN (...)`: SQLite limita las variables de una
/// sentencia, y una semana con miles de notas tocadas no puede romper el
/// panel.
const _chunkSize = 500;

class HealthRepositoryImpl implements HealthRepository {
  const HealthRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  @override
  Stream<NoteComposition> watchNoteComposition() {
    return watchQuery(
      db: _db,
      // `item` también: una nota que va a la papelera deja de contar.
      tables: [_db.knowledgeNotes, _db.knowledgeEntries],
      read: _readComposition,
      telemetry: _telemetry,
      hint: 'HealthRepositoryImpl.watchNoteComposition',
    );
  }

  Future<NoteComposition> _readComposition() async {
    final notes = _db.knowledgeNotes;
    final count = notes.itemId.count();

    final alive = itemIsActive(_db, notes.itemId);

    final kindRows =
        await (_db.selectOnly(notes)
              ..addColumns([notes.noteKind, count])
              ..where(alive)
              ..groupBy([notes.noteKind]))
            .get();
    final maturityRows =
        await (_db.selectOnly(notes)
              ..addColumns([notes.maturity, count])
              ..where(alive)
              ..groupBy([notes.maturity]))
            .get();

    final byKind = {
      for (final kind in NoteKind.values) kind: 0,
      for (final row in kindRows)
        row.readWithConverter(notes.noteKind)!: row.read(count)!,
    };
    final byMaturity = {
      for (final maturity in NoteMaturity.values) maturity: 0,
      for (final row in maturityRows)
        row.readWithConverter(notes.maturity)!: row.read(count)!,
    };
    return NoteComposition(byKind: byKind, byMaturity: byMaturity);
  }

  @override
  Stream<int> watchUnreviewedContradictionCount() {
    return watchQuery(
      db: _db,
      tables: [_db.relations, _db.knowledgeEntries],
      read: () async {
        final relations = _db.relations;
        final count = relations.id.count();
        // Una contradicción con algo que está en la papelera no hay quién la
        // revise.
        final row =
            await (_db.selectOnly(relations)
                  ..addColumns([count])
                  ..where(
                    relations.kind.equalsValue(RelationKind.contradicts) &
                        relations.reviewedAt.isNull() &
                        itemIsActive(_db, relations.fromItemId) &
                        itemIsActive(_db, relations.toItemId),
                  ))
                .getSingle();
        return row.read(count)!;
      },
      telemetry: _telemetry,
      hint: 'HealthRepositoryImpl.watchUnreviewedContradictionCount',
    );
  }

  @override
  Stream<int> watchBrokenLinkCount() {
    return watchQuery(
      db: _db,
      tables: [_db.inlineLinks, _db.knowledgeEntries],
      read: () async {
        final links = _db.inlineLinks;
        final count = links.normalizedTitle.count(distinct: true);
        final row =
            await (_db.selectOnly(links)
                  ..addColumns([count])
                  ..where(
                    links.toItemId.isNull() &
                        itemIsActive(_db, links.fromItemId),
                  ))
                .getSingle();
        return row.read(count)!;
      },
      telemetry: _telemetry,
      hint: 'HealthRepositoryImpl.watchBrokenLinkCount',
    );
  }

  @override
  Stream<List<GrownNote>> watchGrownNotes({
    required DateTime since,
    Set<NoteKind> kinds = const {NoteKind.living},
  }) {
    return watchQuery(
      db: _db,
      tables: [
        _db.knowledgeNotes,
        _db.knowledgeEntries,
        _db.renditions,
        _db.relations,
      ],
      read: () => _readGrownNotes(since, kinds),
      telemetry: _telemetry,
      hint: 'HealthRepositoryImpl.watchGrownNotes',
    );
  }

  Future<List<GrownNote>> _readGrownNotes(
    DateTime since,
    Set<NoteKind> kinds,
  ) async {
    if (kinds.isEmpty) return const [];

    // Las notas candidatas: las del subtipo pedido, con lo que hace falta para
    // mostrarlas.
    final notes = _db.knowledgeNotes;
    final entries = _db.knowledgeEntries;
    final candidateRows = await (_db.select(notes).join([
      innerJoin(entries, entries.id.equalsExp(notes.itemId)),
    ])..where(notes.noteKind.isInValues(kinds) & entries.isActive)).get();
    final candidates = {
      for (final row in candidateRows)
        row.readTable(notes).itemId: (
          title: row.readTable(entries).title,
          maturity: row.readTable(notes).maturity,
        ),
    };
    if (candidates.isEmpty) return const [];

    final newBlocks = await _countNewBlocks(candidates.keys.toSet(), since);
    final newRelations = await _countNewRelations(
      candidates.keys.toSet(),
      since,
    );

    final grown = [
      for (final id in {...newBlocks.keys, ...newRelations.keys})
        GrownNote(
          itemId: id,
          title: candidates[id]!.title,
          maturity: candidates[id]!.maturity,
          newBlocks: newBlocks[id] ?? 0,
          newRelations: newRelations[id] ?? 0,
        ),
    ];
    // Lo que más creció primero; a igual crecimiento, por título sin acentos.
    return grown..sort((a, b) {
      final byGrowth = b.growth.compareTo(a.growth);
      if (byGrowth != 0) return byGrowth;
      return normalizeVocabularyLabel(
        a.title,
      ).compareTo(normalizeVocabularyLabel(b.title));
    });
  }

  /// Cuántos bloques con texto se agregaron desde [since] a cada una de las
  /// notas de [candidateIds]. Solo las que tienen algún bloque nuevo.
  ///
  /// Un bloque agregado desde [since] implica que la nota se guardó desde
  /// entonces: con ese filtro solo se decodifican los bloques de las notas
  /// tocadas esta semana, no los de toda la bóveda. Los bloques sin fecha —los
  /// de antes de que se guardara— no cuentan: no se sabe cuándo nacieron.
  Future<Map<String, int>> _countNewBlocks(
    Set<String> candidateIds,
    DateTime since,
  ) async {
    final items = _db.knowledgeEntries;
    final touched =
        await (_db.selectOnly(items)
              ..addColumns([items.id])
              ..where(
                items.updatedAt.isBiggerOrEqualValue(since) & items.isActive,
              ))
            .get();
    final touchedCandidates = [
      for (final row in touched)
        if (candidateIds.contains(row.read(items.id))) row.read(items.id)!,
    ];

    final counts = <String, int>{};
    for (final ids in _chunks(touchedCandidates)) {
      final renditions =
          await (_db.select(_db.renditions)..where(
                (r) =>
                    r.kind.equalsValue(RenditionKind.blocks) &
                    r.itemId.isIn(ids),
              ))
              .get();
      for (final rendition in renditions) {
        final content = rendition.content;
        if (content == null) continue;
        // Una nota ilegible no se puede contar: la migración y el guardado ya
        // la informan; acá simplemente no aporta.
        final blocks = tryDecodeContentBlocks(content);
        if (blocks == null) continue;

        final added = blocks.where((block) {
          final addedAt = block.addedAt;
          return block.text.trim().isNotEmpty &&
              addedAt != null &&
              !addedAt.isBefore(since);
        }).length;
        if (added > 0) {
          counts.update(
            rendition.itemId,
            (n) => n + added,
            ifAbsent: () => added,
          );
        }
      }
    }
    return counts;
  }

  /// Cuántas relaciones creadas desde [since] tocan a cada una de las notas de
  /// [candidateIds], en cualquiera de los dos sentidos.
  Future<Map<String, int>> _countNewRelations(
    Set<String> candidateIds,
    DateTime since,
  ) async {
    final relations =
        await (_db.select(_db.relations)..where(
              (r) =>
                  r.createdAt.isBiggerOrEqualValue(since) &
                  itemIsActive(_db, r.fromItemId) &
                  itemIsActive(_db, r.toItemId),
            ))
            .get();

    final counts = <String, int>{};
    for (final relation in relations) {
      for (final id in {relation.fromItemId, relation.toItemId}) {
        if (candidateIds.contains(id)) {
          counts.update(id, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    return counts;
  }

  Iterable<List<String>> _chunks(List<String> ids) sync* {
    for (var start = 0; start < ids.length; start += _chunkSize) {
      final end = start + _chunkSize;
      yield ids.sublist(start, end > ids.length ? ids.length : end);
    }
  }
}
