import 'dart:async';

import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';

/// Quien escribe el JSON, de mentira (F43, paso 9): pasa cada pedido por la
/// orquestación de verdad (`runStructuredRequest`: de una vez o por partes,
/// la corrección, el avance, la cancelación) y contesta cada vuelta con
/// [reply], sin ninguna IA. Anota los pedidos y las vueltas.
class FakeStructuredWriter implements StructuredWriter {
  FakeStructuredWriter(this.reply, {this.contextTokens = 100000});

  /// Lo que contesta cada vuelta (la número `index`, desde 0).
  final FutureOr<String> Function(StructuredCall call, int index) reply;

  @override
  final int contextTokens;

  final requests = <StructuredRequest<Object?>>[];
  final calls = <StructuredCall>[];

  /// Si está, cada vuelta lo espera antes de contestar.
  Completer<void>? hold;

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) {
    requests.add(request);
    return runStructuredRequest(request, (call) async {
      final index = calls.length;
      calls.add(call);
      final gate = hold;
      if (gate != null) await gate.future;
      return reply(call, index);
    });
  }
}
