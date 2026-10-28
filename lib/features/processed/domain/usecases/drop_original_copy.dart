import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

/// Lo que dejó [DropOriginalCopy].
@immutable
class DroppedOriginalCopy {
  const DroppedOriginalCopy({required this.outcome, required this.keptText});

  /// Para «Deshacer».
  final ProcessOutcome outcome;

  /// Si el texto se guardó en la sección Texto porque el documento no la
  /// tenía.
  final bool keptText;
}

/// «Borrar la copia del original, quedarme con el texto» (F41, decisión K):
/// suelta la copia propia del original de un documento procesado (decisión H)
/// y nunca toca el archivo de la fuente, que en la Biblioteca no se borra
/// (decisión G).
///
/// Va por el mismo camino que quitar el original al volver a triar
/// (`ProcessSourceUseCase` con [ProcessedChange.remove]): la copia va a la
/// papelera del contenido, de donde se recupera, y se deshace.
///
/// **El texto se queda, como dice la opción.** Sin sección Texto, el texto
/// propio del documento es el de la fuente que es el de la copia (decisión I):
/// soltarla lo dejaría mudo —sin qué estudiar ni sobre qué estaban marcados su
/// resumen, su síntesis y sus palabras clave—. Así que, en el mismo guardado,
/// el texto de la fuente entra como su sección Texto: es el mismo texto, con
/// las mismas posiciones, y lo estudiado en el documento sigue en su lugar. Si
/// la fuente no tiene texto, no hay qué guardar y solo se suelta la copia.
class DropOriginalCopy {
  const DropOriginalCopy({
    required ProcessedRepository repository,
    required ProcessSourceUseCase process,
  }) : _repository = repository,
       _process = process;

  final ProcessedRepository _repository;
  final ProcessSourceUseCase _process;

  /// Suelta la copia del original del documento de [sourceItemId]. Falla, sin
  /// tocar nada, si el documento no tiene copia o si la fuente ya no está viva
  /// —procesar se arma contra ella—.
  Future<Either<Failure, DroppedOriginalCopy>> call(String sourceItemId) async {
    final documentId = processedDocumentIdFor(sourceItemId);
    final original = await _repository.originalOf(documentId);
    if (original.isLeft()) return left(original.getLeft().toNullable()!);
    if (original.getRight().toNullable() == null) {
      return left(
        const Failure.validation(
          message: 'Este documento no tiene una copia del original.',
        ),
      );
    }

    final material = await _repository.materialOf(
      sourceItemId,
      countWords: false,
    );
    if (material.isLeft()) return left(material.getLeft().toNullable()!);
    final ProcessedDocument? document;
    try {
      document = await _repository.watchDocument(documentId).first;
      // La consulta ya registró su fallo (`watchQuery`).
    } on Object {
      return left(
        const Failure.unexpected(message: 'No se pudo leer el documento.'),
      );
    }
    final hasTextSection =
        (document?.summary.partCounts[ProcessedSection.text] ?? 0) > 0;
    final keepText =
        !hasTextSection && material.getRight().toNullable()!.hasText;

    final outcome = await _process(sourceItemId, {
      if (keepText)
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    }, original: const OriginalEdit(ProcessedChange.remove));
    return outcome.map(
      (outcome) => DroppedOriginalCopy(outcome: outcome, keptText: keepText),
    );
  }
}
