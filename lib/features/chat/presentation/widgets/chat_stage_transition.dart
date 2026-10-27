import 'package:flutter/material.dart';

/// Cuánto tarda el paso entre el vacío y la conversación (F42).
const kChatStageTransition = Duration(milliseconds: 360);

/// El paso suave entre el vacío que recibe y la conversación (F42): al mandar
/// el primer mensaje el saludo se desvanece y la conversación sube apenas
/// mientras aparece; con ✎, al revés. El brillo del fondo se va y vuelve con
/// el mismo fundido.
///
/// [inConversation] decide qué se ve: cambiar de una conversación a otra no
/// es un cambio de escena —la lista es la misma y comparte su desplazamiento—,
/// así que no se funde. Con «sin animaciones», el cambio es de una.
class ChatStageTransition extends StatelessWidget {
  const ChatStageTransition({
    required this.inConversation,
    required this.child,
    this.slide = true,
    super.key,
  });

  final bool inConversation;
  final Widget child;

  /// Si además de fundirse, lo que entra sube un poco: sí para el contenido,
  /// no para el brillo del fondo, que solo se funde.
  final bool slide;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : kChatStageTransition,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final faded = FadeTransition(opacity: animation, child: child);
        if (!slide) return faded;
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation),
          child: faded,
        );
      },
      child: KeyedSubtree(
        key: ValueKey(inConversation ? 'chat-conversation' : 'chat-welcome'),
        child: child,
      ),
    );
  }
}
