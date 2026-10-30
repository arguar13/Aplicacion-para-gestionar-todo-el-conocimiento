import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/repositories/text_note_repository.dart';

/// [TextNoteRepository] sobre `text_notes` (F45, mejora 19, v49) y, para las
/// notas de antes, sobre `highlights` (F38).
///
/// Escribe en `highlights` solo la nota y el color de un resaltado que ya
/// tenía nota: es la misma nota, que se lee por acá (decisión I). Lo demás del
/// resaltado —su lugar, su estilo, si existe— es de quien resalta.
class TextNoteRepositoryImpl implements TextNoteRepository {
  TextNoteRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  $TextNotesTable get _table => _db.textNotes;

  // --- Leer ---------------------------------------------------------------

  // Se miran las notas y los resaltados, no las formas: una forma que se va
  // se lleva sus resaltados, y eso ya avisa.

  @override
  Stream<List<TextNote>> watchNotes(TextNoteTarget target) => watchQuery(
    db: _db,
    tables: [_table, _db.highlights],
    read: () => _notesOf(target),
    telemetry: _telemetry,
    hint: 'TextNoteRepositoryImpl.watchNotes',
  );

  @override
  Stream<int> watchCount(TextNoteTarget target) => watchQuery(
    db: _db,
    tables: [_table, _db.highlights],
    read: () => _countOf(target),
    telemetry: _telemetry,
    hint: 'TextNoteRepositoryImpl.watchCount',
  );

  Future<List<TextNote>> _notesOf(TextNoteTarget target) async {
    final rows = await (_db.select(_table)..where(_of(target))).get();
    return [
      for (final row in rows) _toEntity(row, target),
      for (final row in await _highlightNotesOf(target))
        _fromHighlight(row, target),
    ]..sort(compareInTextOrder);
  }

  Future<int> _countOf(TextNoteTarget target) async {
    final count = _table.id.count();
    final own =
        await (_db.selectOnly(_table)
              ..addColumns([count])
              ..where(_of(target)(_table)))
            .map((row) => row.read(count)!)
            .getSingle();
    final legacy = switch (target) {
      SourceOriginalNotes(:final sourceId) =>
        (await _db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM highlights h '
                  'JOIN renditions r ON r.id = h.rendition_id '
                  'WHERE r.item_id = ? AND $_highlightHasNote',
                  variables: [Variable.withString(sourceId)],
                  readsFrom: {_db.highlights, _db.renditions},
                )
                .getSingle())
            .read<int>('n'),
      _ => 0,
    };
    return own + legacy;
  }

  /// Las filas de [target]: por su dueño y su clase. Del original de la
  /// Biblioteca, todas las de la fuente, sobre cualquiera de sus formas: la
  /// que el texto que se muestra no es queda sin lugar al ubicarla, nunca
  /// afuera.
  Expression<bool> Function($TextNotesTable) _of(TextNoteTarget target) =>
      (n) => switch (target) {
        CreationNotes(:final id) =>
          n.target.equals(kCreationNotes) & n.creationId.equals(id),
        _ =>
          n.target.equals(target.storageKey) & n.itemId.equals(target.itemId!),
      };

  /// Los resaltados de antes con nota (F38): solo en el original de la
  /// Biblioteca, que es donde se resalta —la copia de Procesado es de solo
  /// lectura, y un resaltado no cae ni en el texto procesado ni en lo
  /// creado—.
  Future<List<HighlightRow>> _highlightNotesOf(TextNoteTarget target) async {
    if (target is! SourceOriginalNotes) return const [];
    return _db
        .customSelect(
          'SELECT h.* FROM highlights h '
          'JOIN renditions r ON r.id = h.rendition_id '
          'WHERE r.item_id = ? AND $_highlightHasNote',
          variables: [Variable.withString(target.sourceId)],
          readsFrom: {_db.highlights, _db.renditions},
        )
        .asyncMap(_db.highlights.mapFromRow)
        .get();
  }

  // --- Escribir -----------------------------------------------------------

  @override
  Future<Either<Failure, TextNote>> create({
    required TextNoteTarget target,
    required int start,
    required int end,
    required String excerpt,
    required String note,
    required HighlightColor color,
  }) => _guard('create', () async {
    final text = note.trim();
    if (start < 0 || end <= start || excerpt.isEmpty) {
      return left(
        const Failure.validation(message: 'El pedazo elegido no es válido.'),
      );
    }
    if (text.isEmpty) return left(_blank);
    final now = _clock();
    final created = TextNote(
      id: _ids.next(),
      origin: TextNoteOrigin.note,
      target: target,
      start: start,
      end: end,
      excerpt: excerpt,
      note: text,
      color: color,
      renditionId: target.renditionId,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_table).insert(_companionOf(created));
    return right(created);
  });

  @override
  Future<Either<Failure, TextNote>> edit(TextNote note, String text) => _guard(
    'edit',
    () async {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return left(_blank);
      if (trimmed == note.note) return right(note);
      final now = _clock();
      final written = switch (note.origin) {
        TextNoteOrigin.note =>
          await (_db.update(_table)..where((n) => n.id.equals(note.id))).write(
            TextNotesCompanion(note: Value(trimmed), updatedAt: Value(now)),
          ),
        TextNoteOrigin.highlight =>
          await (_db.update(_db.highlights)..where((h) => h.id.equals(note.id)))
              .write(HighlightsCompanion(note: Value(trimmed))),
      };
      if (written == 0) return left(_missing);
      return right(
        note.copyWith(
          note: trimmed,
          updatedAt: note.origin == TextNoteOrigin.note ? now : null,
        ),
      );
    },
  );

  @override
  Future<Either<Failure, TextNote>> recolor(
    TextNote note,
    HighlightColor color,
  ) => _guard('recolor', () async {
    if (color == note.color) return right(note);
    final now = _clock();
    final written = switch (note.origin) {
      TextNoteOrigin.note =>
        await (_db.update(_table)..where((n) => n.id.equals(note.id))).write(
          TextNotesCompanion(color: Value(color), updatedAt: Value(now)),
        ),
      // El de un resaltado es el del resaltado: cambia los dos, como en la
      // tarjeta del resaltado (F38).
      TextNoteOrigin.highlight =>
        await (_db.update(_db.highlights)..where((h) => h.id.equals(note.id)))
            .write(HighlightsCompanion(color: Value(color))),
    };
    if (written == 0) return left(_missing);
    return right(
      note.copyWith(
        color: color,
        updatedAt: note.origin == TextNoteOrigin.note ? now : null,
      ),
    );
  });

  @override
  Future<Either<Failure, TextNote>> delete(TextNote note) =>
      _guard('delete', () async {
        final removed = switch (note.origin) {
          TextNoteOrigin.note => await (_db.delete(
            _table,
          )..where((n) => n.id.equals(note.id))).go(),
          // El resaltado queda: lo que se borra es su nota.
          TextNoteOrigin.highlight =>
            await (_db.update(_db.highlights)
                  ..where((h) => h.id.equals(note.id)))
                .write(const HighlightsCompanion(note: Value(null))),
        };
        if (removed == 0) return left(_missing);
        return right(note);
      });

  @override
  Future<Either<Failure, Unit>> restore(TextNote note) =>
      _guard('restore', () async {
        switch (note.origin) {
          case TextNoteOrigin.note:
            if (!await _ownerExists(note.target)) {
              return left(
                const Failure.validation(
                  message: 'El texto de esta nota ya no está.',
                ),
              );
            }
            await _db
                .into(_table)
                .insert(_companionOf(note), mode: InsertMode.insertOrReplace);
          case TextNoteOrigin.highlight:
            final written =
                await (_db.update(
                  _db.highlights,
                )..where((h) => h.id.equals(note.id))).write(
                  HighlightsCompanion(
                    note: Value(note.note),
                    color: Value(note.color),
                  ),
                );
            if (written == 0) return left(_missing);
        }
        return right(unit);
      });

  /// Si el dueño de una nota de [target] sigue en la base —vivo o en la
  /// papelera—.
  Future<bool> _ownerExists(TextNoteTarget target) async {
    final row = switch (target) {
      CreationNotes(:final id) => await (_db.select(
        _db.studyCreations,
      )..where((c) => c.id.equals(id))).getSingleOrNull(),
      _ => await (_db.select(
        _db.knowledgeEntries,
      )..where((i) => i.id.equals(target.itemId!))).getSingleOrNull(),
    };
    return row != null;
  }

  // --- Filas --------------------------------------------------------------

  TextNotesCompanion _companionOf(TextNote note) => TextNotesCompanion.insert(
    id: note.id,
    target: note.target.storageKey,
    itemId: Value(note.target.itemId),
    renditionId: Value(note.renditionId),
    creationId: Value(note.target.creationId),
    startOffset: Value(note.start),
    endOffset: Value(note.end),
    excerpt: note.excerpt,
    note: note.note,
    color: note.color ?? HighlightColor.values.first,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
  );

  TextNote _toEntity(TextNoteRow row, TextNoteTarget target) => TextNote(
    id: row.id,
    origin: TextNoteOrigin.note,
    target: target,
    start: row.startOffset,
    end: row.endOffset,
    excerpt: row.excerpt,
    note: row.note,
    color: row.color,
    renditionId: row.renditionId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  TextNote _fromHighlight(HighlightRow row, TextNoteTarget target) => TextNote(
    id: row.id,
    origin: TextNoteOrigin.highlight,
    target: target,
    start: row.startOffset,
    end: row.endOffset,
    excerpt: row.excerpt,
    note: row.note!.trim(),
    color: row.color,
    renditionId: row.renditionId,
    createdAt: row.createdAt,
    updatedAt: row.createdAt,
  );

  static const _highlightHasNote = "h.note IS NOT NULL AND trim(h.note) <> ''";

  static const _blank = Failure.validation(
    message: 'Una nota en blanco no se guarda: para sacarla, borrala.',
  );

  static const _missing = Failure.unexpected(
    message: 'La nota ya no existe; puede que se haya borrado.',
  );

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
        hint: 'TextNoteRepositoryImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
