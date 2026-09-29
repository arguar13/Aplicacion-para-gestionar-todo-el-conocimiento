import 'package:freezed_annotation/freezed_annotation.dart';

part 'processing_queue_state.freezed.dart';

/// En qué carril está un elemento en curso, o si espera turno para el largo.
enum ProcessingLane {
  /// En el carril corto: traer una página, los subtítulos, el texto de un
  /// documento.
  short,

  /// Terminó su parte corta y espera que se libere el carril largo.
  waitingForLong,

  /// En el carril largo: transcribiendo, reconociendo páginas.
  long,
}

/// Cuánto va un elemento en curso.
@freezed
sealed class ProcessingProgress with _$ProcessingProgress {
  const factory ProcessingProgress({
    @Default(ProcessingLane.short) ProcessingLane lane,

    /// [done] de [total] —páginas, segundos de audio—; los dos en cero
    /// mientras el trabajo no informó nada.
    @Default(0) int done,
    @Default(0) int total,
  }) = _ProcessingProgress;

  const ProcessingProgress._();

  /// La fracción hecha, de 0 a 1, o `null` si todavía no se sabe cuánto hay.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);
}

/// Qué está haciendo la cola de procesamiento: lo que está en curso —en
/// cualquiera de los dos carriles— con su avance, y cuántos esperan turno.
@freezed
sealed class ProcessingQueueState with _$ProcessingQueueState {
  const factory ProcessingQueueState({
    @Default(<String, ProcessingProgress>{})
    Map<String, ProcessingProgress> active,
    @Default(0) int waiting,
  }) = _ProcessingQueueState;

  const ProcessingQueueState._();

  /// Sin nada en curso ni esperando.
  bool get isIdle => active.isEmpty && waiting == 0;
}
