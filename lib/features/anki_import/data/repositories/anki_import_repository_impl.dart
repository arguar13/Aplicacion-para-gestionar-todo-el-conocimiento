import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/repositories/anki_import_repository.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_ids.dart';

/// Cuántos `id` se preguntan por consulta: SQLite acepta 32.766 variables, y
/// una importación de decenas de miles de tarjetas las parte en tandas.
const _chunk = 500;

class AnkiImportRepositoryImpl implements AnkiImportRepository {
  const AnkiImportRepositoryImpl({
    required AppDatabase database,
    required IdGenerator ids,
  }) : _db = database,
       _ids = ids;

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<Set<int>> alreadyImported(List<AnkiImportedCard> cards) async {
    final byDerivedId = <String, List<AnkiImportedCard>>{};
    final byGuid = <String, List<AnkiImportedCard>>{};
    for (final card in cards) {
      (byDerivedId[ankiImportedCardId(card)] ??= []).add(card);
      (byGuid[card.guid] ??= []).add(card);
    }

    final present = <int>{};
    for (final ids in _chunks(byDerivedId.keys)) {
      final rows =
          await (_db.selectOnly(_db.flashcards)
                ..addColumns([_db.flashcards.id])
                ..where(_db.flashcards.id.isIn(ids)))
              .get();
      for (final row in rows) {
        for (final card in byDerivedId[row.read(_db.flashcards.id)]!) {
          present.add(card.ankiCardId);
        }
      }
    }

    // Las que Sinapsis mismo exportó: el `guid` de la nota es el `id` de su
    // tarjeta (en los huecos, el de la primera del grupo).
    for (final guids in _chunks(byGuid.keys)) {
      final own = await (_db.select(
        _db.flashcards,
      )..where((f) => f.id.isIn(guids))).get();
      for (final row in own) {
        final covered = await _clozeNumbersCovered(row);
        for (final card in byGuid[row.id]!) {
          if (card.kind == AnkiCardKind.cloze) {
            if (covered.contains(card.clozeNumber)) {
              present.add(card.ankiCardId);
            }
          } else if (row.kind != FlashcardKind.cloze && card.ord == 0) {
            present.add(card.ankiCardId);
          }
        }
      }
    }
    return present;
  }

  /// Los números de hueco que ya tiene la bóveda del texto de [row]: el suyo y
  /// los de sus hermanas.
  Future<Set<int>> _clozeNumbersCovered(FlashcardRow row) async {
    if (row.kind != FlashcardKind.cloze) return const {};
    final numbers = <int>{?row.clozeIndex};
    final groupId = row.groupId;
    if (groupId != null) {
      final siblings = await (_db.select(
        _db.flashcards,
      )..where((f) => f.groupId.equals(groupId))).get();
      numbers.addAll([for (final sibling in siblings) ?sibling.clozeIndex]);
    }
    return numbers;
  }

  @override
  Future<Map<String, bool>> existingItems(List<String> itemIds) async {
    final found = <String, bool>{};
    for (final ids in _chunks(itemIds)) {
      final rows = await (_db.select(
        _db.knowledgeEntries,
      )..where((e) => e.id.isIn(ids))).get();
      for (final row in rows) {
        found[row.id] = row.deletedAt != null;
      }
    }
    return found;
  }

  @override
  Future<int> insertCards(List<AnkiPlannedCard> cards) async {
    var written = 0;
    for (var start = 0; start < cards.length; start += _chunk) {
      final tanda = cards.sublist(
        start,
        start + _chunk > cards.length ? cards.length : start + _chunk,
      );
      // Una que ya existe se deja como está: lo que la persona repasó no se
      // pisa nunca.
      final existing = {
        for (final row
            in await (_db.selectOnly(_db.flashcards)
                  ..addColumns([_db.flashcards.id])
                  ..where(
                    _db.flashcards.id.isIn([for (final c in tanda) c.id]),
                  ))
                .get())
          row.read(_db.flashcards.id),
      };
      final fresh = [
        for (final card in tanda)
          if (!existing.contains(card.id)) card,
      ];

      await _db.batch((batch) {
        batch
          ..insertAll(_db.flashcards, [
            for (final card in fresh)
              FlashcardsCompanion.insert(
                id: card.id,
                itemId: card.itemId,
                front: card.front,
                // Una de opción múltiple guarda sus respuestas en las opciones.
                back: card.kind == FlashcardKind.multipleChoice
                    ? ''
                    : card.back,
                dueAt: card.dueAt,
                createdAt: card.createdAt,
                kind: Value(card.kind),
                easeFactor: Value(card.easeFactor),
                intervalDays: Value(card.intervalDays),
                repetitions: Value(card.repetitions),
                lastReviewedAt: Value(card.lastReviewedAt),
                suspended: Value(card.suspended),
                buriedUntil: Value(card.buriedUntil),
                learningStep: Value(card.learningStep),
                groupId: Value(card.groupId),
                clozeIndex: Value(card.clozeIndex),
              ),
          ])
          ..insertAll(_db.flashcardOptions, [
            for (final card in fresh)
              if (card.kind == FlashcardKind.multipleChoice)
                for (final (position, content) in [
                  card.back,
                  ...card.choiceDistractors,
                ].indexed)
                  FlashcardOptionsCompanion.insert(
                    id: _ids.next(),
                    flashcardId: card.id,
                    content: content,
                    isCorrect: position == 0,
                    position: position,
                  ),
          ]);
      });
      written += fresh.length;
    }
    return written;
  }
}

Iterable<List<String>> _chunks(Iterable<String> values) sync* {
  final list = values.toList();
  for (var i = 0; i < list.length; i += _chunk) {
    yield list.sublist(i, i + _chunk > list.length ? list.length : i + _chunk);
  }
}
