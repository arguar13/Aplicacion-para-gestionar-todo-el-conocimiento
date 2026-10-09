import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/cloze_card_editor.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';

class ClozeCardEditorImpl implements ClozeCardEditor {
  const ClozeCardEditorImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Either<Failure, ClozeEditOutcome>> edit({
    required String cardId,
    required String text,
    required String extra,
  }) async {
    final trimmedText = text.trim();
    final trimmedExtra = extra.trim();
    final problems = validateCloze(trimmedText);
    if (problems.isNotEmpty) {
      return left(
        Failure.validation(message: clozeProblemMessage(problems.first)),
      );
    }
    final numbers = parseCloze(trimmedText).numbers;

    try {
      return await _db.transaction(() async {
        final card = await (_db.select(
          _db.flashcards,
        )..where((f) => f.id.equals(cardId))).getSingleOrNull();
        if (card == null) {
          return left<Failure, ClozeEditOutcome>(
            const Failure.unexpected(
              message: 'La tarjeta ya no existe; puede que se haya borrado.',
            ),
          );
        }
        if (card.kind != FlashcardKind.cloze) {
          return left<Failure, ClozeEditOutcome>(
            const Failure.validation(
              message: 'Esa tarjeta no es de huecos para completar.',
            ),
          );
        }

        // Las hermanas de un mismo texto: las del grupo, en el mismo elemento.
        final groupId = card.groupId;
        final siblings = groupId == null
            ? [card]
            : await (_db.select(_db.flashcards)..where(
                    (f) =>
                        f.itemId.equals(card.itemId) &
                        f.groupId.equals(groupId),
                  ))
                  .get();
        final byNumber = {
          for (final sibling in siblings)
            if (sibling.clozeIndex != null) sibling.clozeIndex!: sibling,
        };

        var updated = 0;
        var removed = 0;
        for (final sibling in siblings) {
          final number = sibling.clozeIndex;
          if (number != null && numbers.contains(number)) {
            // Editar es adoptar (F27), y el calendario no se toca.
            await (_db.update(
              _db.flashcards,
            )..where((f) => f.id.equals(sibling.id))).write(
              FlashcardsCompanion(
                front: Value(trimmedText),
                back: Value(trimmedExtra),
                origin: const Value(ContentOrigin.user),
                aiRunId: const Value(null),
              ),
            );
            updated++;
          } else {
            await (_db.delete(
              _db.flashcards,
            )..where((f) => f.id.equals(sibling.id))).go();
            removed++;
          }
        }

        final toCreate = [
          for (final number in numbers)
            if (!byNumber.containsKey(number)) number,
        ];
        // Si el texto pasa a tener varios huecos, todas comparten un grupo: el
        // existente, o uno nuevo que también recibe a la que estaba suelta.
        final survivors = updated + toCreate.length;
        final newGroupId = groupId ?? (survivors > 1 ? _ids.next() : null);
        if (groupId == null && newGroupId != null && updated > 0) {
          await (_db.update(_db.flashcards)..where((f) => f.id.equals(card.id)))
              .write(FlashcardsCompanion(groupId: Value(newGroupId)));
        }

        final now = _clock();
        for (final number in toCreate) {
          await _db
              .into(_db.flashcards)
              .insert(
                FlashcardsCompanion.insert(
                  id: _ids.next(),
                  itemId: card.itemId,
                  front: trimmedText,
                  back: trimmedExtra,
                  dueAt: now,
                  createdAt: now,
                  kind: const Value(FlashcardKind.cloze),
                  sourceChunkId: Value(card.sourceChunkId),
                  sourceCharStart: Value(card.sourceCharStart),
                  sourceCharEnd: Value(card.sourceCharEnd),
                  groupId: Value(newGroupId),
                  clozeIndex: Value(number),
                ),
              );
        }

        return right(
          ClozeEditOutcome(
            updated: updated,
            created: toCreate.length,
            removed: removed,
          ),
        );
      });
      // Un TypeError es Error, no Exception: se atrapa todo, igual que en el
      // resto de los repositorios.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'ClozeCardEditorImpl.edit');
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
