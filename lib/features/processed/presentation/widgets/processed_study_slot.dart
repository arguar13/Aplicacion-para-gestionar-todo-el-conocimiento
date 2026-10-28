import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';

/// El texto con el que se estudia un documento procesado por sí solo
/// (F41, decisión I): su sección Texto o la copia del original, para que
/// «Resumir», «Sintetizar» y «Palabras clave» trabajen sobre lo procesado
/// aunque la fuente nunca se haya estudiado. `null` mientras no se pueda.
///
/// Es el punto por el que entra el paso 1b: los datos —dónde se guarda lo
/// estudiado del procesado y cómo cae en sus secciones Resumen, Síntesis y
/// Palabras clave— son suyos. Hasta entonces no hay texto que estudiar y la
/// tarjeta no se muestra; cuando lo haya, la pantalla la muestra sola.
final processedStudyTextProvider = Provider.autoDispose
    .family<StudyText?, String>((ref, documentId) => null);

/// La tarjeta de estudiar de siempre (`StudyDocumentCard`: «Resumir con» el
/// modelo elegido o «Elegir a mano», la leyenda con sus colores, el avance),
/// sobre el texto del documento procesado —ver [processedStudyTextProvider]—.
///
/// La misma tarjeta, no una copia: lo que se aprenda a hacer en ella vale
/// igual para una fuente y para lo procesado.
class ProcessedStudySlot extends ConsumerWidget {
  const ProcessedStudySlot({required this.document, super.key});

  final ProcessedDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(processedStudyTextProvider(document.id));
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StudyDocumentCard(text: text, kind: document.summary.sourceKind),
    );
  }
}
