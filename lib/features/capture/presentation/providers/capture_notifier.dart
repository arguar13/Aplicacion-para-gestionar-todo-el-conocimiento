import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_state.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';

class CaptureNotifier extends StateNotifier<CaptureState> {
  CaptureNotifier({
    required CaptureItemUseCase captureItem,
    required ProcessingQueueNotifier queue,
    required AppLogger logger,
  }) : _captureItem = captureItem,
       _queue = queue,
       _logger = logger,
       super(const CaptureState.idle());

  final CaptureItemUseCase _captureItem;
  final ProcessingQueueNotifier _queue;
  final AppLogger _logger;

  /// Guarda lo capturado. Devuelve si salió bien, para que la pantalla sepa
  /// si corresponde cerrarse.
  Future<bool> capture({
    required String rawInput,
    String? title,
    String? note,
  }) async {
    state = const CaptureState.saving();

    final result = await _captureItem(
      CaptureRequest.text(rawInput: rawInput, title: title, note: note),
    );

    return result.match(
      (failure) {
        _logger.error('No se pudo guardar la captura.', failure);
        state = CaptureState.failed(failure);
        return false;
      },
      (item) {
        state = const CaptureState.idle();
        _logger.info('Guardado: ${item.id}');

        // Se encola para traerle el contenido, sin esperar a que termine: lo
        // que el usuario capturó ya está guardado y la pantalla puede
        // cerrarse. El resultado aparece solo en la lista cuando llegue.
        _queue.enqueue(item.id);
        return true;
      },
    );
  }
}

final captureNotifierProvider =
    StateNotifierProvider.autoDispose<CaptureNotifier, CaptureState>((ref) {
      return CaptureNotifier(
        captureItem: ref.watch(captureItemUseCaseProvider),
        queue: ref.watch(processingQueueProvider.notifier),
        logger: ref.watch(appLoggerProvider),
      );
    });
