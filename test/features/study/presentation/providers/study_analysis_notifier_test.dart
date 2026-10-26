import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/services/study_marker.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/spy_ai_run_repository.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Un modelo grabado que contesta siempre lo mismo; cada parte puede esperar
/// a que la prueba la suelte.
class _RecordedMarker implements StudyMarker {
  @override
  int get partCharBudget => 164;

  int calls = 0;
  Completer<void>? gate;
  Error? fail;
  Exception? failWith;

  /// Qué pasa cada vez que se marca una parte (p. ej. correr el reloj).
  void Function()? onPart;

  /// Qué pasa justo al empezar a marcar una parte, antes de esperar.
  void Function()? onStart;

  @override
  Future<StudyPartOutcome> markPart({
    required String content,
    required List<StudySentence> part,
  }) async {
    calls++;
    onStart?.call();
    await gate?.future;
    onPart?.call();
    if (fail case final error?) throw error;
    if (failWith case final error?) throw error;
    return StudyPartOutcome(
      analyzed: part.length,
      marks: parseStudyReply('RESUMEN: 1', content: content, part: part),
    );
  }
}

class _RecordingKeeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('$done/$total');

  @override
  void idle() => calls.add('idle');
}

/// El análisis de un texto desde la interfaz (F36): cómo va, el servicio en
/// primer plano, parar y los errores.
void main() {
  late AppDatabase db;
  late StudyRepositoryImpl repository;
  late _RecordedMarker marker;
  late _RecordingKeeper keeper;
  late StudyAnalysisNotifier notifier;
  final now = DateTime(2026, 10, 22, 10);

  // Seis oraciones: con 164 caracteres por parte, tres partes de dos.
  final content = [
    for (var i = 0; i < 6; i++) 'Oración número $i ok.',
  ].join(' ');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = StudyRepositoryImpl(
      database: db,
      telemetry: _SilentTelemetry(),
      clock: () => now,
    );
    marker = _RecordedMarker();
    keeper = _RecordingKeeper();
    notifier = StudyAnalysisNotifier(
      renditionId: 'texto',
      analyze: () => AnalyzeForStudy(repository: repository, marker: marker),
      keeper: () => keeper,
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

  tearDown(() async {
    notifier.dispose();
    await db.close();
  });

  test(
    'cuenta cómo va, mantiene viva la app y la suelta al terminar',
    () async {
      final states = <StudyAnalysisState>[];
      notifier.addListener(states.add, fireImmediately: false);

      await notifier.start(content: content, markdown: false);

      expect(states.first, isA<StudyAnalysisRunning>());
      expect((states.first as StudyAnalysisRunning).progress, isNull);
      expect(
        [
          for (final s in states.whereType<StudyAnalysisRunning>())
            s.progress?.partsDone,
        ],
        [null, 0, 1, 2, 3],
      );
      expect(states.last, isA<StudyAnalysisDone>());
      expect(keeper.calls, ['0/0', '0/3', '1/3', '2/3', '3/3', 'idle']);
      expect((await repository.read('texto')).complete, isTrue);
    },
  );

  test('pedirlo de nuevo mientras analiza no arranca otro', () async {
    marker.gate = Completer<void>();
    final first = notifier.start(content: content, markdown: false);
    await pumpEventQueue();

    await notifier.start(content: content, markdown: false);
    marker.gate!.complete();
    await first;

    expect(marker.calls, 3);
  });

  test('parar termina después de la parte en curso; lo hecho queda', () async {
    marker.gate = Completer<void>();
    final run = notifier.start(content: content, markdown: false);
    await pumpEventQueue();

    notifier.stop();
    marker.gate!.complete();
    await run;

    expect(notifier.state, isA<StudyAnalysisIdle>());
    expect(marker.calls, 1);
    final study = await repository.read('texto');
    expect(study.started, isTrue);
    expect(study.complete, isFalse);
    expect(keeper.calls.last, 'idle');
  });

  test('si el modelo falla, lo dice y suelta la app; lo hecho queda', () async {
    marker.fail = StateError('sin conexión');

    await notifier.start(content: content, markdown: false);

    final state = notifier.state;
    expect(state, isA<StudyAnalysisFailed>());
    expect((state as StudyAnalysisFailed).error, isA<StateError>());
    expect(keeper.calls.last, 'idle');

    notifier.acknowledge();
    expect(notifier.state, isA<StudyAnalysisIdle>());
  });

  group('F39: lo que pasa mientras analiza', () {
    late StreamController<AiNotice> notices;
    late DateTime clockNow;
    late StudyAnalysisNotifier timed;

    setUp(() {
      notices = StreamController<AiNotice>.broadcast();
      clockNow = DateTime(2026, 10, 23, 10);
      timed = StudyAnalysisNotifier(
        renditionId: 'texto',
        analyze: () => AnalyzeForStudy(repository: repository, marker: marker),
        notices: notices.stream,
        clock: () => clockNow,
      );
    });

    tearDown(() async {
      timed.dispose();
      await notices.close();
    });

    AiRetryNotice retry(int attempt) => AiRetryNotice(
      at: clockNow,
      provider: AiProvider.gemini,
      failure: CloudModelFailure.network,
      attempt: attempt,
      maxAttempts: 4,
      wait: const Duration(seconds: 3),
    );

    test('cuánto falta sale del ritmo de las partes ya hechas', () async {
      marker.onPart = () =>
          clockNow = clockNow.add(const Duration(seconds: 20));
      final states = <StudyAnalysisState>[];
      timed.addListener(states.add, fireImmediately: false);

      await timed.start(content: content, markdown: false);

      expect(
        [for (final s in states.whereType<StudyAnalysisRunning>()) s.remaining],
        [
          // Preparando, y las tres partes por hacer: todavía no hay ritmo.
          null,
          null,
          // Una parte en 20 s, faltan dos.
          const Duration(seconds: 40),
          const Duration(seconds: 20),
          // Terminó: no falta nada.
          null,
        ],
      );
    });

    test(
      'un reintento de la IA se muestra hasta que la respuesta vuelve',
      () async {
        marker.gate = Completer<void>();
        final run = timed.start(content: content, markdown: false);
        await pumpEventQueue();

        notices.add(retry(2));
        await pumpEventQueue();
        final running = timed.state as StudyAnalysisRunning;
        expect(
          running.retry,
          const StudyRetry(
            attempt: 2,
            maxAttempts: 4,
            failure: CloudModelFailure.network,
          ),
        );
        // El avance no se pierde.
        expect(running.progress?.partsTotal, 3);

        notices.add(retry(3));
        await pumpEventQueue();
        expect((timed.state as StudyAnalysisRunning).retry?.attempt, 3);

        notices.add(
          AiRetryEndedNotice(at: clockNow, provider: AiProvider.gemini),
        );
        await pumpEventQueue();
        expect((timed.state as StudyAnalysisRunning).retry, isNull);

        marker.gate!.complete();
        await run;
      },
    );

    test('terminar una parte borra el reintento', () async {
      marker.gate = Completer<void>();
      final run = timed.start(content: content, markdown: false);
      await pumpEventQueue();
      notices.add(retry(2));
      await pumpEventQueue();

      marker.gate!.complete();
      await run;

      expect(timed.state, isA<StudyAnalysisDone>());
    });

    test(
      'los reintentos de antes o de después de analizar no cuentan',
      () async {
        notices.add(retry(2));
        await pumpEventQueue();
        expect(timed.state, isA<StudyAnalysisIdle>());

        await timed.start(content: content, markdown: false);
        notices.add(retry(2));
        await pumpEventQueue();
        expect(timed.state, isA<StudyAnalysisDone>());
      },
    );

    test(
      'si la IA en la nube se cortó, el estado trae la clase de falla',
      () async {
        marker.failWith = const CloudModelException(CloudModelFailure.timeout);

        await timed.start(content: content, markdown: false);

        final failed = timed.state as StudyAnalysisFailed;
        expect(failed.failure, CloudModelFailure.timeout);
      },
    );

    test('un error que no es de la nube no tiene clase de falla', () async {
      marker.fail = StateError('otro');

      await timed.start(content: content, markdown: false);

      expect((timed.state as StudyAnalysisFailed).failure, isNull);
    });
  });

  group('F39, paso 6: una tarea de la IA y su pasada de estudio', () {
    late DateTime clockNow;
    late AiTaskTracker tracker;
    late LanguageModelMeter meter;
    late AiRunRepositoryImpl runs;
    late StreamController<AiNotice> notices;
    late StudyAnalysisNotifier tracked;

    setUp(() {
      clockNow = DateTime(2026, 10, 24, 10);
      tracker = AiTaskTracker(clock: () => clockNow);
      meter = LanguageModelMeter()
        ..addTap(
          (reply) => tracker.recordReply(
            inputTokens: reply.inputTokens,
            outputTokens: reply.tokens,
          ),
        );
      runs = AiRunRepositoryImpl(
        database: db,
        telemetry: _SilentTelemetry(),
        ids: FakeIdGenerator(),
        clock: () => clockNow,
      );
      notices = StreamController<AiNotice>.broadcast();
      tracked = StudyAnalysisNotifier(
        renditionId: 'texto',
        analyze: () => AnalyzeForStudy(repository: repository, marker: marker),
        notices: notices.stream,
        clock: () => clockNow,
        tasks: tracker,
        runs: () => runs,
        telemetry: _SilentTelemetry(),
        modelName: () => 'gemini-3.8-flash',
        titleOf: (itemId) async => itemId == 'libro' ? 'Historia' : null,
      );
      // Cada parte: el modelo contesta con lo que contó y tarda 20 s.
      marker.onPart = () {
        meter.recordReply(
          const LanguageModelReply(
            kind: LanguageModelReplyKind.task,
            total: Duration(seconds: 20),
            words: 2,
            inputTokens: 1000,
            tokens: 100,
          ),
        );
        clockNow = clockNow.add(const Duration(seconds: 20));
      };
    });

    tearDown(() async {
      tracked.dispose();
      tracker.dispose();
      await notices.close();
    });

    Future<List<AiRun>> studyRuns() async => (await runs.listRuns())
        .getOrElse((f) => fail('$f'))
        .where((run) => run.scope == AiRunScope.study)
        .toList();

    test('mientras analiza, la tarea dice qué documento, con qué modelo, qué '
        'parte va y cuántos tokens lleva, y cuál es su paso', () async {
      final seen = <AiTask>[];
      marker.onStart = () => seen.add(tracker.tasks.value.single);

      await tracked.start(content: content, markdown: false, itemId: 'libro');

      expect(seen, hasLength(3));
      final first = seen.first;
      expect(first.kind, AiTaskKind.studyAnalysis);
      expect(first.title, 'Historia');
      expect(first.itemId, 'libro');
      expect(first.model, 'gemini-3.8-flash');
      expect(first.currentStep, AiTaskStepKind.studySend);
      expect(first.stateOf(AiTaskStepKind.studySplit), AiTaskStepState.done);
      expect(first.partProgress?.done, 0);
      expect(first.partProgress?.total, 3);
      expect(first.tokens, 0);
      // Con la segunda, la primera ya está hecha y gastó sus tokens.
      expect(seen[1].partProgress?.done, 1);
      expect(seen[1].percent, 33);
      expect(seen[1].tokens, 1100);
      expect(seen[2].tokens, 2200);
      expect(tracker.tasks.value, isEmpty);
    });

    test('al terminar deja una pasada de estudio con el modelo, el tiempo y '
        'los tokens', () async {
      await tracked.start(content: content, markdown: false, itemId: 'libro');

      final run = (await studyRuns()).single;
      expect(run.itemId, 'libro');
      expect(run.model, 'gemini-3.8-flash');
      expect(run.finishedAt, isNotNull);
      expect(run.workTime, const Duration(seconds: 60));
      expect((run.inputTokens, run.outputTokens), (3000, 300));
      expect(run.organizedItem, isFalse);
      expect(tracked.state, isA<StudyAnalysisDone>());
    });

    test('si el modelo se corta, lo que ya gastó queda en la pasada, cerrada, '
        'y la tarea se va', () async {
      var parts = 0;
      final hook = marker.onPart;
      marker.onPart = () {
        hook!();
        if (++parts == 2) {
          marker.failWith = const CloudModelException(
            CloudModelFailure.timeout,
          );
        }
      };

      await tracked.start(content: content, markdown: false, itemId: 'libro');

      expect(tracked.state, isA<StudyAnalysisFailed>());
      final run = (await studyRuns()).single;
      expect(run.finishedAt, isNotNull);
      // La segunda respuesta llegó a contarse antes de fallar la parte.
      expect(run.tokens, 2200);
      expect(run.workTime, const Duration(seconds: 40));
      expect(tracker.tasks.value, isEmpty);
    });

    test('parar termina la pasada con lo gastado hasta ahí', () async {
      marker.gate = Completer<void>();
      final done = tracked.start(
        content: content,
        markdown: false,
        itemId: 'libro',
      );
      await pumpEventQueue();
      expect(tracker.tasks.value, hasLength(1));

      tracked.stop();
      marker.gate!.complete();
      await done;

      final run = (await studyRuns()).single;
      expect(run.finishedAt, isNotNull);
      expect((run.inputTokens, run.outputTokens), (1000, 100));
      expect(tracker.tasks.value, isEmpty);
    });

    test('el reintento de la IA se ve en la tarea y se borra cuando vuelve '
        'la respuesta', () async {
      marker.gate = Completer<void>();
      final done = tracked.start(
        content: content,
        markdown: false,
        itemId: 'libro',
      );
      await pumpEventQueue();

      notices.add(
        AiRetryNotice(
          at: clockNow,
          provider: AiProvider.gemini,
          failure: CloudModelFailure.network,
          attempt: 2,
          maxAttempts: 4,
          wait: const Duration(seconds: 3),
        ),
      );
      await pumpEventQueue();
      expect(tracker.tasks.value.single.retry?.attempt, 2);

      notices.add(
        AiRetryEndedNotice(at: clockNow, provider: AiProvider.gemini),
      );
      await pumpEventQueue();
      expect(tracker.tasks.value.single.retry, isNull);

      marker.gate!.complete();
      await done;
    });

    test('sin el documento no hay pasada que guardar, pero la tarea se '
        've', () async {
      AiTask? seen;
      marker.onStart = () => seen ??= tracker.tasks.value.single;

      await tracked.start(content: content, markdown: false);

      expect(seen?.title, isEmpty);
      expect(await studyRuns(), isEmpty);
      expect(tracker.tasks.value, isEmpty);
    });

    test('lo que costó se guarda y la pasada se cierra antes de que la tarea '
        'termine: «Lo que hizo la IA» vuelve a leer en ese momento', () async {
      final log = <String>[];
      tracker.tasks.addListener(() {
        if (tracker.tasks.value.isEmpty) log.add('tarea terminada');
      });
      final ordered = StudyAnalysisNotifier(
        renditionId: 'texto',
        analyze: () => AnalyzeForStudy(repository: repository, marker: marker),
        clock: () => clockNow,
        tasks: tracker,
        runs: () => SpyAiRunRepository(runs, log),
        telemetry: _SilentTelemetry(),
      );
      addTearDown(ordered.dispose);

      await ordered.start(content: content, markdown: false, itemId: 'libro');

      expect(log, ['abre', 'suma costo', 'cierra', 'tarea terminada']);
    });

    test('un texto sin nada por analizar —ya llegó al final— no abre ninguna '
        'pasada', () async {
      await db
          .into(db.studyAnalyses)
          .insert(
            StudyAnalysesCompanion.insert(
              renditionId: 'texto',
              analyzedUntil: content.length,
              updatedAt: clockNow,
            ),
          );

      await tracked.start(content: content, markdown: false, itemId: 'libro');

      expect(marker.calls, 0);
      expect(await studyRuns(), isEmpty);
      expect(tracked.state, isA<StudyAnalysisDone>());
    });

    test('un texto ya analizado entero no abre ninguna pasada', () async {
      await tracked.start(content: content, markdown: false, itemId: 'libro');
      expect(await studyRuns(), hasLength(1));

      await tracked.start(content: content, markdown: false, itemId: 'libro');

      expect(await studyRuns(), hasLength(1));
      expect(tracker.tasks.value, isEmpty);
    });
  });
}
