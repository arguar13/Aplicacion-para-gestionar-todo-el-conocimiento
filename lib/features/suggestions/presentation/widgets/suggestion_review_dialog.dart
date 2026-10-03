import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' show Either, left, right;
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/i18n/category_label.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Muestra el diálogo de revisión y aplica —vía
/// `SuggestionRepository.accept`— las sugerencias que queden tildadas al
/// confirmar. Las que no se tildaron quedan `pending`, sin tocar: se
/// pueden revisar de nuevo después, no se rechazan por cerrar el diálogo.
///
/// Devuelve `null` si se cerró sin confirmar, cuántas se aplicaron si se
/// confirmó, o el primer fallo si alguna no se pudo aplicar —esa queda
/// `pending`, para reintentar—. Quien llama decide con eso si la revisión se
/// completó: la Bandeja tría la fuente solo entonces (F28), y no al abrir el
/// diálogo.
///
/// Recibe el repositorio ya resuelto, no un `WidgetRef`: quien llama puede
/// desmontarse mientras el diálogo está abierto, y un `ref` atado a ese
/// widget deja de servir en cuanto se desmonta. El repositorio, en cambio,
/// sigue siendo válido durante todo el tiempo que el diálogo esté en
/// pantalla.
Future<Either<Failure, int>?> showSuggestionReviewDialog(
  BuildContext context, {
  required SuggestionRepository repository,
  required List<Suggestion> suggestions,
}) async {
  final accepted = await showDialog<List<Suggestion>>(
    context: context,
    builder: (context) => _SuggestionReviewDialog(suggestions: suggestions),
  );
  if (accepted == null) return null;

  // Una que falla no frena a las demás: lo tildado se aplica todo lo que se
  // pueda, y la que falló queda `pending` para otra vuelta.
  Failure? firstFailure;
  for (final suggestion in accepted) {
    final result = await repository.accept(suggestion.id);
    firstFailure ??= result.getLeft().toNullable();
  }
  return firstFailure == null ? right(accepted.length) : left(firstFailure);
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
                '${categoryValueLabel(l10n, suggestion.definitionName)}: '
                    '${suggestion.value}',
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
              // El Atlas (F27): el tema con su padre delante, y la madurez.
              TopicParentSuggestion() => (
                '${suggestion.parentName} › ${suggestion.valueName}',
                null,
                Icons.account_tree_outlined,
                null,
              ),
              MaturitySuggestion() => (
                '${suggestion.from.label(l10n)} → '
                    '${suggestion.to.label(l10n)}',
                l10n.noteMaturityChangeTooltip,
                Icons.trending_up,
                suggestion.to.color(Theme.of(context).colorScheme),
              ),
              // Nunca deberían llegar hasta acá: un duplicado pide su propia
              // confirmación explícita —la pantalla "Posibles duplicados"
              // (D4, F7)— porque fusionar borra un elemento, y una sugerencia
              // de referencia (F15) tiene su propia tarjeta, con el
              // formulario ya precargado, en vez de un casillero con un
              // título y un subtítulo. Quien arma la lista que llega a este
              // diálogo es quien debe dejarlas afuera (ver `InboxScreen`).
              DuplicateSuggestionEntry() => throw StateError(
                'Un duplicado no debería llegar al diálogo de revisión '
                'genérico.',
              ),
              MetadataSuggestion() => throw StateError(
                'Una sugerencia de referencia no debería llegar al diálogo '
                'de revisión genérico.',
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
