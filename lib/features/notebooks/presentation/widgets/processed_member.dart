/// Cómo se ve un documento procesado dentro de un cuaderno (F41, paso 5): el
/// ícono de la fuente de la que salió, su título y los chips de las partes que
/// tiene, con los nombres de «Procesado» (`ProcessedSectionPresentation`). Lo
/// usan el detalle del cuaderno y el selector para agregar, así se ven iguales
/// en los dos y como en la pantalla Procesado.
library;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dice el lector de pantalla de [document]: su título, de qué era y
/// qué partes tiene, en una sola frase.
String processedMemberSemantics(
  AppLocalizations l10n,
  ProcessedDocumentSummary document,
) => l10n.notebookMemberSemantics(
  document.title,
  document.sourceKind.label(l10n),
  [for (final section in document.sections) section.label(l10n)].join(', '),
);

/// El ícono de la fuente de origen, en su círculo: un procesado es lo que la
/// persona sacó de una fuente, así que lleva el color de las notas.
class ProcessedOriginBadge extends StatelessWidget {
  const ProcessedOriginBadge({required this.document, super.key});

  final ProcessedDocumentSummary document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CircleAvatar(
        backgroundColor: scheme.tertiaryContainer,
        foregroundColor: scheme.onTertiaryContainer,
        child: Icon(document.sourceKind.icon, size: 20),
      ),
    );
  }
}

/// Los chips de las partes que tiene [document], en el orden en que se leen.
/// Son para mirar, no para tocar: van sin semántica propia, que la fila ya la
/// dice entera ([processedMemberSemantics]).
class ProcessedPartChips extends StatelessWidget {
  const ProcessedPartChips({required this.document, super.key});

  final ProcessedDocumentSummary document;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExcludeSemantics(
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final section in document.sections)
            DecoratedBox(
              key: Key('processed-part-${document.id}-${section.name}'),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  section.label(l10n),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
