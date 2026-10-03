import 'package:sinapsis/core/domain/entities/ai_certainty.dart';

/// Qué tan seguro es un vínculo que propone la IA, y qué se hace con él
/// (F27, decisión B: lo seguro se aplica solo, lo dudoso va a «Para
/// revisar»).
///
/// Dos señales, ninguna suficiente sola:
///
/// - **El parecido medido**: el coseno entre los centros de los embeddings
///   de los dos elementos (`RelationCandidateSelector`). Es una medida, pero
///   de tema compartido, no de vínculo: dos textos sobre Roma se parecen
///   aunque uno no diga nada del otro.
/// - **Lo que dice el modelo de lenguaje**: la certeza que declara
///   ([AiCertainty]). Juzga el vínculo en sí, pero un modelo chico se
///   equivoca con aplomo.
///
/// Por eso se combinan, y pesa más el modelo —es el que mira el vínculo—,
/// pero nunca alcanza solo: con la certeza más alta igual hace falta un
/// parecido real para aplicar. Los números son el punto de partida, para
/// ajustar con la medición en el teléfono (paso 8 del plan): por ahora no hay
/// cosenos medidos de EmbeddingGemma sobre una biblioteca real.
double relationConfidence({required double cosine, AiCertainty? certainty}) {
  final measured =
      ((cosine - kRelationCosineFloor) /
              (kRelationCosineCeiling - kRelationCosineFloor))
          .clamp(0.0, 1.0);
  final declared = switch (certainty) {
    AiCertainty.high => 1.0,
    AiCertainty.medium => 0.5,
    AiCertainty.low => 0.0,
    // Un modelo que no siguió el formato pedido merece un poco menos que
    // «media»: tampoco se sabe si leyó bien el resto.
    null => 0.4,
  };
  return kRelationModelWeight * declared +
      (1 - kRelationModelWeight) * measured;
}

/// Qué hacer con un vínculo de confianza [confidence].
RelationVerdict relationVerdictFor(double confidence) {
  if (confidence >= kAutoApplyRelationConfidence) return RelationVerdict.apply;
  if (confidence >= kReviewRelationConfidence) return RelationVerdict.review;
  return RelationVerdict.discard;
}

enum RelationVerdict {
  /// Se crea solo, marcado como de la IA.
  apply,

  /// Queda en «Para revisar» como sugerencia pendiente.
  review,

  /// No se propone: ni siquiera vale el toque de descartarlo.
  discard,
}

/// El coseno desde el que un candidato llega al modelo: el mismo umbral con
/// el que lo preselecciona `RelationCandidateSelector` (`minSimilarity`). Acá
/// vale cero.
const kRelationCosineFloor = 0.5;

/// El coseno desde el que el parecido ya no suma: más arriba son casi el
/// mismo texto, y eso es un duplicado, no un vínculo más seguro.
const kRelationCosineCeiling = 0.8;

/// Cuánto pesa lo que dice el modelo frente al parecido medido.
const kRelationModelWeight = 0.6;

/// Desde acá se aplica solo. Con certeza «alta» hace falta un coseno de al
/// menos 0,6125; con «media», o sin decir nada, no se llega nunca: lo que el
/// modelo no afirma con claridad no se aplica sin que la persona lo vea.
const kAutoApplyRelationConfidence = 0.75;

/// Desde acá, y por debajo de [kAutoApplyRelationConfidence], va a «Para
/// revisar». Con «media» hace falta el mismo coseno de 0,6125; con «baja» no
/// se llega nunca. Más abajo se descarta: una bandeja llena de dudas flojas
/// se deja de mirar.
const kReviewRelationConfidence = 0.45;
