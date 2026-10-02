import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_source_of.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';
import 'package:sinapsis/features/citations/presentation/citation_presentation.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La cita de una fuente (F15), en el estilo, el idioma y la forma que se
/// elijan: la entrada de la lista, la cita en el texto y —en Chicago— la nota
/// completa y la nota corta.
///
/// Sale de los datos de la referencia con lo que cada estilo pide. Lo que falta
/// se ve resaltado, con el nombre de cada dato, en lugar de inventarse o de
/// callarse. Se copia como texto plano o con las cursivas —Markdown—: el
/// portapapeles de Flutter solo lleva texto plano.
///
/// El estilo y el idioma parten de lo que Ajustes recuerda; elegir otro acá
/// vale para esta vista y no cambia lo predeterminado. La página o el minuto
/// que se escriba se agrega a las formas que citan un pasaje.
class CitationSection extends ConsumerStatefulWidget {
  const CitationSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  ConsumerState<CitationSection> createState() => _CitationSectionState();
}

class _CitationSectionState extends ConsumerState<CitationSection> {
  String? _styleId;
  CitationLanguage? _language;
  var _form = CitationForm.reference;
  final _locator = TextEditingController();

  @override
  void dispose() {
    _locator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reference = ref.watch(referenceProvider(widget.item.id)).valueOrNull;
    // Mientras se lee, no se dibuja: una cita con todo por completar que
    // después se llena sola es un parpadeo de datos falsos.
    if (reference == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = _styleId == null
        ? ref.watch(defaultCitationStyleProvider)
        : kReferenceStyles.resolve(_styleId);
    final defaultLanguage = ref.watch(defaultCitationLanguageProvider);
    final language = _language ?? defaultLanguage;
    // Una forma que el estilo no tiene —«nota» en APA— cae en la entrada.
    final form = style.forms.contains(_form) ? _form : CitationForm.reference;
    final citation = style.format(
      form,
      citationSourceOf(widget.item, reference),
      CitationContext(
        language: language,
        locator: form.takesLocator ? parseLocator(_locator.text) : null,
      ),
    );

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
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              key: const Key('citation-style'),
              value: style.id,
              onChanged: (id) => setState(() => _styleId = id),
              items: [
                for (final option in kReferenceStyles.styles)
                  DropdownMenuItem(
                    value: option.id,
                    child: Text(option.label(l10n)),
                  ),
              ],
            ),
            SegmentedButton<CitationLanguage>(
              key: const Key('citation-language'),
              showSelectedIcon: false,
              segments: [
                for (final option in CitationLanguage.values)
                  ButtonSegment(value: option, label: Text(option.label(l10n))),
              ],
              selected: {language},
              onSelectionChanged: (selection) =>
                  setState(() => _language = selection.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final option in CitationForm.values)
              if (style.forms.contains(option))
                ChoiceChip(
                  key: Key('citation-form-${option.name}'),
                  label: Text(option.label(l10n)),
                  selected: form == option,
                  onSelected: (_) => setState(() => _form = option),
                ),
          ],
        ),
        if (form.takesLocator) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('citation-locator'),
            controller: _locator,
            decoration: InputDecoration(
              labelText: l10n.citationLocatorLabel,
              hintText: l10n.citationLocatorHint,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText.rich(
            key: const Key('citation-text'),
            contextMenuBuilder: buildSelectionMenu,
            citationTextSpan(citation, theme),
          ),
        ),
        if (citation.hasGaps) ...[
          const SizedBox(height: 8),
          Text(
            key: const Key('citation-gaps'),
            l10n.citationMissingData(
              {for (final gap in citation.gaps) gap.label(l10n)}.join(', '),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('citation-copy'),
              onPressed: () => _copy(context, citation.toPlainText()),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.citationCopyAction),
            ),
            TextButton.icon(
              key: const Key('citation-copy-markdown'),
              onPressed: () => _copy(context, citation.toMarkdown()),
              icon: const Icon(Icons.format_italic, size: 18),
              label: Text(l10n.citationCopyMarkdownAction),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.citationCopied)));
  }
}
