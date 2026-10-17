import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_item_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_review_queue.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../../support/ai_organize_harness.dart';

/// Un revisor de mentira: anota a quién revisó, en qué pasada y con qué, y
/// contesta lo que diga [answer] —una corrección por elemento, o lanzar—.
class _FakeReviewer implements AiItemReviewer {
  Future<AiStepReport> Function(KnowledgeItem item) answer = (_) async =>
      const AiStepReport(forReview: 1);

  final calls =
      <({String itemId, String runId, String? model, String? except})>[];

  @override
  Future<AiStepReport> review(
    KnowledgeItem item, {
    required String runId,
    String? model,
    String? exceptMadeBy,
  }) {
    calls.add((
      itemId: item.id,
      runId: runId,
      model: model,
      except: exceptMadeBy,
    ));
    return answer(item);
  }
}

class _Keeper implements LongWorkKeeper {
  final log = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => log.add('$done/$total');

  @override
  void idle() => log.add('idle');
}

void main() {
  late AiOrganizeHarness vault;
  late _FakeReviewer reviewer;
  late _Keeper keeper;
  late List<AiReviewBatch?> batches;
  late LanguageModelStatus status;
  late List<bool> askedBackground;
  late AiReviewQueue queue;

  setUp(() async {
    vault = AiOrganizeHarness();
    reviewer = _FakeReviewer();
    keeper = _Keeper();
    batches = [];
    askedBackground = [];
    status = const LanguageModelReady(provider: AiProvider.gemini);
    queue = AiReviewQueue(
      runs: vault.runs,
      library: vault.library,
      reviewer: () => reviewer,
      languageModel: () => ({background = false}) async {
        askedBackground.add(background);
        return status;
      },
      modelName: () => 'gemini-3.8-flash',
      telemetry: vault.telemetry,
      clock: vault.clock,
      onBatch: batches.add,
      longWork: keeper,
    );
    for (final id in ['a', 'b', 'c']) {
      await vault.note(id, title: 'Nota $id', content: 'Texto de $id.');
    }
  });

  tearDown(() async {
    await queue.dispose();
    await vault.close();
  });

  Future<List<AiRunRow>> reviewRuns() => (vault.db.select(
    vault.db.aiRuns,
  )..where((r) => r.scope.equalsValue(AiRunScope.review))).get();

  test('revisa de a uno, en orden, cada uno en su pasada de revisión del '
      'modelo elegido, y cuenta lo que propuso', () async {
    queue.review(['a', 'b']);
    await queue.settled;

    expect(reviewer.calls.map((c) => c.itemId), ['a', 'b']);
    expect(
      reviewer.calls.map((c) => c.model),
      everyElement('gemini-3.8-flash'),
    );
    final runs = await reviewRuns();
    expect(runs, hasLength(2));
    expect(runs.map((r) => r.model), everyElement('gemini-3.8-flash'));
    expect(runs.every((r) => r.finishedAt != null), isTrue);
    expect(
      reviewer.calls.map((c) => c.runId).toSet(),
      runs.map((r) => r.id).toSet(),
    );
    expect(queue.batch, const AiReviewBatch(total: 2, done: 2, proposed: 2));
    expect(batches.first, const AiReviewBatch(total: 2));
  });

  test('sale de la cuota de la persona: el chequeo no es el de la IA de '
      'fondo', () async {
    queue.review(['a']);
    await queue.settled;

    expect(askedBackground, isNotEmpty);
    expect(askedBackground, everyElement(isFalse));
  });

  test('al revisar la biblioteca deja afuera lo del mismo modelo; pedido en '
      'un elemento, no', () async {
    queue.review(['a']);
    await queue.settled;
    queue.review(['b'], skipOwnWork: false);
    await queue.settled;

    expect(reviewer.calls.map((c) => c.except), ['gemini-3.8-flash', null]);
  });

  test('un pedido nuevo se suma al que corre, sin repetir', () async {
    queue
      ..pause()
      ..review(['a', 'b'])
      ..review(['b', 'c']);

    expect(queue.batch!.total, 3);
    queue.resume();
    await queue.settled;
    expect(reviewer.calls.map((c) => c.itemId), ['a', 'b', 'c']);
  });

  test(
    'sin cuota no empieza: espera hasta la renovación, sin perder nada',
    () async {
      final resetsAt = vault.now.add(const Duration(hours: 3));
      status = LanguageModelOutOfQuota(
        provider: AiProvider.gemini,
        accounts: 2,
        resetsAt: resetsAt,
      );
      queue.review(['a']);
      await queue.settled;

      expect(reviewer.calls, isEmpty);
      expect(queue.batch!.waiting, AiModelWait.quota);
      expect(queue.batch!.resumesAt, resetsAt);
      expect(keeper.log.last, 'idle');

      status = const LanguageModelReady(provider: AiProvider.gemini);
      queue.languageModelChanged();
      await queue.settled;
      expect(reviewer.calls.map((c) => c.itemId), ['a']);
      expect(queue.batch!.waiting, isNull);
      expect(queue.batch!.finished, isTrue);
    },
  );

  test('a la hora de la renovación se despierta sola', () async {
    // Ya pasó la hora que dijo el proveedor: se despierta enseguida.
    status = LanguageModelOutOfQuota(
      provider: AiProvider.gemini,
      accounts: 1,
      resetsAt: vault.now.subtract(const Duration(seconds: 5)),
    );
    queue.review(['a']);
    await queue.settled;
    expect(reviewer.calls, isEmpty);

    status = const LanguageModelReady(provider: AiProvider.gemini);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await queue.settled;

    expect(reviewer.calls.map((c) => c.itemId), ['a']);
  });

  test('sin clave o sin modelo, lo dice', () async {
    status = const LanguageModelNeedsAccount(provider: AiProvider.gemini);
    queue.review(['a']);
    await queue.settled;

    expect(queue.batch!.modelMissing, isTrue);
    expect(reviewer.calls, isEmpty);
  });

  test('si el modelo deja de contestar a mitad, el elemento se retoma primero '
      'y en la misma pasada', () async {
    var first = true;
    reviewer.answer = (item) async {
      if (item.id == 'a' && first) {
        first = false;
        throw const CloudModelException(
          CloudModelFailure.quotaExhausted,
          retryAfter: Duration(hours: 1),
        );
      }
      return const AiStepReport(forReview: 1);
    };
    queue.review(['a', 'b']);
    await queue.settled;

    expect(reviewer.calls.map((c) => c.itemId), ['a']);
    expect(queue.batch!.waiting, AiModelWait.quota);
    expect(queue.batch!.done, 0);
    final open = (await reviewRuns()).single;
    expect(open.finishedAt, isNull);

    queue.languageModelChanged();
    await queue.settled;

    expect(reviewer.calls.map((c) => c.itemId), ['a', 'a', 'b']);
    expect(reviewer.calls[1].runId, open.id);
    expect(await reviewRuns(), hasLength(2));
    expect(queue.batch, const AiReviewBatch(total: 2, done: 2, proposed: 2));
  });

  test('pedir otra vez el que quedó cortado no lo repite', () async {
    var first = true;
    reviewer.answer = (item) async {
      if (first) {
        first = false;
        throw const CloudModelException(CloudModelFailure.network);
      }
      return const AiStepReport(forReview: 1);
    };
    queue.review(['a']);
    await queue.settled;

    queue.review(['a', 'b']);
    expect(queue.batch!.total, 2);
    queue.languageModelChanged();
    await queue.settled;

    expect(reviewer.calls.map((c) => c.itemId), ['a', 'a', 'b']);
  });

  test(
    'un error que no es de cuota se registra y sigue con el siguiente',
    () async {
      reviewer.answer = (item) async {
        if (item.id == 'a') {
          throw StateError('el modelo contestó cualquier cosa');
        }
        return const AiStepReport(forReview: 1);
      };
      queue.review(['a', 'b']);
      await queue.settled;

      expect(queue.batch, const AiReviewBatch(total: 2, done: 2, proposed: 1));
      expect((await reviewRuns()).every((r) => r.finishedAt != null), isTrue);
    },
  );

  test('en pausa no toma otro; al reanudar sigue', () async {
    queue
      ..pause()
      ..review(['a']);
    await queue.settled;
    expect(reviewer.calls, isEmpty);
    expect(queue.batch!.paused, isTrue);

    queue.resume();
    await queue.settled;
    expect(reviewer.calls, hasLength(1));
    expect(queue.batch!.paused, isFalse);
  });

  test(
    'cancelar saca lo que falta y cierra la pasada que esperaba al modelo',
    () async {
      reviewer.answer = (_) async =>
          throw const CloudModelException(CloudModelFailure.network);
      queue.review(['a', 'b']);
      await queue.settled;
      expect((await reviewRuns()).single.finishedAt, isNull);

      queue.cancel();
      await pumpEventQueue();

      expect(queue.batch, isNull);
      expect(batches.last, isNull);
      expect((await reviewRuns()).single.finishedAt, isNotNull);
      queue.languageModelChanged();
      await queue.settled;
      expect(reviewer.calls, hasLength(1));
    },
  );

  test('un elemento que ya no está cuenta como revisado', () async {
    queue.review(['no-existe', 'a']);
    await queue.settled;

    expect(reviewer.calls.map((c) => c.itemId), ['a']);
    expect(queue.batch!.done, 2);
  });

  test(
    'mantiene viva la app mientras trabaja y la suelta al terminar',
    () async {
      queue.review(['a', 'b']);
      await queue.settled;

      expect(keeper.log, containsAllInOrder(['0/2', '1/2', 'idle']));
      expect(keeper.log.last, 'idle');
    },
  );

  test('terminado, se puede sacar de la vista', () async {
    queue.review(['a']);
    await queue.settled;
    queue.dismiss();

    expect(queue.batch, isNull);
  });
}
