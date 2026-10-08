import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';

part 'flashcard.freezed.dart';

/// Una tarjeta de repaso: pregunta, respuesta, y el estado de repetición
/// espaciada que decide cuándo volver a mostrarla.
///
/// El estado SM-2 vive en la entidad y no en un servicio aparte porque es
/// justamente lo que se guarda: la tarjeta *es* su historial de repasos, no
/// solo su contenido.
@freezed
sealed class Flashcard with _$Flashcard {
  const factory Flashcard({
    required String id,
    required String itemId,
    required String front,
    required String back,
    required DateTime dueAt,
    required DateTime createdAt,
    @Default(2.5) double easeFactor,
    @Default(0) int intervalDays,
    @Default(0) int repetitions,
    DateTime? lastReviewedAt,

    /// La forma de la tarjeta (F20): `freeRecall` para toda tarjeta de
    /// antes de F20 y para las que se siguen creando a mano. El programador
    /// SM-2 y `review_log` no lo leen —repasan y registran por igual—: es
    /// la presentación la que cambia según el valor.
    @Default(FlashcardKind.freeRecall) FlashcardKind kind,

    /// El fragmento de la fuente del que salió la tarjeta (F11): el rango de
    /// caracteres de la forma principal del elemento, y el chunk que lo
    /// contiene. `null` en las tarjetas escritas a mano y en las que ya
    /// existían.
    ///
    /// El rango es lo que vale para volver a la fuente: el id de un chunk
    /// desaparece cuando el texto se rehace y sus chunks se reemplazan; el
    /// rango sigue señalando el mismo lugar mientras el texto no cambie.
    String? sourceChunkId,
    int? sourceCharStart,
    int? sourceCharEnd,

    /// Cuándo se exportó por última vez a un `.apkg` con éxito (F17, D4).
    /// `null` en una tarjeta que nunca entró en una exportación: es lo que
    /// el camino incremental usa para decidir qué es «nuevo».
    DateTime? lastExportedAt,

    /// Quién la hizo (F27). Una de la IA que la persona edita pasa a ser
    /// suya: editarla es adoptarla, y «deshacer todo» ya no se la lleva.
    @Default(ContentOrigin.user) ContentOrigin origin,

    /// La pasada de la IA que la creó. `null` en las de la persona.
    String? aiRunId,

    /// Pausada (F31): no entra en ninguna sesión hasta que se la reactive; su
    /// calendario no se toca.
    @Default(false) bool suspended,

    /// Pospuesta hasta esta fecha (F31): no entra en ninguna sesión mientras
    /// sea futura. `null` = no está pospuesta.
    DateTime? buriedUntil,

    /// El paso de aprendizaje en el que está (F31): `null` = no se aprende ni
    /// se reaprende (nueva, o en repaso por días); 0 = el primer paso, 1 = el
    /// segundo. Ver [phase].
    int? learningStep,

    /// Las hermanas (F31): las tarjetas de un mismo grupo —las dos direcciones
    /// de una pregunta, los huecos de un texto— comparten este id y no se
    /// estudian el mismo día. `null` = sin hermanas.
    String? groupId,

    /// En una tarjeta `cloze`, cuál hueco tapa (desde 1). `null` en las demás.
    int? clozeIndex,
  }) = _Flashcard;

  const Flashcard._();

  /// Si se sabe de qué fragmento de la fuente salió.
  bool get hasSourceRange => sourceCharStart != null && sourceCharEnd != null;

  /// Si sigue siendo de la IA.
  bool get isFromAi => origin == ContentOrigin.ai;

  /// Si ya toca repasarla.
  bool isDue(DateTime now) => !dueAt.isAfter(now);

  /// En qué etapa del calendario está (F31). Se DEDUCE de los campos, sin una
  /// columna propia, para que lo programado antes de F31 tenga etapa sin
  /// migrarse:
  ///
  /// - con [learningStep]: se aprende (si nunca se graduó: intervalo 0) o se
  ///   reaprende (si ya tuvo intervalo y se olvidó);
  /// - sin paso, sin intervalo, sin repeticiones y sin haberse contestado
  ///   nunca: nueva;
  /// - todo lo demás: en repaso por días. Incluye la tarjeta de antes de F31
  ///   a la que le dijeron «De nuevo» (intervalo 1, repeticiones 0).
  CardPhase get phase {
    if (learningStep != null) {
      return intervalDays == 0 ? CardPhase.learning : CardPhase.relearning;
    }
    if (repetitions == 0 && intervalDays == 0 && lastReviewedAt == null) {
      return CardPhase.newCard;
    }
    return CardPhase.review;
  }

  /// Si está en un paso corto (se aprende o se reaprende): vuelve en minutos.
  bool get isInLearningSteps => learningStep != null;

  /// Si la pospusieron y todavía no llegó el momento de volver a verla.
  bool isBuriedAt(DateTime now) => buriedUntil?.isAfter(now) ?? false;
}
