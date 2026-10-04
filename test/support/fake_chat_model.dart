// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'dart:async';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';

/// Un modelo de chat de mentira, para las pruebas de pantalla que no están
/// probando `flutter_gemma` en sí.
class FakeChatModel implements ChatModel {
  FakeChatModel({this.response, this.error});

  /// Lo que "contesta" [answer]. Mutable a propósito.
  String? response;

  /// Si está, se lanza en vez de contestar —tanto en [answer] como al
  /// mandar un mensaje de una conversación libre—.
  Object? error;

  /// Cada conversación libre que se arrancó, en orden. Permite comprobar en
  /// las pruebas que una charla reusa la misma sesión entre mensajes, en vez
  /// de abrir una nueva cada vez.
  final conversations = <FakeFreeConversation>[];

  /// Lo mismo, para las conversaciones sobre la bóveda.
  final vaultConversations = <FakeVaultConversation>[];

  /// Si las conversaciones que se arranquen dejan cada respuesta abierta para
  /// que la prueba la escriba (ver [FakeFreeConversation.manual]).
  bool manualReplies = false;

  @override
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  }) async {
    final err = error;
    if (err != null) throw err;
    return response ?? '';
  }

  @override
  Future<FreeConversation> startConversation() async {
    final conversation = FakeFreeConversation(response: response, error: error)
      ..manual = manualReplies;
    conversations.add(conversation);
    return conversation;
  }

  @override
  Future<VaultConversation> startVaultConversation() async {
    final conversation = FakeVaultConversation(response: response, error: error)
      ..manual = manualReplies;
    vaultConversations.add(conversation);
    return conversation;
  }
}

/// Una conversación libre de mentira: devuelve [response] a cada mensaje —o
/// [error] si se puso—, y guarda todo lo que se le mandó.
class FakeFreeConversation implements FreeConversation {
  FakeFreeConversation({this.response, this.error});

  String? response;
  Object? error;

  /// Cada mensaje que se mandó con [send], en orden.
  final sent = <String>[];

  /// Las imágenes que acompañaron a cada mensaje, en el mismo orden que
  /// [sent].
  final sentImages = <List<Uint8List>>[];

  bool closed = false;

  /// Si es `true`, cada respuesta queda abierta en [replies] para que la
  /// prueba la escriba de a pedazos, la termine o le meta un error.
  bool manual = false;

  /// Las respuestas abiertas, con [manual].
  final replies = <StreamController<String>>[];

  @override
  ChatReplyStream send(String message, {List<Uint8List> images = const []}) {
    sent.add(message);
    sentImages.add(images);
    return _reply(response, error, manual ? replies : null);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Una conversación sobre la bóveda de mentira: devuelve [response] a cada
/// mensaje —o [error] si se puso—, y guarda todo lo que se le mandó, mensaje
/// y fuentes por separado.
class FakeVaultConversation implements VaultConversation {
  FakeVaultConversation({this.response, this.error});

  String? response;
  Object? error;

  /// Cada mensaje que se mandó con [send], en orden.
  final sent = <String>[];

  /// Las fuentes que acompañaron a cada mensaje, en el mismo orden que
  /// [sent].
  final sentSources = <List<ChatSource>>[];

  /// Las imágenes que acompañaron a cada mensaje, en el mismo orden que
  /// [sent].
  final sentImages = <List<Uint8List>>[];

  bool closed = false;

  /// Ver [FakeFreeConversation.manual].
  bool manual = false;

  /// Ver [FakeFreeConversation.replies].
  final replies = <StreamController<String>>[];

  @override
  ChatReplyStream send({
    required String message,
    required List<ChatSource> sources,
    List<Uint8List> images = const [],
  }) {
    sent.add(message);
    sentSources.add(sources);
    sentImages.add(images);
    return _reply(response, error, manual ? replies : null);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Una respuesta de mentira, como la da el modelo: el texto creciendo hasta
/// [response] —en dos pedazos—, o [error]. Con [open], queda abierta ahí
/// para que la prueba la maneje.
ChatReplyStream _reply(
  String? response,
  Object? error,
  List<StreamController<String>>? open,
) {
  if (open != null) {
    final controller = StreamController<String>();
    open.add(controller);
    return controller.stream;
  }
  if (error != null) return Stream.error(error);
  final text = response ?? '';
  final half = text.length ~/ 2;
  return Stream.fromIterable([if (half > 0) text.substring(0, half), text]);
}
