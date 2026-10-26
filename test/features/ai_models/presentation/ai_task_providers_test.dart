import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_task_providers.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

/// El tracker de lo que hace la IA, enganchado al medidor del modelo (F39,
/// paso 6): los tokens salen de lo que de verdad anota cada respuesta.
void main() {
  late ProviderContainer container;
  late LanguageModelMeter meter;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 24, 10);
    meter = LanguageModelMeter();
    container = ProviderContainer(
      overrides: [
        languageModelMeterProvider.overrideWithValue(meter),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
  });

  void reply({required int input, required int output}) => meter.recordReply(
    LanguageModelReply(
      kind: LanguageModelReplyKind.task,
      total: const Duration(seconds: 1),
      words: 1,
      inputTokens: input,
      tokens: output,
    ),
  );

  test('una respuesta del modelo pedida desde una tarea le suma sus tokens, '
      'con el reloj de la app', () async {
    final tracker = container.read(aiTaskTrackerProvider);
    final task = tracker.begin(kind: AiTaskKind.organize, title: 'Roma');
    now = now.add(const Duration(seconds: 30));

    await task.run(() async => reply(input: 800, output: 40));

    expect(task.usage.inputTokens, 800);
    expect(task.usage.outputTokens, 40);
    expect(task.usage.elapsed, const Duration(seconds: 30));
  });

  test('una respuesta que no es de ninguna tarea —el chat— no se anota en '
      'ninguna', () {
    final tracker = container.read(aiTaskTrackerProvider);
    final task = tracker.begin(kind: AiTaskKind.organize, title: 'Roma');

    reply(input: 100, output: 10);

    expect(task.usage.tokens, 0);
  });

  test('las tareas en curso se ven en el acto, al empezar y al terminar, en '
      'quien las mira', () {
    final seen = <int>[];
    container.listen(
      aiLiveTasksProvider,
      (_, tasks) => seen.add(tasks.length),
      fireImmediately: true,
    );
    final tracker = container.read(aiTaskTrackerProvider);

    final a = tracker.begin(kind: AiTaskKind.organize, title: 'A');
    final b = tracker.begin(kind: AiTaskKind.studyAnalysis, title: 'B');
    a.end();
    b.end();

    expect(seen, [0, 1, 2, 1, 0]);
    expect(container.read(aiLiveTasksProvider), isEmpty);
  });

  test('cada cambio de una tarea —el avance, los tokens— también llega', () {
    final tracker = container.read(aiTaskTrackerProvider);
    final task = tracker.begin(kind: AiTaskKind.studyAnalysis, title: 'A');
    final percents = <int?>[];
    container.listen(
      aiLiveTasksProvider,
      (_, tasks) => percents.add(tasks.single.percent),
      fireImmediately: true,
    );

    task
      ..parts(1, 4)
      ..parts(2, 4);

    expect(percents, [null, 25, 50]);
  });

  test('al descartar el contenedor, el medidor deja de contarle al tracker, y '
      'el tracker ya no cambia', () async {
    final tracker = container.read(aiTaskTrackerProvider);
    final task = tracker.begin(kind: AiTaskKind.organize, title: 'Roma');

    container.dispose();
    await task.run(() async => reply(input: 5, output: 5));
    task.parts(1, 2);

    expect(task.usage.tokens, 0, reason: 'ya nadie le cuenta');
    expect(tracker.tasks.value.single.partProgress, isNull);
  });

  test('quien dejó de mirar las tareas se da de baja del tracker: no queda '
      'ningún oyente colgado', () async {
    final listenable = _CountingTasks();
    final tracker = _CountingTracker(listenable);
    final other = ProviderContainer(
      overrides: [aiTaskTrackerProvider.overrideWithValue(tracker)],
    );
    addTearDown(other.dispose);

    final subscription = other.listen(aiLiveTasksProvider, (_, _) {});
    expect(listenable.active, 1);
    subscription.close();
    // Sin nadie que la mire, la lista se descarta al terminar el turno.
    await other.pump();

    expect(listenable.active, 0);
  });
}

/// Las tareas con la cuenta de quién las escucha.
class _CountingTasks extends ValueNotifier<List<AiTask>> {
  _CountingTasks() : super(const []);

  int active = 0;

  @override
  void addListener(VoidCallback listener) {
    active++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    active--;
    super.removeListener(listener);
  }
}

class _CountingTracker extends AiTaskTracker {
  _CountingTracker(this._listenable) : super(clock: DateTime.now);

  final _CountingTasks _listenable;

  @override
  ValueListenable<List<AiTask>> get tasks => _listenable;
}
