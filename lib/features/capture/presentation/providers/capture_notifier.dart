import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_state.dart';

class CaptureNotifier extends StateNotifier<CaptureState> {
  CaptureNotifier({
    required CaptureItemUseCase captureItem,
    required AppLogger logger,
  }) : _captureItem = captureItem,
       _logger = logger,
       super(const CaptureState.idle());

  final CaptureItemUseCase _captureItem;
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
      CaptureRequest(rawInput: rawInput, title: title, note: note),
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
        return true;
      },
    );
  }
}

final captureNotifierProvider =
    StateNotifierProvider.autoDispose<CaptureNotifier, CaptureState>((ref) {
      return CaptureNotifier(
        captureItem: ref.watch(captureItemUseCaseProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });
