import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/processed/domain/services/processed_study_layout.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';

/// El texto propio de un documento procesado, para estudiarlo en él (decisión
/// I): sus páginas de «Texto», una detrás de la otra, o —sin «Texto», con la
/// copia del original— el texto de la fuente, que es el de la copia.
///
/// Se estudia con la máquina de siempre (F36, F39) dándole [asStudyText]: su
/// `renditionId` es la clave del procesado ([key], `processedStudyKeyFor`), y
/// el `StudyRepository` de la app la reconoce y guarda lo estudiado en el
/// procesado —como partes propias—, no en `study_marks` de la fuente.
@immutable
class ProcessedStudyText {
  const ProcessedStudyText({
    required this.key,
    required this.documentId,
    required this.content,
    required this.markdown,
    required this.layout,
  });

  /// La clave de estudio: ver `processedStudyKeyFor`.
  final String key;
  final String documentId;

  /// El texto entero.
  final String content;

  /// Si [content] es Markdown, como el de su fuente.
  final bool markdown;

  /// Cómo se corresponde con el texto de la fuente.
  final ProcessedStudyLayout layout;

  /// Lo que se le da a la tarjeta de estudiar, al lector y a la máquina de
  /// estudiar.
  StudyText get asStudyText => (
    itemId: documentId,
    renditionId: key,
    content: content,
    markdown: markdown,
  );
}
