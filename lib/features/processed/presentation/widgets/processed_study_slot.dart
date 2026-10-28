import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';

/// La tarjeta de estudiar de siempre (`StudyDocumentCard`: «Resumir con» el
/// modelo elegido o «Elegir a mano», la leyenda con sus colores, el avance y
/// «Extraer» con el resumen, la síntesis y las palabras clave para leer y
/// escuchar), sobre el texto propio del documento procesado (F41, decisión I)
/// —`processedStudyTextProvider`: su sección Texto o la copia del original—.
///
/// Es acá donde se estudia lo procesado (decisión K): en la fuente, la misma
/// tarjeta solo marca el original. Sin texto propio —un documento con solo
/// notas o fragmentos— no hay qué estudiar y no se muestra.
///
/// La misma tarjeta, no una copia: lo que se aprenda a hacer en ella vale
/// igual para una fuente y para lo procesado.
class ProcessedStudySlot extends ConsumerWidget {
  const ProcessedStudySlot({required this.document, super.key});

  final ProcessedDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = ref
        .watch(processedStudyTextProvider(document.id))
        .valueOrNull
        ?.getOrElse((_) => null);
    if (own == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StudyDocumentCard(
        text: own.asStudyText,
        kind: document.summary.sourceKind,
      ),
    );
  }
}
