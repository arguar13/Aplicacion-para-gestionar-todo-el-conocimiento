import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_documents.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_colors.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos documentos se listan en la leyenda: el resto se resume en «y N más».
/// Con cientos de documentos a la vista, una lista entera no sería una
/// leyenda; y cualquiera se encuentra recortando por documento.
const kDocumentLegendRows = 8;

/// Los documentos de [documents] que entran en la leyenda: los de más hechos
/// primero y, a igual cantidad, por título. Los que más pesan en el eje son los
/// que más interesa reconocer.
List<TimelineDocument> legendDocuments(List<TimelineDocument> documents) {
  // Sin distinguir mayúsculas ni acentos, como la hoja de «Documento»; la
  // clave se calcula una vez por documento y no en cada comparación.
  final keys = {
    for (final document in documents)
      document.itemId: normalizeVocabularyLabel(document.title),
  };
  return [...documents]..sort((a, b) {
    final byCount = b.eventCount.compareTo(a.eventCount);
    if (byCount != 0) return byCount;
    final byTitle = keys[a.itemId]!.compareTo(keys[b.itemId]!);
    return byTitle != 0 ? byTitle : a.itemId.compareTo(b.itemId);
  });
}

/// La leyenda de colores por documento (F40): se pliega y se despliega, y dice
/// qué color es de qué documento. Tocar una fila recorta la línea de tiempo a
/// ese documento.
///
/// Plegada ocupa una fila: el título, cuántos documentos son y una muestra de
/// sus colores. Así no le quita lugar al eje de quien ya los reconoce.
class TimelineDocumentLegend extends StatefulWidget {
  const TimelineDocumentLegend({
    required this.documents,
    required this.colors,
    required this.onPick,
    super.key,
  });

  /// Los documentos que se ven, con sus hechos contados, ya en el orden en que
  /// se listan (ver [legendDocuments]): ordenarlos es trabajo de quien los
  /// arma, una vez por lista de hechos, y no de cada vez que se dibuja.
  final List<TimelineDocument> documents;

  final DocumentColors colors;

  /// Se tocó la fila de un documento.
  final ValueChanged<TimelineDocument> onPick;

  @override
  State<TimelineDocumentLegend> createState() => _TimelineDocumentLegendState();
}

class _TimelineDocumentLegendState extends State<TimelineDocumentLegend> {
  bool _expanded = false;

  /// Cuántas muestras de color se asoman con la leyenda plegada.
  static const _previewDots = 6;

  /// Lo más alto que se deja crecer la lista desplegada, para no tapar el eje.
  static const _maxListHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ordered = widget.documents;
    final listed = ordered.take(kDocumentLegendRows).toList();
    final hidden = ordered.length - listed.length;

    final list = !_expanded
        ? const SizedBox(width: double.infinity)
        : ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxListHeight),
            child: ListView(
              key: const ValueKey('timeline-docs-legend-list'),
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                for (final document in listed)
                  _Row(
                    document: document,
                    color: widget.colors.of(document.itemId),
                    onTap: () => widget.onPick(document),
                  ),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      l10n.timelineDocsLegendMore(hidden),
                      key: const ValueKey('timeline-docs-legend-more'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: _expanded
                ? l10n.timelineDocsLegendCollapse
                : l10n.timelineDocsLegendExpand,
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('timeline-docs-legend-toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        l10n.timelineDocsLegendTitle,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.timelineDocsLegendCount(ordered.length),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!_expanded)
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            children: [
                              for (final document in ordered.take(_previewDots))
                                _Dot(color: widget.colors.of(document.itemId)),
                            ],
                          ),
                        )
                      else
                        const Spacer(),
                      Icon(
                        _expanded ? Icons.expand_more : Icons.expand_less,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Sin animaciones (accesibilidad), de golpe: `AnimatedSize` con
          // duración cero no es válido.
          if (MediaQuery.disableAnimationsOf(context))
            list
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: list,
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.surface,
        width: 1.5,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.document,
    required this.color,
    required this.onTap,
  });

  final TimelineDocument document;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Tooltip(
      message: l10n.timelineDocsLegendRowTooltip,
      child: InkWell(
        key: ValueKey('timeline-docs-legend-${document.itemId}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.timelineEventCount(document.eventCount),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
