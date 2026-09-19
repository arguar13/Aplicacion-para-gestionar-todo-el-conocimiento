import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las propiedades que el modelo sugirió para una fuente, como chips que se
/// aceptan de un toque y se deshacen con otro.
///
/// Un chip aceptado sigue a la vista, marcado: el repositorio solo entrega las
/// sugerencias *pendientes*, así que la que se acaba de aceptar dejaría de
/// llegar y el chip desaparecería sin dejar volver atrás. Por eso se guardan
/// las que se vieron mientras la tarjeta estuvo abierta.
///
/// Es una tarjeta por fuente: quien lo usa le pone una `key` por elemento, así
/// lo visto y lo aceptado no pasa de una fuente a la siguiente.
class SuggestedPropertyChips extends ConsumerStatefulWidget {
  const SuggestedPropertyChips({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<SuggestedPropertyChips> createState() =>
      _SuggestedPropertyChipsState();
}

class _SuggestedPropertyChipsState
    extends ConsumerState<SuggestedPropertyChips> {
  /// Las sugerencias que se vieron, en el orden en que aparecieron.
  final Map<String, PropertySuggestion> _seen = {};

  /// Las que se aceptaron desde acá.
  final Set<String> _accepted = {};

  /// Las que están a mitad de aceptarse o deshacerse: un segundo toque no las
  /// vuelve a mandar.
  final Set<String> _busy = {};

  Future<void> _toggle(PropertySuggestion suggestion) async {
    if (!_busy.add(suggestion.id)) return;

    final repository = ref.read(suggestionRepositoryProvider);
    final wasAccepted = _accepted.contains(suggestion.id);
    final result = wasAccepted
        ? await repository.revertAccepted(suggestion.id)
        : await repository.accept(suggestion.id);

    _busy.remove(suggestion.id);
    if (!mounted) return;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              failure.localizedMessage(AppLocalizations.of(context)!),
            ),
          ),
        );
      return;
    }

    setState(() {
      if (wasAccepted) {
        _accepted.remove(suggestion.id);
      } else {
        _accepted.add(suggestion.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    for (final suggestion
        in (ref.watch(pendingSuggestionsProvider(widget.itemId)).valueOrNull ??
                const <Suggestion>[])
            .whereType<PropertySuggestion>()) {
      _seen.putIfAbsent(suggestion.id, () => suggestion);
    }
    if (_seen.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.inboxSuggestedProperties,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in _seen.values)
                FilterChip(
                  key: ValueKey('suggested-${suggestion.id}'),
                  label: Text(
                    '${suggestion.definitionName}: ${suggestion.value}',
                  ),
                  selected: _accepted.contains(suggestion.id),
                  onSelected: (_) => _toggle(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
