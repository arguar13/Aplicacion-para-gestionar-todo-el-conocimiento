import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// De qué cola sale la tarjeta que toca (F31, decisión 69).
enum StudyQueueKind {
  /// Una que se aprende o reaprende y ya volvió (o está por volver).
  learning,

  /// Un repaso en días que venció.
  review,

  /// Una tarjeta nueva, dentro del límite de nuevas de hoy.
  newCard,
}

/// Qué sigue en una sesión de estudio. Es lo que devuelve
/// `StudyRepository.next` y se llama de nuevo tras cada respuesta: el estado
/// vive en la base, no en la pantalla, así que una sesión se puede retomar tal
/// cual.
sealed class StudyNext {
  const StudyNext();
}

/// Toca esta tarjeta.
@immutable
class StudyNextCard extends StudyNext {
  const StudyNextCard({
    required this.card,
    required this.queue,
    this.early = false,
  });

  final Flashcard card;
  final StudyQueueKind queue;

  /// Se la trae antes de su hora (por el margen de `learnAhead`): no es que
  /// ya venció, es que no hay otra cosa y falta poco.
  final bool early;
}

/// Por ahora no hay nada, pero vuelve una tarjeta en aprendizaje más tarde
/// hoy: la sesión espera hasta [until], o termina.
///
/// Quien muestra la sesión decide entre esperar (`next` de nuevo al llegar
/// [until]), ofrecer «seguir ya» (`next` con `learnAhead` suficiente) o cerrar
/// con un aviso claro: «volvé en 8 minutos».
@immutable
class StudyNextWait extends StudyNext {
  const StudyNextWait({
    required this.until,
    required this.learningLeft,
    this.newBeyondLimit = 0,
    this.reviewsBeyondLimit = 0,
  });

  /// Cuándo vuelve la primera tarjeta en aprendizaje.
  final DateTime until;

  /// Cuántas tarjetas en aprendizaje vuelven hoy.
  final int learningLeft;

  /// Lo que quedó fuera de hoy por los límites (ver [StudyNextDone]).
  final int newBeyondLimit;
  final int reviewsBeyondLimit;
}

/// No queda nada para estudiar hoy en este recorte.
@immutable
class StudyNextDone extends StudyNext {
  const StudyNextDone({this.newBeyondLimit = 0, this.reviewsBeyondLimit = 0});

  /// Nuevas que siguen sin hacerse porque se llegó al límite de hoy. Si es
  /// mayor que 0, el aviso correcto es «llegaste al límite de hoy», no «no hay
  /// nada».
  final int newBeyondLimit;

  /// Repasos vencidos que quedaron fuera por el límite.
  final int reviewsBeyondLimit;

  /// Si se cortó por un límite y no porque se acabó.
  bool get hitLimit => newBeyondLimit > 0 || reviewsBeyondLimit > 0;
}
