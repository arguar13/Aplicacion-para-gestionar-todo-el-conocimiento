import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// [StudyRepository] sobre la base (`study_marks`, `study_analyses`, v40).
class StudyRepositoryImpl implements StudyRepository {
  StudyRepositoryImpl({
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

  @override
  Stream<DocumentStudy> watch(String renditionId) => watchQuery(
    db: _db,
    tables: [_db.studyMarks, _db.studyAnalyses],
    read: () => read(renditionId),
    telemetry: _telemetry,
    hint: 'StudyRepositoryImpl.watch',
  );

  @override
  Future<DocumentStudy> read(String renditionId) async {
    final analysis = await (_db.select(
      _db.studyAnalyses,
    )..where((a) => a.renditionId.equals(renditionId))).getSingleOrNull();
    final rows =
        await (_db.select(_db.studyMarks)
              ..where((m) => m.renditionId.equals(renditionId))
              ..orderBy([
                (m) => OrderingTerm(expression: m.startOffset),
                (m) => OrderingTerm(expression: m.endOffset),
              ]))
            .get();
    return DocumentStudy(
      marks: [
        for (final row in rows)
          StudyMark(
            id: row.id,
            kind: row.kind,
            origin: row.origin,
            start: row.startOffset,
            end: row.endOffset,
          ),
      ],
      analyzedUntil: analysis?.analyzedUntil ?? 0,
      complete: analysis?.completedAt != null,
    );
  }

  @override
  Future<Either<Failure, Unit>> savePart({
    required String renditionId,
    required String content,
    required int partStart,
    required int partEnd,
    required StudyPartMarks marks,
    required bool completes,
  }) => _guard('savePart', () async {
    if (partStart < 0 || partEnd < partStart || partEnd > content.length) {
      return left(
        Failure.validation(
          message:
              'Parte fuera del texto: $partStart–$partEnd de '
              '${content.length}.',
        ),
      );
    }
    final now = _clock();
    await _db.transaction(() async {
      // Lo que la IA había marcado en esta parte —de un intento anterior que
      // se cortó, o de antes de volver a extraer el texto— se va; lo que eligió
      // la persona, no.
      await (_db.delete(_db.studyMarks)..where(
            (m) =>
                m.renditionId.equals(renditionId) &
                m.origin.equalsValue(ContentOrigin.ai) &
                m.startOffset.isBiggerOrEqualValue(partStart) &
                m.startOffset.isSmallerThanValue(partEnd),
          ))
          .go();

      StudyMarksCompanion row(StudyMarkKind kind, int start, int end) =>
          StudyMarksCompanion.insert(
            id: _ids.next(),
            renditionId: renditionId,
            kind: kind,
            origin: ContentOrigin.ai,
            startOffset: start,
            endOffset: end,
            excerpt: content.substring(start, end),
            createdAt: now,
          );

      // Lo que la persona ya eligió no se repite: una oración o una palabra
      // es una sola marca, venga de quien venga.
      final chosen = {
        for (final m in await _userMarks(renditionId)) (m.kind, m.start, m.end),
      };
      await _db.batch((batch) {
        batch.insertAll(_db.studyMarks, [
          for (final (kind, start, end) in [
            for (final StudySentence(:start, :end) in marks.summary)
              (StudyMarkKind.summary, start, end),
            for (final StudySentence(:start, :end) in marks.synthesis)
              (StudyMarkKind.synthesis, start, end),
            for (final StudyWord(:start, :end) in marks.keywords)
              (StudyMarkKind.keyword, start, end),
          ])
            if (!chosen.contains((kind, start, end))) row(kind, start, end),
        ]);
      });

      await _db
          .into(_db.studyAnalyses)
          .insertOnConflictUpdate(
            StudyAnalysesCompanion.insert(
              renditionId: renditionId,
              analyzedUntil: partEnd,
              completedAt: Value(completes ? now : null),
              updatedAt: now,
            ),
          );
    });
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> addAiKeywords({
    required String renditionId,
    required String content,
    required List<StudyWord> words,
  }) => _guard('addAiKeywords', () async {
    for (final word in words) {
      if (word.start < 0 ||
          word.end > content.length ||
          word.end <= word.start) {
        return left(
          Failure.validation(
            message:
                'Palabra fuera del texto: ${word.start}–${word.end} de '
                '${content.length}.',
          ),
        );
      }
    }
    final now = _clock();
    await _db.transaction(() async {
      final existing = {
        for (final m in (await read(renditionId)).of(StudyMarkKind.keyword))
          (m.start, m.end),
      };
      await _db.batch((batch) {
        batch.insertAll(_db.studyMarks, [
          for (final word in words)
            if (existing.add((word.start, word.end)))
              StudyMarksCompanion.insert(
                id: _ids.next(),
                renditionId: renditionId,
                kind: StudyMarkKind.keyword,
                origin: ContentOrigin.ai,
                startOffset: word.start,
                endOffset: word.end,
                excerpt: content.substring(word.start, word.end),
                createdAt: now,
              ),
        ]);
      });
    });
    return right(unit);
  });

  Future<List<StudyMark>> _userMarks(String renditionId) async {
    final study = await read(renditionId);
    return [
      for (final mark in study.marks)
        if (mark.origin == ContentOrigin.user) mark,
    ];
  }

  @override
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  }) => _guard('addUserMark', () async {
    if (start < 0 || end > content.length || end <= start) {
      return left(
        Failure.validation(
          message: 'Marca fuera del texto: $start–$end de ${content.length}.',
        ),
      );
    }
    await _db.transaction(() async {
      final same =
          await (_db.select(_db.studyMarks)..where(
                (m) =>
                    m.renditionId.equals(renditionId) &
                    m.kind.equalsValue(kind) &
                    m.startOffset.equals(start) &
                    m.endOffset.equals(end),
              ))
              .get();
      if (same.isNotEmpty) return;
      await _db
          .into(_db.studyMarks)
          .insert(
            StudyMarksCompanion.insert(
              id: _ids.next(),
              renditionId: renditionId,
              kind: kind,
              origin: ContentOrigin.user,
              startOffset: start,
              endOffset: end,
              excerpt: content.substring(start, end),
              createdAt: _clock(),
            ),
          );
    });
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> removeMark(String markId) =>
      _guard('removeMark', () async {
        await (_db.delete(
          _db.studyMarks,
        )..where((m) => m.id.equals(markId))).go();
        return right(unit);
      });

  @override
  Future<Either<Failure, Unit>> clearAi(String renditionId) =>
      _guard('clearAi', () async {
        await _db.transaction(() async {
          await (_db.delete(_db.studyMarks)..where(
                (m) =>
                    m.renditionId.equals(renditionId) &
                    m.origin.equalsValue(ContentOrigin.ai),
              ))
              .go();
          await (_db.delete(
            _db.studyAnalyses,
          )..where((a) => a.renditionId.equals(renditionId))).go();
        });
        return right(unit);
      });

  Future<Either<Failure, T>> _guard<T>(
    String name,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Un TypeError de una fila rara es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'StudyRepositoryImpl.$name');
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
