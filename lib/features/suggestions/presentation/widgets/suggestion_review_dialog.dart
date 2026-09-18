import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Muestra el diálogo de revisión y aplica —vía
/// `SuggestionRepository.accept`— las sugerencias que queden tildadas al
/// confirmar. Las que no se tildaron quedan `pending`, sin tocar: se
/// pueden revisar de nuevo después, no se rechazan por cerrar el diálogo.
///
/// Recibe el repositorio ya resuelto, no un `WidgetRef`: quien llama
/// —`_PendingItemCard`— puede desmontarse mientras el diálogo está
/// abierto (transiciona el elemento a `triaged` antes de mostrarlo, y eso
/// lo saca de la Bandeja), y un `ref` atado a ese widget deja de servir
/// en cuanto se desmonta. El repositorio, en cambio, sigue siendo válido
/// durante todo el tiempo que el diálogo esté en pantalla.
Future<void> showSuggestionReviewDialog(
  BuildContext context, {
  required SuggestionRepository repository,
  required List<Suggestion> suggestions,
}) async {
  final accepted = await showDialog<List<Suggestion>>(
    context: context,
    builder: (context) => _SuggestionReviewDialog(suggestions: suggestions),
  );
  if (accepted == null || accepted.isEmpty) return;

  for (final suggestion in accepted) {
    await repository.accept(suggestion.id);
  }
}

/// Revisar lo que propuso el modelo antes de aplicar nada: cada sugerencia
/// se puede aceptar o dejar de lado por separado —mismo patrón que
/// `_FlashcardDraftReviewDialog`/`_AiSuggestionsDialog`—, sin estado de
/// carga: las sugerencias ya están persistidas, no se piden en vivo al
/// abrir este diálogo.
class _SuggestionReviewDialog extends StatefulWidget {
  const _SuggestionReviewDialog({required this.suggestions});

  final List<Suggestion> suggestions;

  @override
  State<_SuggestionReviewDialog> createState() =>
      _SuggestionReviewDialogState();
}

class _SuggestionReviewDialogState extends State<_SuggestionReviewDialog> {
  late final _accepted = List<bool>.filled(widget.suggestions.length, true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.suggestionsReviewDialogTitle),
      content: SizedBox(
        width: 400,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = widget.suggestions[index];
            final (title, subtitle, icon, color) = switch (suggestion) {
              PropertySuggestion() => (
                '${suggestion.definitionName}: ${suggestion.value}',
                suggestion.isNewValue ? l10n.suggestionsNewValueBadge : null,
                Icons.sell_outlined,
                null,
              ),
              RelationSuggestionEntry() => (
                suggestion.kind.describe(
                  l10n,
                  direction: RelationDirection.outgoing,
                  otherItemTitle: suggestion.relatedItemTitle,
                ),
                suggestion.reason,
                suggestion.kind.icon,
                suggestion.kind.color(Theme.of(context).colorScheme),
              ),
            };

            return CheckboxListTile(
              value: _accepted[index],
              onChanged: (value) =>
                  setState(() => _accepted[index] = value ?? false),
              secondary: Icon(icon, color: color),
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop([
            for (var i = 0; i < widget.suggestions.length; i++)
              if (_accepted[i]) widget.suggestions[i],
          ]),
          child: Text(l10n.suggestionsApplySelected),
        ),
      ],
    );
  }
}
