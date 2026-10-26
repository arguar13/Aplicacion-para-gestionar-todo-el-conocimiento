import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';

/// Lo que la IA está haciendo ahora (F39, paso 6): uno solo en toda la app, la
/// fuente de «Ahora» y «Cómo lo hace» en «Lo que hizo la IA».
///
/// Los tokens de cada tarea salen de lo que el medidor del modelo anota en
/// cada respuesta —la cuenta del proveedor, o el tokenizador de Gemma—: este
/// proveedor es quien lo engancha. NO autoDispose: las colas de la IA lo piden
/// al usarlo y viven toda la sesión.
final aiTaskTrackerProvider = Provider<AiTaskTracker>((ref) {
  final tracker = AiTaskTracker(clock: ref.watch(clockProvider));
  final stopCounting = ref
      .watch(languageModelMeterProvider)
      .addTap(
        (reply) => tracker.recordReply(
          inputTokens: reply.inputTokens,
          outputTokens: reply.tokens,
        ),
      );
  ref.onDispose(() {
    stopCounting();
    tracker.dispose();
  });
  return tracker;
});

/// Las tareas que la IA hace ahora, la que empezó antes primero. Vacío si no
/// está haciendo nada.
///
/// Cada cambio de [AiTaskTracker.tasks] se pasa a quien mira **en el acto**, no
/// invalidando el proveedor para que se vuelva a calcular cuando el programador
/// de Riverpod quiera: así «Ahora» y la actividad ven empezar y terminar una
/// tarea en el mismo cuadro, con el contenedor que sea.
final aiLiveTasksProvider =
    StateNotifierProvider.autoDispose<_LiveTasks, List<AiTask>>(
      (ref) => _LiveTasks(ref.watch(aiTaskTrackerProvider).tasks),
    );

class _LiveTasks extends StateNotifier<List<AiTask>> {
  _LiveTasks(this._tasks) : super(_tasks.value) {
    _tasks.addListener(_changed);
  }

  final ValueListenable<List<AiTask>> _tasks;

  void _changed() => state = _tasks.value;

  @override
  void dispose() {
    _tasks.removeListener(_changed);
    super.dispose();
  }
}
