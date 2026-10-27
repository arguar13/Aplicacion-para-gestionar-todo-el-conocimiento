import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Lo que guarda el repositorio, en memoria, y lo que se le pidió.
class MemoryStudyRepository implements StudyRepository {
  MemoryStudyRepository(this._study);

  DocumentStudy _study;
  final _changes = StreamController<DocumentStudy>.broadcast();
  final added = <String>[];
  final removed = <String>[];
  var _next = 0;

  /// Los textos a los que se les borró lo de la IA con `clearAi`.
  final cleared = <String>[];

  /// Cambia lo guardado, como lo haría un análisis.
  void set(DocumentStudy study) => _set(study);

  void _set(DocumentStudy study) {
    _study = study;
    _changes.add(study);
  }

  @override
  Stream<DocumentStudy> watch(String renditionId) async* {
    yield _study;
    yield* _changes.stream;
  }

  @override
  Future<DocumentStudy> read(String renditionId) async => _study;

  @override
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  }) async {
    added.add(content.substring(start, end));
    _set(
      DocumentStudy(
        marks: [
          ..._study.marks,
          StudyMark(
            id: 'new${_next++}',
            kind: kind,
            origin: ContentOrigin.user,
            start: start,
            end: end,
          ),
        ]..sort((a, b) => a.start.compareTo(b.start)),
        analyzedUntil: _study.analyzedUntil,
        complete: _study.complete,
      ),
    );
    return right(unit);
  }

  /// Las palabras clave que se completaron con `addAiKeywords`.
  final filled = <String>[];

  @override
  Future<Either<Failure, Unit>> addAiKeywords({
    required String renditionId,
    required String content,
    required List<StudyWord> words,
  }) async {
    final have = {
      for (final m in _study.of(StudyMarkKind.keyword)) (m.start, m.end),
    };
    final fresh = [
      for (final word in words)
        if (have.add((word.start, word.end))) word,
    ];
    filled.addAll([for (final w in fresh) content.substring(w.start, w.end)]);
    _set(
      DocumentStudy(
        marks: [
          ..._study.marks,
          for (final word in fresh)
            StudyMark(
              id: 'fill${_next++}',
              kind: StudyMarkKind.keyword,
              origin: ContentOrigin.ai,
              start: word.start,
              end: word.end,
            ),
        ]..sort((a, b) => a.start.compareTo(b.start)),
        analyzedUntil: _study.analyzedUntil,
        complete: _study.complete,
      ),
    );
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> removeMark(String markId) async {
    removed.add(markId);
    _set(
      DocumentStudy(
        marks: [
          for (final mark in _study.marks)
            if (mark.id != markId) mark,
        ],
        analyzedUntil: _study.analyzedUntil,
        complete: _study.complete,
      ),
    );
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> savePart({
    required String renditionId,
    required String content,
    required int partStart,
    required int partEnd,
    required StudyPartMarks marks,
    required bool completes,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> clearAi(String renditionId) async {
    cleared.add(renditionId);
    _set(
      DocumentStudy(
        marks: [
          for (final mark in _study.marks)
            if (mark.origin == ContentOrigin.user) mark,
        ],
        analyzedUntil: 0,
        complete: false,
      ),
    );
    return right(unit);
  }
}
