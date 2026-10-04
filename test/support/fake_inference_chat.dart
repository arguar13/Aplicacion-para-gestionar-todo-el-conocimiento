import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una sesión de `flutter_gemma` de mentira: anota lo que recibe y contesta
/// de a pedazos, como el modelo de verdad (`generateChatResponseAsync`).
///
/// Por defecto contesta «respuesta N de la sesión I», en tres pedazos. Con
/// [answer] se elige qué contesta a cada pedido; con [gated] cada pedazo
/// espera a que la prueba lo suelte ([releasePiece]), para ver lo que pasa a
/// mitad de una respuesta.
class FakeInferenceChat extends Fake implements InferenceChat {
  FakeInferenceChat({
    this.id = 1,
    this.answer,
    this.gated = false,
    this.tokensPerPiece = 1,
    this.failAfter,
  });

  final int id;

  /// Los pedazos de la respuesta a un pedido: recibe su número y su texto.
  final List<String> Function(int turn, String prompt)? answer;

  /// Si cada pedazo espera a [releasePiece].
  final bool gated;

  /// Cuántos tokens cuenta cada pedazo.
  final int tokensPerPiece;

  /// Si está, el motor falla después de dar estos pedazos.
  final int? failAfter;

  /// Lo que se le mandó, en orden: un texto por pedido.
  final received = <String>[];

  /// Cuántas fotos llegaron, entre todos los pedidos.
  int imagesReceived = 0;

  bool closed = false;
  int stopRequests = 0;
  var _stopped = false;
  var _tokens = 0;
  final _pending = StringBuffer();
  final _pieceGate = StreamController<void>();
  late final _pieces = StreamIterator(_pieceGate.stream);

  /// Si está generando ahora.
  bool generating = false;

  /// Deja salir el próximo pedazo de una respuesta [gated].
  void releasePiece() => _pieceGate.add(null);

  @override
  int get currentTokens => _tokens;

  @override
  ModelType get modelType => ModelType.gemma4;

  @override
  ModelFileType get fileType => ModelFileType.litertlm;

  @override
  Future<void> addQueryChunk(
    Message message, [
    bool noTool = false,
    bool prefix = false,
  ]) async {
    if (closed) throw StateError('sesión cerrada');
    _pending.write(message.text);
    imagesReceived += message.images.length;
  }

  @override
  Stream<ModelResponse> generateChatResponseAsync() async* {
    if (closed) throw StateError('sesión cerrada');
    final prompt = _pending.toString();
    _pending.clear();
    received.add(prompt);
    final turn = received.length;
    final pieces =
        answer?.call(turn, prompt) ??
        ['respuesta ', '$turn ', 'de la sesión $id'];
    _stopped = false;
    generating = true;
    try {
      var given = 0;
      for (final piece in pieces) {
        if (gated) await _pieces.moveNext();
        if (_stopped || closed) break;
        if (given == failAfter) throw StateError('falla del motor');
        _tokens += tokensPerPiece;
        given++;
        yield TextResponse(piece);
      }
    } finally {
      generating = false;
    }
  }

  @override
  Future<void> stopGeneration() async {
    stopRequests++;
    _stopped = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    unawaited(_pieceGate.close());
  }
}
