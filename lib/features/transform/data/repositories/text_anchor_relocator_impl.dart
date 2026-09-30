import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/util/text_anchor_locator.dart';
import 'package:sinapsis/features/transform/domain/repositories/text_anchor_relocator.dart';
import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

/// [TextAnchorRelocator] sobre la base (F22).
///
/// Escribe directo en `highlights`, `flashcards`, `flashcard_options` y
/// `relations`: no hay otra forma de mover una posición, y es un ajuste del
/// mismo dato —dónde está ese fragmento—, no una edición del usuario.
class TextAnchorRelocatorImpl implements TextAnchorRelocator {
  const TextAnchorRelocatorImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<LostHighlight>> relocate({
    required String itemId,
    required String renditionId,
    required String from,
    required String to,
  }) async {
    ({int start, int end})? find(String excerpt, int oldStart) => locateExcerpt(
      to,
      excerpt,
      near: from.isEmpty ? 0 : oldStart * to.length ~/ from.length,
    );

    // El fragmento que marcaba una posición del texto viejo, si la posición
    // todavía tiene sentido en él.
    String? excerptAt(int? start, int? end) =>
        start == null || end == null || start < 0 || end > from.length
        ? null
        : from.substring(start, end);

    final lost = <LostHighlight>[];
    final highlights = await (_db.select(
      _db.highlights,
    )..where((h) => h.renditionId.equals(renditionId))).get();
    for (final highlight in highlights) {
      final range = find(highlight.excerpt, highlight.startOffset);
      if (range == null) {
        lost.add((excerpt: highlight.excerpt, note: highlight.note));
        await (_db.delete(
          _db.highlights,
        )..where((h) => h.id.equals(highlight.id))).go();
        continue;
      }
      await (_db.update(
        _db.highlights,
      )..where((h) => h.id.equals(highlight.id))).write(
        HighlightsCompanion(
          startOffset: Value(range.start),
          endOffset: Value(range.end),
        ),
      );
    }

    final cards =
        await (_db.select(_db.flashcards)..where(
              (c) => c.itemId.equals(itemId) & c.sourceCharStart.isNotNull(),
            ))
            .get();
    for (final card in cards) {
      final range = _relocated(
        excerptAt(card.sourceCharStart, card.sourceCharEnd),
        card.sourceCharStart!,
        find,
      );
      await (_db.update(
        _db.flashcards,
      )..where((c) => c.id.equals(card.id))).write(
        FlashcardsCompanion(
          sourceCharStart: Value(range?.start),
          sourceCharEnd: Value(range?.end),
          sourceChunkId: Value(await _chunkAt(itemId, range?.start)),
        ),
      );
    }

    final options =
        await (_db.select(_db.flashcardOptions)..where(
              (o) =>
                  o.sourceItemId.equals(itemId) & o.sourceCharStart.isNotNull(),
            ))
            .get();
    for (final option in options) {
      final range = _relocated(
        excerptAt(option.sourceCharStart, option.sourceCharEnd),
        option.sourceCharStart!,
        find,
      );
      await (_db.update(
        _db.flashcardOptions,
      )..where((o) => o.id.equals(option.id))).write(
        FlashcardOptionsCompanion(
          sourceCharStart: Value(range?.start),
          sourceCharEnd: Value(range?.end),
          sourceChunkId: Value(await _chunkAt(itemId, range?.start)),
        ),
      );
    }

    final extracts =
        await (_db.select(_db.relations)..where(
              (r) =>
                  r.toItemId.equals(itemId) &
                  r.kind.equalsValue(RelationKind.extractedFrom) &
                  r.sourceCharStart.isNotNull(),
            ))
            .get();
    for (final extract in extracts) {
      final range = _relocated(
        excerptAt(extract.sourceCharStart, extract.sourceCharEnd),
        extract.sourceCharStart!,
        find,
      );
      await (_db.update(
        _db.relations,
      )..where((r) => r.id.equals(extract.id))).write(
        RelationsCompanion(
          sourceCharStart: Value(range?.start),
          sourceCharEnd: Value(range?.end),
        ),
      );
    }

    return lost;
  }

  ({int start, int end})? _relocated(
    String? excerpt,
    int oldStart,
    ({int start, int end})? Function(String excerpt, int oldStart) find,
  ) => excerpt == null || excerpt.trim().isEmpty
      ? null
      : find(excerpt, oldStart);

  /// El chunk de [itemId] que contiene la posición [offset] del texto: los
  /// chunks se rehicieron con el texto nuevo, y los de antes ya no existen.
  Future<String?> _chunkAt(String itemId, int? offset) async {
    if (offset == null) return null;
    final chunk =
        await (_db.select(_db.chunks)
              ..where(
                (c) =>
                    c.itemId.equals(itemId) &
                    c.charStart.isSmallerOrEqualValue(offset) &
                    c.charEnd.isBiggerThanValue(offset),
              )
              ..limit(1))
            .getSingleOrNull();
    return chunk?.id;
  }
}
