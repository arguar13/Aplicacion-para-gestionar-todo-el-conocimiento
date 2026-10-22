import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

/// Quien marca, en una parte de un documento, las oraciones del resumen, las
/// de la síntesis y las palabras clave (F36): el modelo elegido en Ajustes.
///
/// Interfaz propia, como `SummarizationService`: quien estudia un documento
/// no tiene por qué saber de motores, ventanas ni turnos.
abstract interface class StudyMarker {
  /// Cuántos caracteres de oraciones conviene darle por parte: lo que entra
  /// en la ventana del modelo elegido, con lugar para lo que contesta.
  int get partCharBudget;

  /// Marca [part], las oraciones de [content] que siguen.
  ///
  /// Si el pedido entero no entra en la ventana —el texto cuenta más tokens
  /// de lo común—, analiza solo las primeras: [StudyPartOutcome.analyzed]
  /// dice cuántas, al menos una.
  ///
  /// Lanza si el modelo no está listo o falla —sin conexión, sin cuota—:
  /// quien llama ya comprobó que estaba listo, y lo analizado hasta ahí queda.
  Future<StudyPartOutcome> markPart({
    required String content,
    required List<StudySentence> part,
  });
}

/// Lo que dio una parte: cuántas de sus oraciones se analizaron, desde la
/// primera, y lo que se marcó en ellas —`null` si el modelo no contestó en el
/// formato—.
@immutable
class StudyPartOutcome {
  const StudyPartOutcome({required this.analyzed, required this.marks});

  final int analyzed;
  final StudyPartMarks? marks;
}
