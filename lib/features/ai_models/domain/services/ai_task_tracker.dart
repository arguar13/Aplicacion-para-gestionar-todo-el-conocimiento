import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';

/// La fuente única de lo que la IA está haciendo ahora (F39, paso 6).
///
/// El análisis para estudiar, la cola que organiza sola, el pedido de
/// tarjetas y la revisión con otro modelo abren cada uno su tarea con [begin]
/// y la van contando —en qué paso están, qué parte, con qué modelo—; «Lo que
/// hizo la IA» lee [tasks] y no sabe quién las hace. Al terminar,
/// [AiTaskHandle.end] da lo que gastó, que queda en la pasada.
///
/// **Los tokens no se estiman.** Salen de donde sale el uso de verdad: la
/// cuenta del proveedor en la nube, o el tokenizador de Gemma, que anotan cada
/// respuesta en `LanguageModelMeter`. Ese medidor llama a [recordReply] en el
/// mismo momento y en la misma zona de quien pidió la respuesta, y es la zona
/// la que dice de qué tarea es: dos tareas a la vez —el análisis de la persona
/// y la cola de fondo— no se mezclan los tokens, ni siquiera cuando esperan
/// el turno del modelo. Una respuesta pedida fuera de una tarea —el chat, un
/// resumen suelto— no es de ninguna y no se anota en ninguna.
class AiTaskTracker {
  AiTaskTracker({required Clock clock}) : _clock = clock;

  final Clock _clock;
  final _tasks = ValueNotifier<List<AiTask>>(const []);
  var _next = 0;
  var _disposed = false;

  /// Las tareas en curso, la que empezó antes primero.
  ValueListenable<List<AiTask>> get tasks => _tasks;

  /// Abre una tarea. [title] es el del elemento; [model], el que trabaja tal
  /// como lo guardan las pasadas; [steps], los pasos de «Cómo lo hace».
  AiTaskHandle begin({
    required AiTaskKind kind,
    required String title,
    String? itemId,
    String? model,
    List<AiTaskStepKind> steps = const [],
    AiTaskProgress? batchProgress,
  }) {
    final id = 'tarea-${_next++}';
    final handle = AiTaskHandle._(this, id, startedAt: _clock());
    if (_disposed) return handle;
    _tasks.value = [
      ..._tasks.value,
      AiTask(
        id: id,
        kind: kind,
        title: title,
        itemId: itemId,
        model: model,
        startedAt: handle.startedAt,
        steps: List.unmodifiable(steps),
        batchProgress: batchProgress,
      ),
    ];
    return handle;
  }

  /// Anota una respuesta del modelo en la tarea de la zona de quien la pidió,
  /// si la hay. Lo llama el medidor del modelo (`LanguageModelMeter`) al
  /// terminar cada respuesta.
  void recordReply({int? inputTokens, int? outputTokens}) {
    final handle = Zone.current[_zoneKey];
    if (handle is! AiTaskHandle || handle._tracker != this) return;
    handle._addTokens(inputTokens ?? 0, outputTokens ?? 0);
  }

  void _update(String id, AiTask Function(AiTask task) change) {
    if (_disposed) return;
    final tasks = _tasks.value;
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final changed = change(tasks[index]);
    if (changed == tasks[index]) return;
    _tasks.value = [...tasks]..[index] = changed;
  }

  void _remove(String id) {
    if (_disposed) return;
    _tasks.value = [
      for (final task in _tasks.value)
        if (task.id != id) task,
    ];
  }

  /// Las tareas en curso se descartan: la sesión terminó. Quien siga contando
  /// una tarea ya no la ve, pero tampoco falla.
  void dispose() {
    _disposed = true;
    _tasks.dispose();
  }

  static final _zoneKey = Object();
}

/// Una tarea en curso: quien la hace la va contando y la cierra con [end].
class AiTaskHandle {
  AiTaskHandle._(this._tracker, this.id, {required this.startedAt});

  final AiTaskTracker _tracker;
  final String id;
  final DateTime startedAt;

  var _ended = false;
  var _input = 0;
  var _output = 0;

  /// La tarea de la que forma parte quien llama —la que abrió con [run] quien
  /// lo llamó, también a través de `await` y de `Stream`—, o `null`. Para que
  /// lo que se hace adentro, como los pasos de revisar o de analizar, diga en
  /// cuál va sin que se lo pasen de mano en mano.
  static AiTaskHandle? get current {
    final handle = Zone.current[AiTaskTracker._zoneKey];
    return handle is AiTaskHandle && !handle._ended ? handle : null;
  }

  /// Si ya terminó: [end] la cierra y nada más se le anota.
  bool get isEnded => _ended;

  /// Corre [body] como parte de esta tarea: las respuestas del modelo que se
  /// pidan desde adentro —también las que esperan su turno— se le anotan a
  /// ella. Si ya terminó, corre igual, sin anotar nada.
  R run<R>(R Function() body) =>
      runZoned(body, zoneValues: {AiTaskTracker._zoneKey: this});

  /// Pasa a hacer [step]: los anteriores quedan hechos y los siguientes por
  /// hacer.
  void step(AiTaskStepKind step) => _change(
    (task) => task.copyWith(
      currentStep: () => step,
      doneSteps: {...task.doneSteps}..remove(step),
    ),
  );

  /// Termina [step]: queda hecho aunque haya pasos por delante. Si era el que
  /// se hacía, no queda ninguno en curso hasta el próximo.
  void finishStep(AiTaskStepKind step) => _change(
    (task) => task.copyWith(
      doneSteps: {...task.doneSteps, step},
      currentStep: () => task.currentStep == step ? null : task.currentStep,
    ),
  );

  /// Lleva [done] de [total] partes hechas de un texto largo.
  void parts(int done, int total) => _change(
    (task) => task.copyWith(
      partProgress: () =>
          AiTaskProgress(done: done, total: total, unit: AiTaskUnit.part),
    ),
  );

  /// Lleva [done] de [total] elementos hechos de un pedido.
  void items(int done, int total) => _change(
    (task) => task.copyWith(
      batchProgress: () =>
          AiTaskProgress(done: done, total: total, unit: AiTaskUnit.item),
    ),
  );

  /// Cambia el modelo que trabaja.
  void model(String? model) => _change((task) => task.copyWith(model: model));

  /// La IA en la nube falló por algo pasajero y se repite sola; `null` si la
  /// respuesta ya vuelve a llegar.
  void retry(AiTaskRetry? retry) =>
      _change((task) => task.copyWith(retry: () => retry));

  /// Lo que lleva gastado: el tiempo, hasta ahora, y los tokens.
  AiTaskUsage get usage => _usage(_tracker._clock());

  /// Cierra la tarea y da lo que gastó. Cerrarla dos veces no suma nada.
  AiTaskUsage end() {
    if (_ended) return AiTaskUsage.none;
    final usage = this.usage;
    _ended = true;
    _tracker._remove(id);
    return usage;
  }

  void _addTokens(int input, int output) {
    if (_ended) return;
    _input += input;
    _output += output;
    _tracker._update(
      id,
      (task) => task.copyWith(inputTokens: _input, outputTokens: _output),
    );
  }

  void _change(AiTask Function(AiTask task) change) {
    if (_ended) return;
    _tracker._update(id, change);
  }

  AiTaskUsage _usage(DateTime now) {
    final elapsed = now.difference(startedAt);
    return AiTaskUsage(
      elapsed: elapsed.isNegative ? Duration.zero : elapsed,
      inputTokens: _input,
      outputTokens: _output,
    );
  }
}
