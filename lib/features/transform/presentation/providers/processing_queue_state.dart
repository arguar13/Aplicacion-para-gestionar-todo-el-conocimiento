import 'package:freezed_annotation/freezed_annotation.dart';

part 'processing_queue_state.freezed.dart';

/// Qué está haciendo la cola de procesamiento.
@freezed
sealed class ProcessingQueueState with _$ProcessingQueueState {
  const factory ProcessingQueueState.idle() = QueueIdle;

  /// Trabajando sobre un elemento, con [remaining] esperando turno.
  const factory ProcessingQueueState.working({
    required String currentItemId,
    required int remaining,
  }) = QueueWorking;
}
