import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Qué clase de tarea está haciendo la IA ahora (F39, paso 6).
enum AiTaskKind {
  /// Analizar un texto para estudiarlo: resumen, síntesis y palabras clave,
  /// por partes (F36). Lo pidió la persona.
  studyAnalysis,

  /// Organizar un elemento: vínculos, tarjetas, temas y etiquetas, espacio,
  /// referencia, Atlas (F27). La cola de fondo.
  organize,

  /// Hacerle solo las tarjetas a un elemento (F30; desde F43, M18, «Para
  /// cada documento» en «Tarjetas didácticas»).
  flashcards,

  /// Buscarle solo las fechas a un elemento para la línea de tiempo (F40).
  dates,

  /// Revisar con otro modelo lo que hizo la IA (F33).
  review,
}

/// Cada paso de «Cómo lo hace»: una tarea tiene los suyos, en orden.
enum AiTaskStepKind {
  /// Partir el texto en partes que le entren al modelo.
  studySplit,

  /// Mandar la parte al modelo y leer lo que contestó.
  studySend,

  /// Juntar lo marcado y guardarlo en el texto.
  studyJoin,

  /// Completar los datos vacíos de la referencia.
  organizeReference,

  /// Etiquetas y propiedades.
  organizeProperties,

  /// El tema (espacio) del elemento.
  organizeSpace,

  /// Vínculos con otros elementos.
  organizeRelations,

  /// Tarjetas de repaso.
  organizeFlashcards,

  /// El árbol de temas del Atlas y sus notas mapa.
  organizeAtlas,

  /// Los hechos fechados del texto, para la línea de tiempo (F40).
  organizeDates,

  /// Mirar las tarjetas de la IA con otro modelo.
  reviewFlashcards,

  /// Mirar lo demás que hizo la IA con otro modelo.
  reviewThings,
}

/// En qué se cuenta el avance de una tarea.
enum AiTaskUnit {
  /// Las partes en que se parte un texto largo.
  part,

  /// Los pasos de organizar un elemento.
  step,

  /// Los elementos de un pedido.
  item,
}

/// Cuánto va de una tarea, en [unit].
@immutable
class AiTaskProgress {
  const AiTaskProgress({
    required this.done,
    required this.total,
    required this.unit,
  });

  final int done;
  final int total;
  final AiTaskUnit unit;

  /// La que va ahora, de 1 a [total]: la que se está haciendo, no la última
  /// terminada.
  int get current => total <= 0 ? 0 : (done + 1).clamp(1, total);

  /// De 0 a 100: lo hecho sobre el total de ahora. Sin saber cuántas son, 0.
  int get percent => total <= 0 ? 0 : (done * 100 ~/ total).clamp(0, 100);

  @override
  bool operator ==(Object other) =>
      other is AiTaskProgress &&
      other.done == done &&
      other.total == total &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(done, total, unit);

  @override
  String toString() => 'AiTaskProgress($done/$total $unit)';
}

/// El pedido que falló por algo pasajero y se repite solo: «Reintentando (2 de
/// 4)…».
@immutable
class AiTaskRetry {
  const AiTaskRetry({
    required this.attempt,
    required this.maxAttempts,
    required this.failure,
  });

  /// El intento que viene, de 2 a [maxAttempts].
  final int attempt;
  final int maxAttempts;
  final CloudModelFailure failure;

  @override
  bool operator ==(Object other) =>
      other is AiTaskRetry &&
      other.attempt == attempt &&
      other.maxAttempts == maxAttempts &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(attempt, maxAttempts, failure);
}

/// En qué está un paso de «Cómo lo hace».
enum AiTaskStepState { pending, running, done }

/// Lo que la IA está haciendo ahora (F39, paso 6): la fuente única de la que
/// salen «Ahora» y «Cómo lo hace» en «Lo que hizo la IA».
///
/// Una tarea vive mientras se hace; lo que deja, y su tiempo y sus tokens,
/// queda en la pasada (`ai_runs`) que la cola o el análisis abren al
/// empezar.
@immutable
class AiTask {
  const AiTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.startedAt,
    this.itemId,
    this.model,
    this.steps = const [],
    this.doneSteps = const {},
    this.currentStep,
    this.batchProgress,
    this.partProgress,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.retry,
  });

  final String id;
  final AiTaskKind kind;

  /// El título del elemento, o del documento, que se trabaja.
  final String title;
  final String? itemId;

  /// Qué modelo trabaja, como lo guardan las pasadas (`modelLabel` lo
  /// muestra); `null` si no se sabe.
  final String? model;
  final DateTime startedAt;

  /// Los pasos de la tarea, en orden. Vacío si no tiene más que uno.
  final List<AiTaskStepKind> steps;

  /// Los pasos que ya terminaron aunque sean posteriores al actual: al
  /// retomar una pasada cortada, los que ya había hecho.
  final Set<AiTaskStepKind> doneSteps;

  /// El paso que se hace ahora, o `null` entre un paso y otro.
  final AiTaskStepKind? currentStep;

  /// El avance de un pedido de varios elementos: «elemento 3 de 12».
  final AiTaskProgress? batchProgress;

  /// El avance por partes de un texto largo: «parte 3 de 12».
  final AiTaskProgress? partProgress;

  /// Los tokens que el modelo leyó y escribió en esta tarea, contados por
  /// quien los cuenta de verdad: el proveedor en la nube, o el tokenizador de
  /// Gemma. Solo lo que el modelo contestó entero.
  final int inputTokens;
  final int outputTokens;

  /// Si la IA en la nube falló por algo pasajero y se repite sola.
  final AiTaskRetry? retry;

  int get tokens => inputTokens + outputTokens;

  /// El estado del paso [step].
  AiTaskStepState stateOf(AiTaskStepKind step) {
    final index = steps.indexOf(step);
    if (index < 0) return AiTaskStepState.pending;
    final currentIndex = currentStep == null ? -1 : steps.indexOf(currentStep!);
    if (currentIndex == index) return AiTaskStepState.running;
    if (doneSteps.contains(step) || index < currentIndex) {
      return AiTaskStepState.done;
    }
    return AiTaskStepState.pending;
  }

  /// Cuántos pasos terminaron.
  int get stepsDone =>
      steps.where((s) => stateOf(s) == AiTaskStepState.done).length;

  /// El avance que se cuenta para esta tarea: el pedido entero, si lo hay;
  /// si no, las partes; si no, los pasos.
  AiTaskProgress? get progress =>
      batchProgress ??
      partProgress ??
      (steps.isEmpty
          ? null
          : AiTaskProgress(
              done: stepsDone,
              total: steps.length,
              unit: AiTaskUnit.step,
            ));

  /// De 0 a 100, o `null` si no se sabe cuánto falta.
  ///
  /// Un pedido de varios elementos suma la parte del elemento que va: sin eso,
  /// el primero de doce se quedaría en 0 % todo el rato. El avance por partes
  /// va solo, por partes terminadas; los pasos, por pasos terminados.
  int? get percent {
    final batch = batchProgress;
    if (batch != null) {
      if (batch.total <= 0) return 0;
      final inside = _insideFraction;
      return ((batch.done + inside) * 100 / batch.total).floor().clamp(0, 100);
    }
    return (partProgress ?? progress)?.percent;
  }

  /// Cuánto va del elemento en curso dentro de un pedido: 0 a 1.
  double get _insideFraction {
    final part = partProgress;
    if (part != null && part.total > 0) return part.done / part.total;
    if (steps.isNotEmpty) return stepsDone / steps.length;
    return 0;
  }

  /// Cuánto lleva trabajando a [now].
  Duration elapsed(DateTime now) {
    final value = now.difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  AiTask copyWith({
    String? model,
    List<AiTaskStepKind>? steps,
    Set<AiTaskStepKind>? doneSteps,
    AiTaskStepKind? Function()? currentStep,
    AiTaskProgress? Function()? batchProgress,
    AiTaskProgress? Function()? partProgress,
    int? inputTokens,
    int? outputTokens,
    AiTaskRetry? Function()? retry,
  }) => AiTask(
    id: id,
    kind: kind,
    title: title,
    itemId: itemId,
    startedAt: startedAt,
    model: model ?? this.model,
    steps: steps ?? this.steps,
    doneSteps: doneSteps ?? this.doneSteps,
    currentStep: currentStep != null ? currentStep() : this.currentStep,
    batchProgress: batchProgress != null ? batchProgress() : this.batchProgress,
    partProgress: partProgress != null ? partProgress() : this.partProgress,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    retry: retry != null ? retry() : this.retry,
  );

  @override
  bool operator ==(Object other) =>
      other is AiTask &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.itemId == itemId &&
      other.model == model &&
      other.startedAt == startedAt &&
      _sameList(other.steps, steps) &&
      _sameSet(other.doneSteps, doneSteps) &&
      other.currentStep == currentStep &&
      other.batchProgress == batchProgress &&
      other.partProgress == partProgress &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.retry == retry;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    title,
    itemId,
    model,
    startedAt,
    Object.hashAll(steps),
    Object.hashAllUnordered(doneSteps),
    currentStep,
    batchProgress,
    partProgress,
    inputTokens,
    outputTokens,
    retry,
  );

  static bool _sameList(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameSet(Set<Object?> a, Set<Object?> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Lo que gastó una tarea al terminar (F39, paso 6): el tiempo que trabajó y
/// los tokens que contó el modelo. Es lo que queda en su pasada.
@immutable
class AiTaskUsage {
  const AiTaskUsage({
    this.elapsed = Duration.zero,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  static const none = AiTaskUsage();

  final Duration elapsed;
  final int inputTokens;
  final int outputTokens;

  int get tokens => inputTokens + outputTokens;

  bool get isEmpty => elapsed == Duration.zero && tokens == 0;

  @override
  bool operator ==(Object other) =>
      other is AiTaskUsage &&
      other.elapsed == elapsed &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens;

  @override
  int get hashCode => Object.hash(elapsed, inputTokens, outputTokens);

  @override
  String toString() => 'AiTaskUsage($elapsed, $inputTokens + $outputTokens)';
}
