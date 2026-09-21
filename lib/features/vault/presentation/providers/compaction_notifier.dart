import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/services/vault_compactor.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_state.dart';

/// Lleva una compactación de la bóveda y traduce cómo termina a
/// [CompactionState].
class CompactionNotifier extends StateNotifier<CompactionState> {
  CompactionNotifier({
    required VaultCompactor compactor,
    required AppLogger logger,
  }) : _compactor = compactor,
       _logger = logger,
       super(const CompactionState.idle());

  final VaultCompactor _compactor;
  final AppLogger _logger;

  CompactionCancellation? _cancellation;

  /// Empieza. Si ya hay una en curso no hace nada: dos compactaciones a la vez
  /// sobre la misma conexión no tienen sentido.
  Future<void> start() async {
    if (state is CompactionRunning) return;

    final cancellation = _cancellation = CompactionCancellation();
    state = const CompactionState.running(
      CompactionProgress(CompactionPhase.checking),
    );

    try {
      final result = await _compactor.compact(
        onProgress: _onProgress,
        cancellation: cancellation,
      );
      _set(CompactionState.finished(result));
    } on VaultCompactionNoSpaceException catch (e) {
      _set(CompactionState.noSpace(e.assessment));
    } on VaultCompactionVerificationException catch (e) {
      _logger.error('La bóveda compactada no coincide con la de antes.', e);
      _set(CompactionState.verificationFailed(e.problem));
    } on VaultCompactionFailedException catch (e) {
      _logger.error('No se pudo compactar la bóveda.', e.cause);
      _set(const CompactionState.failed());
    } on Object catch (e, stackTrace) {
      // Lo que ni el compactador previó —medir el espacio, por ejemplo—: la
      // pantalla no puede quedarse mostrando un avance que ya no existe.
      _logger.error('Falló compactando la bóveda.', e, stackTrace);
      _set(const CompactionState.failed());
    } finally {
      _cancellation = null;
    }
  }

  /// Pide parar. Solo lo atiende el compactador en las fases que lo admiten;
  /// pedirlo en otra no hace nada.
  void cancel() => _cancellation?.cancel();

  /// Vuelve a la pantalla de antes de empezar: después de un fallo, o de un
  /// resultado ya visto.
  void reset() {
    if (state is CompactionRunning) return;
    state = const CompactionState.idle();
  }

  void _onProgress(CompactionProgress progress) {
    if (mounted && state is CompactionRunning) {
      state = CompactionState.running(progress);
    }
  }

  /// La pantalla puede haberse ido mientras compactaba —la conexión no se
  /// detiene por eso—: no se le escribe a un estado que ya no existe.
  void _set(CompactionState next) {
    if (mounted) state = next;
  }
}
