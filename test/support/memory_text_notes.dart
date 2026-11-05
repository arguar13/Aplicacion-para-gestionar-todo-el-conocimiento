import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/repositories/text_note_repository.dart';

/// Las notas en el texto (F45, paso 8b) en memoria, para las pruebas de una
/// pantalla sin base: guarda lo que se pone y lo muestra al día, en el orden
/// del texto. Lo que [created] dice es lo que se puso, en orden.
class MemoryTextNotes implements TextNoteRepository {
  final _notes = <TextNote>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  /// Lo que se puso, en el orden en que se puso.
  List<TextNote> get created => List.unmodifiable(_notes);

  List<TextNote> _of(TextNoteTarget target) => [
    for (final note in _notes)
      if (note.target == target) note,
  ]..sort(compareInTextOrder);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  TextNote _make(
    TextNoteTarget target, {
    required String excerpt,
    required String note,
    required HighlightColor color,
    int? start,
    int? end,
  }) {
    final at = DateTime(2026, 11, 5, 12, _next);
    return TextNote(
      id: 'nota-${_next++}',
      origin: TextNoteOrigin.note,
      target: target,
      start: start,
      end: end,
      excerpt: excerpt,
      note: note.trim(),
      color: color,
      renditionId: target.renditionId,
      createdAt: at,
      updatedAt: at,
    );
  }

  Either<Failure, TextNote> _add(TextNote note) {
    if (note.note.isEmpty) {
      return left(const Failure.validation(message: 'En blanco.'));
    }
    _notes.add(note);
    _changes.add(null);
    return right(note);
  }

  @override
  Stream<List<TextNote>> watchNotes(TextNoteTarget target) =>
      _watch(() => _of(target));

  @override
  Stream<int> watchCount(TextNoteTarget target) =>
      _watch(() => _of(target).length);

  @override
  Future<Either<Failure, TextNote>> create({
    required TextNoteTarget target,
    required int start,
    required int end,
    required String excerpt,
    required String note,
    required HighlightColor color,
  }) async => _add(
    _make(
      target,
      start: start,
      end: end,
      excerpt: excerpt,
      note: note,
      color: color,
    ),
  );

  @override
  Future<Either<Failure, TextNote>> createOnWholeText({
    required TextNoteTarget target,
    required String note,
    required HighlightColor color,
  }) async => _add(_make(target, excerpt: '', note: note, color: color));

  @override
  Future<Either<Failure, TextNote>> edit(TextNote note, String text) async =>
      _replace(note, note.copyWith(note: text.trim()));

  @override
  Future<Either<Failure, TextNote>> recolor(
    TextNote note,
    HighlightColor color,
  ) async => _replace(note, note.copyWith(color: color));

  @override
  Future<Either<Failure, TextNote>> delete(TextNote note) async {
    final removed = _notes.remove(note);
    if (!removed) {
      return left(const Failure.unexpected(message: 'Ya no está.'));
    }
    _changes.add(null);
    return right(note);
  }

  @override
  Future<Either<Failure, Unit>> restore(TextNote note) async {
    _notes.add(note);
    _changes.add(null);
    return right(unit);
  }

  Either<Failure, TextNote> _replace(TextNote old, TextNote updated) {
    final index = _notes.indexWhere((n) => n.id == old.id);
    if (index < 0) {
      return left(const Failure.unexpected(message: 'Ya no está.'));
    }
    _notes[index] = updated;
    _changes.add(null);
    return right(updated);
  }
}
