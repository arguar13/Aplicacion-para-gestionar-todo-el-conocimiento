import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';

/// Guarda en una pasada lo que costó su tarea (F39, paso 6): el tiempo que el
/// modelo trabajó y los tokens que contó, una sola vez.
///
/// Quien corre una pasada llama [save] antes de cerrarla, para que quien la
/// lee al cerrarse ya lo encuentre, y otra vez al salir, por si algo la cortó
/// antes —el modelo dejó de contestar, o un error—: lo que gastó hasta ahí es
/// suyo, y al retomarla se le suma lo que falte. La segunda vez no hace nada.
/// La tarea se cierra con [end], **después** de cerrar la pasada: «Lo que hizo
/// la IA» vuelve a leer la actividad cuando la tarea termina, y tiene que
/// encontrar la pasada ya cerrada y con lo que costó. Sin tarea —quien corre
/// la pasada no lleva la cuenta—, ninguna de las dos hace nada.
class AiRunUsageSaver {
  AiRunUsageSaver({
    required AiRunRepository runs,
    required TelemetryService telemetry,
    required String runId,
    required AiTaskHandle? task,
    required String hint,
  }) : _runs = runs,
       _telemetry = telemetry,
       _runId = runId,
       _task = task,
       _hint = hint;

  final AiRunRepository _runs;
  final TelemetryService _telemetry;
  final String _runId;
  final AiTaskHandle? _task;
  final String _hint;
  var _saved = false;

  /// Guarda lo que gastó la tarea hasta ahora. Un fallo se registra: no corta
  /// la pasada.
  Future<void> save() async {
    final task = _task;
    if (_saved || task == null) return;
    _saved = true;
    final usage = task.usage;
    if (usage.isEmpty) return;
    (await _runs.addUsage(_runId, usage)).match(
      (failure) => _telemetry.recordError(
        failure,
        StackTrace.current,
        hint: '$_hint: no se pudo guardar lo que costó la pasada',
      ),
      (_) {},
    );
  }

  /// Cierra la tarea: deja de verse como algo en curso.
  void end() => _task?.end();
}
