import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_dates_finder.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_flashcard_maker.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/fake_chat_model_manager.dart';
import '../../../../support/fake_embedding_model_manager.dart';
import '../../../../support/gemma_status_check.dart';
import '../../../../support/spy_ai_run_repository.dart';

/// Un paso que "habla con el modelo": al correr, anota en el medidor las
/// respuestas que da, como lo hace el motor de verdad, y deja que la prueba
/// mire la tarea mientras tanto.
class _TalkingStep implements AiOrganizeStep, AiFlashcardMaker, AiDatesFinder {
  _TalkingStep(
    this.toggle,
    this.vault,
    this.meter, {
    this.replies = const [],
    this.spend = Duration.zero,
    this.onRun,
  });

  @override
  final AiOrganizeToggle toggle;
  final AiOrganizeHarness vault;
  final LanguageModelMeter meter;

  /// Lo que contó el modelo en cada respuesta: leídos y escritos.
  final List<({int input, int output})> replies;

  /// Cuánto tarda, en el reloj de la bóveda.
  final Duration spend;

  /// Qué mira la prueba mientras el paso corre.
  final void Function(KnowledgeItem item)? onRun;

  /// Si está, el próximo paso lanza esto, una sola vez.
  Exception? failNext;

  /// Lo mismo, con un error del programa.
  Error? failNextError;

  @override
  Future<AiStepReport> organize(KnowledgeItem item, {required String runId}) =>
      _work(item);

  @override
  Future<AiStepReport> makeFlashcards(
    KnowledgeItem item, {
    required String runId,
    bool anotherBatch = false,
  }) => _work(item);

  @override
  Future<bool> mentionsDates(KnowledgeItem item) async => true;

  @override
  Future<AiStepReport> findDates(KnowledgeItem item, {required String runId}) =>
      _work(item);

  Future<AiStepReport> _work(KnowledgeItem item) async {
    onRun?.call(item);
    for (final reply in replies) {
      await Future<void>.delayed(Duration.zero);
      meter.recordReply(
        LanguageModelReply(
          kind: LanguageModelReplyKind.task,
          total: const Duration(seconds: 1),
          words: 1,
          inputTokens: reply.input,
          tokens: reply.output,
        ),
      );
    }
    vault.now = vault.now.add(spend);
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    if (failNextError case final error?) {
      failNextError = null;
      throw error;
    }
    return AiStepReport.nothing;
  }
}

class _Vectors implements ChunkEmbeddingIndexer {
  @override
  Future<int> indexItem(String itemId) async => 0;

  @override
  Future<int> indexNote(String itemId) async => 1;
}

class _Charging implements ChargingProbe {
  @override
  Future<bool> isCharging() async => false;

  @override
  Stream<bool> watchCharging() => const Stream.empty();
}

/// Lo que la cola de la IA le cuenta a «Lo que hizo la IA» (F39, paso 6): una
/// tarea por elemento, con sus pasos, el modelo y los tokens que gastó de
/// verdad, y en la pasada, al cerrarla, el tiempo y los tokens.
void main() {
  late AiOrganizeHarness vault;
  late AiTaskTracker tracker;
  late LanguageModelMeter meter;
  late _TalkingStep properties;
  late _TalkingStep relations;
  late _TalkingStep cards;
  late List<AiOrganizeStep> steps;
  late List<AiFlashcardsBatch?> batches;
  late FakeChatModelManager chatModel;

  final epoch = DateTime(2026, 10);

  setUp(() {
    vault = AiOrganizeHarness();
    tracker = AiTaskTracker(clock: vault.clock);
    meter = LanguageModelMeter()
      ..addTap(
        (reply) => tracker.recordReply(
          inputTokens: reply.inputTokens,
          outputTokens: reply.tokens,
        ),
      );
    properties = _TalkingStep(AiOrganizeToggle.properties, vault, meter);
    relations = _TalkingStep(AiOrganizeToggle.relations, vault, meter);
    cards = _TalkingStep(AiOrganizeToggle.flashcards, vault, meter);
    steps = [properties, relations, cards];
    batches = [];
    chatModel = FakeChatModelManager(ready: true);
  });

  tearDown(() async {
    tracker.dispose();
    await vault.close();
  });

  AiOrganizeQueue queue({
    AiOrganizeSettings settings = const AiOrganizeSettings(),
    bool tracked = true,
    AiRunRepository? runs,
  }) {
    final queue = AiOrganizeQueue(
      backlog: AiOrganizeBacklogImpl(vault.db),
      runs: runs ?? vault.runs,
      library: vault.library,
      steps: () => steps,
      languageModel: () => gemmaStatusCheck(chatModel),
      embeddingModel: () => FakeEmbeddingModelManager(ready: true),
      vectors: _Vectors.new,
      charging: _Charging(),
      epoch: () async => epoch,
      telemetry: vault.telemetry,
      clock: vault.clock,
      onStatus: (_) {},
      settings: settings,
      modelName: () => 'gemma4E4b',
      onFlashcardsBatch: batches.add,
      tasks: tracked ? tracker : null,
    );
    addTearDown(queue.dispose);
    return queue;
  }

  Future<List<AiRun>> runs() async =>
      (await vault.runs.listRuns()).getOrElse((f) => fail('$f'));

  test('mientras organiza un elemento, la tarea dice qué elemento, con qué '
      'modelo, qué pasos tiene y cuál va', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    final seen = <AiTask>[];
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      onRun: (_) => seen.add(tracker.tasks.value.single),
    );
    relations = _TalkingStep(
      AiOrganizeToggle.relations,
      vault,
      meter,
      onRun: (_) => seen.add(tracker.tasks.value.single),
    );
    steps = [properties, relations, cards];

    await queue().start();

    final first = seen.first;
    expect(first.kind, AiTaskKind.organize);
    expect(first.title, 'Historia');
    expect(first.itemId, 'a');
    expect(first.model, 'gemma4E4b');
    expect(first.steps, [
      AiTaskStepKind.organizeProperties,
      AiTaskStepKind.organizeRelations,
      AiTaskStepKind.organizeFlashcards,
    ]);
    expect(first.currentStep, AiTaskStepKind.organizeProperties);
    expect(first.percent, 0);
    // En el segundo, el primero ya está hecho.
    final second = seen.last;
    expect(second.currentStep, AiTaskStepKind.organizeRelations);
    expect(
      second.stateOf(AiTaskStepKind.organizeProperties),
      AiTaskStepState.done,
    );
    expect(second.percent, 33);
    // Al terminar la tarea se va: ya no hay nada "ahora".
    expect(tracker.tasks.value, isEmpty);
  });

  test('solo cuenta los pasos prendidos', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    late AiTask seen;
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      onRun: (_) => seen = tracker.tasks.value.single,
    );
    steps = [properties, relations, cards];

    await queue(
      settings: const AiOrganizeSettings(relations: false, flashcards: false),
    ).start();

    expect(seen.steps, [AiTaskStepKind.organizeProperties]);
  });

  test('los tokens de cada respuesta, y el tiempo, quedan en la pasada al '
      'cerrarla', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      replies: const [(input: 1000, output: 200)],
      spend: const Duration(seconds: 20),
    );
    relations = _TalkingStep(
      AiOrganizeToggle.relations,
      vault,
      meter,
      replies: const [(input: 500, output: 100), (input: 300, output: 50)],
      spend: const Duration(seconds: 10),
    );
    steps = [properties, relations, cards];

    await queue().start();

    final run = (await runs()).single;
    expect(run.finishedAt, isNotNull);
    expect((run.inputTokens, run.outputTokens), (1800, 350));
    expect(run.workTime, const Duration(seconds: 30));
    expect(run.scope, AiRunScope.organize);
  });

  test('lo que costó se guarda antes de cerrar la pasada, y la tarea termina '
      'después de cerrarla: quien vuelve a leer al terminar la encuentra '
      'cerrada y con su costo', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    final log = <String>[];
    tracker.tasks.addListener(() {
      if (tracker.tasks.value.isEmpty) log.add('tarea terminada');
    });
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      replies: const [(input: 10, output: 1)],
    );
    steps = [properties];

    await queue(runs: SpyAiRunRepository(vault.runs, log)).start();

    expect(log, ['abre', 'suma costo', 'cierra', 'tarea terminada']);
  });

  test('si el paso falla por algo que no es del modelo, igual cuenta lo que '
      'gastó y la tarea se va', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      replies: const [(input: 40, output: 4)],
    )..failNextError = StateError('sin memoria');
    steps = [properties];

    await queue().start();

    final run = (await runs()).single;
    expect((run.inputTokens, run.outputTokens), (40, 4));
    expect(tracker.tasks.value, isEmpty);
  });

  test('sin tracker la cola anda igual y la pasada queda en cero', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      replies: const [(input: 40, output: 4)],
    );
    steps = [properties];

    await queue(tracked: false).start();

    final run = (await runs()).single;
    expect(run.finishedAt, isNotNull);
    expect(run.hasUsage, isFalse);
  });

  test('si el modelo deja de contestar a mitad, lo gastado hasta ahí queda en '
      'la pasada abierta, y al retomar se suma lo que falta, con los pasos '
      'que ya hizo marcados', () async {
    await vault.source('a', title: 'Historia', content: 'Texto.');
    properties = _TalkingStep(
      AiOrganizeToggle.properties,
      vault,
      meter,
      replies: const [(input: 100, output: 10)],
      spend: const Duration(seconds: 5),
    );
    relations = _TalkingStep(
      AiOrganizeToggle.relations,
      vault,
      meter,
      replies: const [(input: 200, output: 20)],
      spend: const Duration(seconds: 7),
    )..failNext = const CloudModelException(CloudModelFailure.timeout);
    steps = [properties, relations];
    final ai = queue();

    // Con el cloud "no listo" no vuelve solo: se mira la pasada cortada.
    await ai.start();

    var run = (await runs()).single;
    expect(run.finishedAt, isNull, reason: 'queda abierta para retomarla');
    expect((run.inputTokens, run.outputTokens), (300, 30));
    expect(run.workTime, const Duration(seconds: 12));
    expect(tracker.tasks.value, isEmpty);

    // Vuelve el modelo: retoma en el paso que faltaba, sin repetir el otro.
    late AiTask resumed;
    relations = _TalkingStep(
      AiOrganizeToggle.relations,
      vault,
      meter,
      replies: const [(input: 50, output: 5)],
      spend: const Duration(seconds: 3),
      onRun: (_) => resumed = tracker.tasks.value.single,
    );
    steps = [properties, relations];
    ai.languageModelChanged();
    await ai.settled;

    expect(
      resumed.stateOf(AiTaskStepKind.organizeProperties),
      AiTaskStepState.done,
    );
    expect(resumed.currentStep, AiTaskStepKind.organizeRelations);
    run = (await runs()).single;
    expect(run.finishedAt, isNotNull);
    expect((run.inputTokens, run.outputTokens), (350, 35));
    expect(run.workTime, const Duration(seconds: 15));
  });

  group('solo tarjetas, pedidas desde Repasar', () {
    test('si el modelo deja de contestar, la tarea se va y lo gastado queda en '
        'la pasada, que sigue abierta para retomarla', () async {
      await vault.source(
        'a',
        title: 'Historia',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      cards = _TalkingStep(
        AiOrganizeToggle.flashcards,
        vault,
        meter,
        replies: const [(input: 30, output: 3)],
        spend: const Duration(seconds: 6),
      )..failNext = const CloudModelException(CloudModelFailure.timeout);
      steps = [cards];
      final ai = queue()..makeFlashcards(['a']);

      await ai.settled;

      final run = (await runs()).single;
      expect(run.scope, AiRunScope.flashcards);
      expect(run.finishedAt, isNull);
      expect((run.inputTokens, run.outputTokens), (30, 3));
      expect(run.workTime, const Duration(seconds: 6));
      expect(tracker.tasks.value, isEmpty);
    });

    test('es una tarea de tarjetas con su paso y cuánto va del pedido; lo '
        'gastado queda en su pasada', () async {
      // De la biblioteca que ya existía: la cola no la organiza sola, sin el
      // cargador.
      await vault.source(
        'a',
        title: 'Historia',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      await vault.source(
        'b',
        title: 'Roma',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      final seen = <AiTask>[];
      cards = _TalkingStep(
        AiOrganizeToggle.flashcards,
        vault,
        meter,
        replies: const [(input: 90, output: 9)],
        spend: const Duration(seconds: 4),
        onRun: (_) => seen.add(tracker.tasks.value.single),
      );
      steps = [cards];
      final ai = queue()..makeFlashcards(['a', 'b']);
      await ai.settled;

      expect(seen.map((t) => t.kind).toSet(), {AiTaskKind.flashcards});
      expect(seen.map((t) => t.title), ['Historia', 'Roma']);
      expect(seen.first.steps, [AiTaskStepKind.organizeFlashcards]);
      expect(seen.first.batchProgress?.total, 2);
      expect(seen.first.batchProgress?.done, 0);
      expect(seen.last.batchProgress?.done, 1);
      expect(seen.last.progress?.current, 2);
      final listed = await runs();
      expect(listed.map((r) => r.scope).toSet(), {AiRunScope.flashcards});
      expect(listed.map((r) => (r.inputTokens, r.outputTokens)).toSet(), {
        (90, 9),
      });
      expect(listed.map((r) => r.workTime).toSet(), {
        const Duration(seconds: 4),
      });
      expect(tracker.tasks.value, isEmpty);
    });

    test('es una tarea de fechas (F40) con su paso y cuánto va del pedido; lo '
        'gastado queda en su pasada de fechas', () async {
      for (final id in ['a', 'b']) {
        await vault.source(
          id,
          title: 'Doc $id',
          content: 'Texto.',
          createdAt: DateTime(2026, 9),
        );
      }
      final seen = <AiTask>[];
      final dates = _TalkingStep(
        AiOrganizeToggle.dates,
        vault,
        meter,
        replies: const [(input: 70, output: 7)],
        spend: const Duration(seconds: 3),
        onRun: (_) => seen.add(tracker.tasks.value.single),
      );
      steps = [dates];
      final ai = queue()..findDates(['a', 'b']);
      await ai.settled;

      expect(seen.map((t) => t.kind).toSet(), {AiTaskKind.dates});
      expect(seen.map((t) => t.title), ['Doc a', 'Doc b']);
      expect(seen.first.steps, [AiTaskStepKind.organizeDates]);
      expect(seen.first.currentStep, AiTaskStepKind.organizeDates);
      expect(seen.first.batchProgress?.total, 2);
      expect(seen.first.batchProgress?.done, 0);
      expect(seen.last.batchProgress?.done, 1);
      final listed = await runs();
      expect(listed.map((r) => r.scope).toSet(), {AiRunScope.dates});
      expect(listed.map((r) => (r.inputTokens, r.outputTokens)).toSet(), {
        (70, 7),
      });
      expect(listed.map((r) => r.workTime).toSet(), {
        const Duration(seconds: 3),
      });
      expect(tracker.tasks.value, isEmpty);
    });

    test('con las fechas prendidas, el paso de la pasada entera es también '
        'su paso de «Cómo lo hace»', () async {
      await vault.source('a', title: 'Doc', content: 'Texto.');
      final seen = <AiTask>[];
      steps = [
        _TalkingStep(AiOrganizeToggle.relations, vault, meter),
        _TalkingStep(
          AiOrganizeToggle.dates,
          vault,
          meter,
          onRun: (_) => seen.add(tracker.tasks.value.single),
        ),
      ];

      await queue().start();

      expect(seen.single.kind, AiTaskKind.organize);
      expect(seen.single.steps, [
        AiTaskStepKind.organizeRelations,
        AiTaskStepKind.organizeDates,
      ]);
      expect(seen.single.currentStep, AiTaskStepKind.organizeDates);
    });
  });
}
