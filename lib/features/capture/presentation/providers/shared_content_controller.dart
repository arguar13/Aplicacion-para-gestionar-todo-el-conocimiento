import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/services/shared_content_listener.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';

/// Encola lo que llega de [SharedContentListener] hasta que la pantalla de
/// captura pueda ofrecerlo.
///
/// Encolar y no guardar directo es a propósito: todo lo demás que entra a la
/// app pasa por una revisión antes de quedar guardado —el usuario ve "se va
/// a guardar como X" y aprieta un botón—, y lo que llega compartido no tiene
/// por qué ser la excepción. La cola existe porque el sistema puede entregar
/// varias cosas de una vez —varias fotos elegidas juntas—, y acá se revisan
/// de a una, igual que el resto de la app procesa de a una.
class SharedContentController extends StateNotifier<List<CaptureRequest>> {
  SharedContentController({required SharedContentListener listener})
    : _listener = listener,
      super(const []) {
    unawaited(_loadInitial());
    _subscription = _listener.stream.listen(_enqueue);
  }

  final SharedContentListener _listener;
  late final StreamSubscription<List<CaptureRequest>> _subscription;

  Future<void> _loadInitial() async {
    _enqueue(await _listener.initial());
  }

  void _enqueue(List<CaptureRequest> requests) {
    if (requests.isEmpty) return;
    state = [...state, ...requests];
  }

  /// Lo próximo por revisar, sacándolo de la cola. `null` si no hay nada
  /// pendiente.
  ///
  /// Se consume al mostrarlo y no al guardarlo: así, si el usuario vuelve
  /// atrás sin guardar, lo compartido no reaparece la próxima vez que entre
  /// a la pantalla de captura por cualquier otro motivo —tocando el botón
  /// de siempre, por ejemplo.
  CaptureRequest? takeNext() {
    if (state.isEmpty) return null;

    final next = state.first;
    state = state.skip(1).toList();
    return next;
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// Deliberadamente NO autoDispose: tiene que seguir escuchando aunque la
/// pantalla de captura no esté montada, para no perder lo que llegue
/// mientras el usuario está mirando la biblioteca.
final sharedContentControllerProvider =
    StateNotifierProvider<SharedContentController, List<CaptureRequest>>((ref) {
      return SharedContentController(
        listener: ref.watch(sharedContentListenerProvider),
      );
    });
