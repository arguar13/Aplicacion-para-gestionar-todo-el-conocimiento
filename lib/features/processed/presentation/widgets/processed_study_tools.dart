import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organized_line.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/widgets/scope_creations_section.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/graph/presentation/widgets/local_graph_panel.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';

/// Dónde se estudia un documento procesado, al final, después de leerlo: lo
/// que salió del detalle de la fuente, que queda de consulta (F41, decisión
/// K), y lo que se creó con él en Repasar (F43, M6).
///
/// Son las piezas de siempre sobre el documento —un elemento de la bóveda
/// como cualquier otro (decisión A)—, sin copias:
///
/// - **«En Repasar»** (`ScopeCreationsSection`): lo creado con el documento
///   —también desde un cuaderno o un tema que lo usó como fuente—, sus
///   tarjetas para hoy con «Empezar», y «Crear en Repasar», que abre Repasar
///   con el documento ya elegido. Va primero porque es el puente entre lo que
///   se marcó en el original, arriba, y lo que se estudia; y queda justo
///   encima de las tarjetas que cuenta;
/// - **el Mapa**, el grafo local del documento (`LocalGraphPanel`), con sus
///   vínculos entre procesados;
/// - **las Tarjetas de repaso** (`FlashcardSection`): las suyas, a mano o con
///   IA de su propio texto, y, plegadas en «De la fuente», las que la fuente
///   ya tenía.
///
/// En la papelera no se ven: el documento se lee y se restaura, pero no se
/// estudia hasta que vuelve. Lo dice el elemento mismo —`libraryItemProvider`
/// sirve solo lo vivo—, sin una regla aparte que pudiera contradecirlo.
class ProcessedStudyTools extends ConsumerWidget {
  const ProcessedStudyTools({required this.document, super.key});

  final ProcessedDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(libraryItemProvider(document.id)).valueOrNull;
    if (item == null) return const SizedBox.shrink();

    return Column(
      key: const Key('processed-study-tools'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        ScopeCreationsSection(scope: CreationScope.document(document.id)),
        const SizedBox(height: 24),
        LocalGraphPanel(item: item),
        const SizedBox(height: 24),
        FlashcardSection(
          item: item,
          processed: true,
          fromSourceItemId: document.summary.sourceItemId,
        ),
      ],
    );
  }
}

/// Lo que la IA organizó con el documento procesado (F41, decisión K): la
/// misma línea que tenía la fuente —«Para revisar», «Ver», «Deshacer todo»,
/// «Revisar con otro modelo»—, en su tarjeta, sobre lo que la IA hizo con lo
/// procesado. Lo que organizó en la fuente no se borra: queda guardado allá.
///
/// Solo cuando hay algo que contar (`AiItemSummary.isVisible`).
class ProcessedAiLine extends ConsumerWidget {
  const ProcessedAiLine({required this.document, super.key});

  final ProcessedDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(aiItemSummaryProvider(document.id));
    if (!summary.isVisible) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const Key('processed-ai-line'),
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: AiOrganizedLine(
          itemId: document.id,
          itemTitle: document.title,
          summary: summary,
        ),
      ),
    );
  }
}
