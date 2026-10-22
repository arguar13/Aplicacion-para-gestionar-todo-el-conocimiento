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

  /// Lo que se borró con `clear`.
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
  Future<Either<Failure, Unit>> addKeyword({
    required String renditionId,
    required String content,
    required StudyWord word,
  }) async {
    added.add(content.substring(word.start, word.end));
    _set(
      DocumentStudy(
        marks: [
          ..._study.marks,
          StudyMark(
            id: 'new${_next++}',
            kind: StudyMarkKind.keyword,
            origin: ContentOrigin.user,
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
  Future<Either<Failure, Unit>> removeKeyword(String markId) async {
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
  Future<Either<Failure, Unit>> clear(String renditionId) async {
    cleared.add(renditionId);
    _set(DocumentStudy.notStarted);
    return right(unit);
  }
}
