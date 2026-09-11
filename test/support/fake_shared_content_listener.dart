import 'dart:async';

import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/services/shared_content_listener.dart';

/// Entrega lo que el test le ponga, sin un sistema operativo real del otro
/// lado.
class FakeSharedContentListener implements SharedContentListener {
  FakeSharedContentListener({List<CaptureRequest> initial = const []})
    : _initial = initial;

  /// Lo que devuelve [initial]. Solo se lee una vez, al construirse el
  /// controller que escucha esto —igual que pasa con el plugin de
  /// verdad—, así que alcanza con fijarlo al armar la prueba.
  final List<CaptureRequest> _initial;

  final _controller = StreamController<List<CaptureRequest>>.broadcast();

  @override
  Future<List<CaptureRequest>> initial() async => _initial;

  @override
  Stream<List<CaptureRequest>> get stream => _controller.stream;

  /// Simula que algo llega mientras la app ya está abierta.
  void add(List<CaptureRequest> requests) => _controller.add(requests);

  void dispose() => unawaited(_controller.close());
}
