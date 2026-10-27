import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_marker.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
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

  /// Qué mira la prueba cada vez que se le pide una parte.
  void Function()? onPart;

  /// Si la próxima llamada falla, como sin conexión.
  Error? failNext;

  @override
  Future<StudyPartOutcome> markPart({
    required String content,
    required List<StudySentence> part,
  }) async {
    onPart?.call();
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

/// La base de verdad, que dice qué paso tiene la tarea en curso cada vez que
/// se le pide lo ya analizado.
class _WatchingRepository extends StudyRepositoryImpl {
  _WatchingRepository({
    required super.database,
    required super.telemetry,
    required this.onRead,
  });

  final void Function() onRead;

  @override
  Future<DocumentStudy> read(String renditionId) {
    onRead();
    return super.read(renditionId);
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

  group('toda oración con contenido sale con sus palabras clave', () {
    /// Cuántas palabras clave tiene cada oración del texto.
    Future<List<int>> keywordsPerSentence() async {
      final keywords = (await repository.read(
        'texto',
      )).of(StudyMarkKind.keyword);
      return [
        for (final s in sentences)
          keywords.where((k) => k.start >= s.start && k.end <= s.end).length,
      ];
    }

    test('las que el modelo se salteó las completa el respaldo local, sin '
        'volver a pedirle nada', () async {
      // El modelo contesta la línea CLAVE de la primera oración de cada parte
      // y saltea las demás.
      final marker = _RecordedMarker(
        partCharBudget: 164,
        reply: (part) => 'RESUMEN: 1\nSINTESIS: 1\nCLAVE 1: número',
      );

      await analyze(marker);

      expect(marker.parts, hasLength(5), reason: 'sin pedidos de más');
      final counts = await keywordsPerSentence();
      expect(
        counts.every((n) => n >= 1 && n <= kMaxKeywordsPerSentence),
        isTrue,
        reason: '$counts',
      );
      // Lo que eligió el modelo se respeta: una sola palabra, la suya.
      final keywords = (await repository.read(
        'texto',
      )).of(StudyMarkKind.keyword);
      for (var i = 0; i < 10; i += 2) {
        final inFirst = keywords.where(
          (k) => k.start >= sentences[i].start && k.end <= sentences[i].end,
        );
        expect(inFirst.map((k) => content.substring(k.start, k.end)), [
          'número',
        ]);
      }
    });

    test('el modelo que no contesta nada de palabras: igual todas las '
        'oraciones las tienen', () async {
      final marker = _RecordedMarker(partCharBudget: 164);

      await analyze(marker);

      final counts = await keywordsPerSentence();
      expect(counts.every((n) => n >= 1), isTrue, reason: '$counts');
      expect((await repository.read('texto')).complete, isTrue);
    });

    test('una parte que el modelo no contestó en el formato también las '
        'tiene: se cuenta como no leída, pero no queda vacía', () async {
      final marker = _RecordedMarker(
        partCharBudget: 164,
        reply: (part) =>
            part.first == sentences.first ? 'No entendí.' : 'RESUMEN: 1',
      );

      final progress = await analyze(marker);

      expect(progress.last.unreadParts, 1);
      final counts = await keywordsPerSentence();
      expect(counts.every((n) => n >= 1), isTrue, reason: '$counts');
      // Sin resumen en la parte que no se leyó.
      final study = await repository.read('texto');
      expect(
        study
            .of(StudyMarkKind.summary)
            .any((m) => m.start < sentences[2].start),
        isFalse,
      );
    });

    test('una parte que no entró entera no completa las oraciones que quedan '
        'para la próxima', () async {
      final marker = _RecordedMarker(partCharBudget: 1000, fits: 3);

      await analyze(marker, shouldStop: () => marker.parts.length == 1);

      final counts = await keywordsPerSentence();
      expect(counts.take(3).every((n) => n >= 1), isTrue, reason: '$counts');
      expect(counts.skip(3), everyElement(0), reason: '$counts');
    });

    test('una palabra que eligió la persona cuenta: esa oración no recibe '
        'otra', () async {
      final chosen = sentences[3];
      final word = content.indexOf('número', chosen.start);
      await repository.addUserMark(
        renditionId: 'texto',
        content: content,
        kind: StudyMarkKind.keyword,
        start: word,
        end: word + 'número'.length,
      );

      await analyze(_RecordedMarker(partCharBudget: 164));

      final counts = await keywordsPerSentence();
      expect(counts[3], 1);
      expect(
        counts.where((n) => n >= 1).length,
        10,
        reason: 'todas las demás, con las suyas: $counts',
      );
    });
  });

  group('dentro de una tarea de la IA (F39, paso 6)', () {
    late AiTaskTracker tracker;
    late AiTaskHandle task;

    setUp(() {
      tracker = AiTaskTracker(clock: () => now);
      task = tracker.begin(
        kind: AiTaskKind.studyAnalysis,
        title: 'Libro',
        steps: const [
          AiTaskStepKind.studySplit,
          AiTaskStepKind.studySend,
          AiTaskStepKind.studyJoin,
        ],
      );
    });

    tearDown(() => tracker.dispose());

    AiTask current() => tracker.tasks.value.single;

    test('le dice en qué paso está: parte el texto, manda cada parte y junta '
        'lo marcado para guardarlo', () async {
      final atMark = <AiTaskStepKind?>[];
      final marker = _RecordedMarker(partCharBudget: 164)
        ..onPart = () => atMark.add(current().currentStep);
      final afterEach = <AiTaskStepKind?>[];

      await task.run(() async {
        await for (final _ in AnalyzeForStudy(
          repository: repository,
          marker: marker,
        ).call(renditionId: 'texto', content: content, markdown: false)) {
          afterEach.add(current().currentStep);
        }
      });

      // Al pedirle cada parte al modelo, el paso es el de mandarla.
      expect(atMark, everyElement(AiTaskStepKind.studySend));
      expect(atMark, hasLength(5));
      // Antes de la primera parte ya se partió el texto y no hay paso en
      // curso; después de cada una, lo marcado se junta y se guarda.
      expect(afterEach.first, isNull);
      expect(afterEach.skip(1), everyElement(AiTaskStepKind.studyJoin));
    });

    test('mientras parte el texto y lee lo ya analizado, el paso en curso es '
        'partirlo', () async {
      final seen = <AiTaskStepKind?>[];
      final watching = _WatchingRepository(
        database: db,
        telemetry: _SilentTelemetry(),
        onRead: () => seen.add(current().currentStep),
      );
      final stream = task.run(
        () => AnalyzeForStudy(
          repository: watching,
          marker: _RecordedMarker(partCharBudget: 164),
        ).call(renditionId: 'texto', content: content, markdown: false),
      );

      await task.run(() => stream.first);

      expect(seen, [AiTaskStepKind.studySplit]);
    });

    test('partir el texto queda hecho antes de la primera parte', () async {
      final marker = _RecordedMarker(partCharBudget: 164);
      final stream = task.run(
        () => AnalyzeForStudy(
          repository: repository,
          marker: marker,
        ).call(renditionId: 'texto', content: content, markdown: false),
      );

      await task.run(() => stream.first);

      expect(
        current().stateOf(AiTaskStepKind.studySplit),
        AiTaskStepState.done,
      );
      expect(
        current().stateOf(AiTaskStepKind.studySend),
        AiTaskStepState.pending,
      );
    });

    test('afuera de toda tarea no cambia nada: analiza igual', () async {
      final marker = _RecordedMarker(partCharBudget: 164);

      final progress = await analyze(marker);

      expect(progress.last.finished, isTrue);
      expect(current().currentStep, isNull);
    });
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
