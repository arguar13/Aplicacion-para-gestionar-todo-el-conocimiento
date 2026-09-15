import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_style.dart';
import 'package:sinapsis/features/citations/domain/services/citation_formatter.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La cita bibliográfica de un elemento, en el estilo que se elija, con un
/// botón para copiarla.
///
/// Estado local nada más —qué estilo está elegido—: no hace falta
/// recordarlo entre sesiones ni compartirlo con otra pantalla, así que no
/// amerita un provider.
class CitationSection extends StatefulWidget {
  const CitationSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  State<CitationSection> createState() => _CitationSectionState();
}

class _CitationSectionState extends State<CitationSection> {
  var _style = CitationStyle.apa;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final citation = formatCitation(widget.item, _style);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.citationTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CitationStyle>(
          segments: const [
            ButtonSegment(value: CitationStyle.apa, label: Text('APA')),
            ButtonSegment(value: CitationStyle.mla, label: Text('MLA')),
            ButtonSegment(
              value: CitationStyle.chicago,
              label: Text('Chicago'),
            ),
          ],
          selected: {_style},
          onSelectionChanged: (selection) =>
              setState(() => _style = selection.first),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(citation, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _copy(context, citation),
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.citationCopyAction),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String citation) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: citation));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.citationCopied)));
  }
}
