import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/services/study_marker.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';

import '../../../../support/item_rows.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Un modelo grabado: por cada parte que se le pide, la respuesta que toque
/// —la de `reply`, si se da—, leída con el mismo `parseStudyReply` de la app.
class _RecordedMarker implements StudyMarker {
  _RecordedMarker({
    required this.partCharBudget,
    String Function(List<StudySentence> part)? reply,
    this.fits,
  }) : _reply = reply ?? ((part) => 'RESUMEN: 1\nSINTESIS: 1');

  @override
  final int partCharBudget;

  final String Function(List<StudySentence> part) _reply;

  /// Cuántas oraciones de una parte entran en la ventana, como mucho.
  final int? fits;

  final parts = <List<StudySentence>>[];

  /// Si la próxima llamada falla, como sin conexión.
  Error? failNext;

  @override
  Future<StudyPartOutcome> markPart({
    required String content,
    required List<StudySentence> part,
  }) async {
    if (failNext case final error?) {
      failNext = null;
      throw error;
    }
    final fitted = fits == null || part.length <= fits!
        ? part
        : part.sublist(0, fits);
    parts.add(fitted);
    return StudyPartOutcome(
      analyzed: fitted.length,
      marks: parseStudyReply(_reply(fitted), content: content, part: fitted),
    );
  }
}

/// Analizar un documento por partes, en orden y retomable (F36), contra la
/// base real y un modelo grabado.
void main() {
  late AppDatabase db;
  late StudyRepositoryImpl repository;
  final now = DateTime(2026, 10, 22, 10);

  // Diez oraciones de 20 caracteres: con un presupuesto de 164 entran dos por
  // parte (20 + 62 de número y de su línea de palabras clave cada una).
  final content = [
    for (var i = 0; i < 10; i++) 'Oración número $i ok.',
  ].join(' ');
  final sentences = splitStudySentences(content, markdown: false);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = StudyRepositoryImpl(
      database: db,
      telemetry: _SilentTelemetry(),
      clock: () => now,
    );
    await insertItemRows(
      db,
      id: 'libro',
      title: 'Libro',
      kind: SourceKind.document,
    );
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto',
            itemId: 'libro',
            kind: RenditionKind.plainText,
            content: Value(content),
            isPrimary: true,
            createdAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<List<StudyProgress>> analyze(
    StudyMarker marker, {
    bool Function()? shouldStop,
  }) => AnalyzeForStudy(repository: repository, marker: marker)
      .call(
        renditionId: 'texto',
        content: content,
        markdown: false,
        shouldStop: shouldStop,
      )
      .toList();

  test(
    'analiza por partes, en orden, y avisa cómo va desde el principio',
    () async {
      final marker = _RecordedMarker(partCharBudget: 164);

      final progress = await analyze(marker);

      expect(marker.parts.map((p) => p.length), [2, 2, 2, 2, 2]);
      expect(marker.parts.first.first, sentences.first);
      expect(marker.parts.last.last, sentences.last);
      expect(progress, [
        for (var done = 0; done <= 5; done++)
          StudyProgress(partsDone: done, partsTotal: 5),
      ]);
      expect(progress.last.finished, isTrue);

      final study = await repository.read('texto');
      expect(study.complete, isTrue);
      // La primera oración de cada parte, en el resumen y en la síntesis.
      expect(study.of(StudyMarkKind.summary).map((m) => m.start), [
        for (var i = 0; i < 10; i += 2) sentences[i].start,
      ]);
      expect(study.of(StudyMarkKind.synthesis), hasLength(5));
    },
  );

  test('si se para, queda lo hecho; al volver, sigue desde ahí', () async {
    final marker = _RecordedMarker(partCharBudget: 164);
    await analyze(marker, shouldStop: () => marker.parts.length == 2);

    final halfway = await repository.read('texto');
    expect(halfway.complete, isFalse);
    expect(halfway.analyzedUntil, sentences[3].end);

    final again = _RecordedMarker(partCharBudget: 164);
    final progress = await analyze(again);

    expect(again.parts.first.first, sentences[4]);
    expect(again.parts, hasLength(3));
    expect(progress.first, const StudyProgress(partsDone: 0, partsTotal: 3));
    expect((await repository.read('texto')).complete, isTrue);
    expect(
      (await repository.read('texto')).of(StudyMarkKind.summary),
      hasLength(5),
    );
  });

  test(
    'si el modelo falla a mitad, lo analizado queda y el error sale',
    () async {
      final marker = _RecordedMarker(partCharBudget: 164);
      final run = AnalyzeForStudy(
        repository: repository,
        marker: marker,
      ).call(renditionId: 'texto', content: content, markdown: false);

      final seen = <StudyProgress>[];
      await expectLater(
        run.map((p) {
          seen.add(p);
          if (p.partsDone == 2) marker.failNext = StateError('sin conexión');
          return p;
        }).drain<void>(),
        throwsA(isA<StateError>()),
      );

      expect(seen.last.partsDone, 2);
      expect((await repository.read('texto')).analyzedUntil, sentences[3].end);
    },
  );

  test('una parte que no entra se achica y el total crece', () async {
    final marker = _RecordedMarker(partCharBudget: 328, fits: 3);

    final progress = await analyze(marker);

    expect(marker.parts.map((p) => p.length), [3, 3, 3, 1]);
    expect(progress.first.partsTotal, 3);
    expect(progress.last, const StudyProgress(partsDone: 4, partsTotal: 4));
    expect((await repository.read('texto')).complete, isTrue);
  });

  test(
    'si el modelo no contesta en el formato, se reintenta una vez',
    () async {
      var calls = 0;
      final marker = _RecordedMarker(
        partCharBudget: 1000,
        reply: (part) =>
            calls++ == 0 ? 'No entendí.' : 'RESUMEN: 2\nSINTESIS: 2',
      );

      final progress = await analyze(marker);

      expect(marker.parts, hasLength(2));
      expect(progress.last.unreadParts, 0);
      final summary = (await repository.read(
        'texto',
      )).of(StudyMarkKind.summary);
      expect(summary.single.start, sentences[1].start);
    },
  );

  test('si tampoco al reintentar, la parte queda sin marcas y se cuenta: no '
      'se traba en ella', () async {
    final marker = _RecordedMarker(
      partCharBudget: 164,
      reply: (part) =>
          part.first == sentences.first ? 'No entendí.' : 'RESUMEN: 1',
    );

    final progress = await analyze(marker);

    expect(marker.parts, hasLength(6));
    expect(progress.last.unreadParts, 1);
    expect(progress.last.finished, isTrue);
    final study = await repository.read('texto');
    expect(study.complete, isTrue);
    expect(study.of(StudyMarkKind.summary), hasLength(4));
  });

  test('ya terminado, no vuelve a gastar', () async {
    await analyze(_RecordedMarker(partCharBudget: 164));

    final again = _RecordedMarker(partCharBudget: 164);
    final progress = await analyze(again);

    expect(again.parts, isEmpty);
    expect(progress, isEmpty);
  });

  test(
    'lo que faltaba se fue del texto: queda terminado sin pedir nada',
    () async {
      await db
          .into(db.studyAnalyses)
          .insert(
            StudyAnalysesCompanion.insert(
              renditionId: 'texto',
              analyzedUntil: sentences.last.start + 1,
              updatedAt: now,
            ),
          );
      final marker = _RecordedMarker(partCharBudget: 164);

      final progress = await analyze(marker);

      expect(marker.parts, isEmpty);
      expect(progress.single.finished, isTrue);
      expect((await repository.read('texto')).complete, isTrue);
    },
  );
}
