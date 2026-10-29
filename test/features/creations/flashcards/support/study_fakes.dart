import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Un modelo de mentira detrás del pedido de JSON de verdad
/// (`runStructuredRequest`): cada vuelta le pregunta a [reply] qué contestar,
/// así la tolerancia, la corrección de una respuesta rota, el avance y la
/// cancelación son los de la app.
class FakeModelWriter implements StructuredWriter {
  FakeModelWriter(this.reply, {this.contextTokens = 100000});

  /// Lo que contesta el modelo a cada vuelta.
  FutureOr<String> Function(StructuredCall call) reply;

  @override
  final int contextTokens;

  /// Cada vuelta que se le pidió, en orden.
  final calls = <StructuredCall>[];

  /// Cada pedido, en orden.
  final requests = <StructuredRequest<Object?>>[];

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) {
    requests.add(request);
    return runStructuredRequest(request, (call) async {
      calls.add(call);
      return reply(call);
    });
  }
}

/// [replies] en orden, una por vuelta; la última se repite.
FutureOr<String> Function(StructuredCall) inOrder(List<String> replies) {
  var next = 0;
  return (_) => replies[next < replies.length ? next++ : replies.length - 1];
}

/// Un dibujante de mentira: «dibuja» cada una con su ruta de siempre
/// (`originales/<creación>/ilustraciones/<clave>.png`) o, a partir de la
/// [failFrom] (desde 0), falla con [failure] y no pide más —como una cuenta
/// que no puede—; anota lo que se le pidió.
class FakeIllustrator {
  FakeIllustrator({this.failure, this.failFrom = 0, this.account = 'Personal'});

  final ImageFailure? failure;
  final int failFrom;
  final String account;
  final prompts = <String>[];
  final accounts = <String?>[];
  final creations = <String>[];

  /// Si se la cancela mientras dibuja la ilustración [holdAt].
  int? holdAt;

  Future<StudyIllustrations> illustrate({
    required String creationId,
    required List<(String key, String prompt)> wanted,
    required CancellationSignal cancellation,
    String? accountId,
    void Function(int done, int total)? onDrawn,
  }) async {
    creations.add(creationId);
    final references = <String, String>{};
    for (final (index, (key, prompt)) in wanted.indexed) {
      onDrawn?.call(index, wanted.length);
      prompts.add(prompt);
      accounts.add(accountId);
      if (holdAt == index) {
        await cancellation.whenCancelled;
        throw const CreationCancelledException();
      }
      if (failure case final failure? when index >= failFrom) {
        return StudyIllustrations(
          references: references,
          failure: failure,
          account: account,
        );
      }
      references[key] = 'originales/$creationId/ilustraciones/$key.png';
    }
    return StudyIllustrations(references: references, account: account);
  }

  StudyIllustrator get asIllustrator => illustrate;
}

/// Un PNG chiquito de verdad, distinto por [seed].
Uint8List tinyPng([int seed = 0]) {
  final image = img.Image(width: 4, height: 3)
    ..clear(img.ColorRgb8(10 + seed * 20 % 200, 120, 200));
  return img.encodePng(image);
}

/// El JSON de un mazo con [count] tarjetas, como lo contestaría la IA.
String deckReply(
  int count, {
  String title = 'Éxodo en tarjetas',
  String prefix = 'Qué pasa en',
  bool illustrated = false,
  String? source,
}) => jsonEncode({
  'titulo': title,
  'tarjetas': [
    for (var i = 1; i <= count; i++)
      {
        'frente': '¿$prefix el paso $i?',
        'dorso': 'Respuesta $i.',
        if (i == 1) 'pista': 'Pensá en el mar.',
        'fuente': ?source,
        if (illustrated) 'icono': 'history',
        if (illustrated && i.isOdd) 'ilustracion': 'A sea parting, $i',
      },
  ],
});
