import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';

/// Una pregunta que otra pantalla le pasa al chat (F43): «Preguntarle al chat
/// sobre esto» desde una idea del mapa mental. El chat la toma apenas se
/// abre —o en el acto, si ya estaba abierto—: arranca una conversación nueva
/// con la bóveda, acotada a [notebookId] si se pidió sobre un cuaderno, y la
/// manda.
@immutable
class ChatHandoff {
  const ChatHandoff({
    required this.question,
    this.notebookId,
    this.send = true,
  });

  /// Lo que se pregunta, ya escrito.
  final String question;

  /// El cuaderno al que se acota la pregunta; `null`, toda la bóveda.
  final String? notebookId;

  /// Si se manda sola; si no, queda en el campo para retocarla.
  final bool send;

  @override
  bool operator ==(Object other) =>
      other is ChatHandoff &&
      other.question == question &&
      other.notebookId == notebookId &&
      other.send == send;

  @override
  int get hashCode => Object.hash(question, notebookId, send);

  @override
  String toString() => 'ChatHandoff(«$question», cuaderno: $notebookId)';
}

/// La pregunta que espera al chat; `null` si no hay ninguna. La deja quien
/// pregunta ([askInChat]) y la vacía el chat al tomarla.
///
/// No es `autoDispose`: la pregunta tiene que esperar a que el chat se arme,
/// si todavía no se había abierto nunca.
final chatHandoffProvider = StateProvider<ChatHandoff?>((ref) => null);

/// Lleva [handoff] al chat y lo abre. `go` y no `push`: el chat es un destino
/// de la barra, y apilarlo encima de otra pantalla armaría un segundo shell.
void askInChat(BuildContext context, ChatHandoff handoff) {
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(chatHandoffProvider.notifier).state = handoff;
  context.go(RoutePaths.chat);
}
