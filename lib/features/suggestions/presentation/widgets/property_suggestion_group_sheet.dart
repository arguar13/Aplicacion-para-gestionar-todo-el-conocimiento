import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/property_suggestion_action_bar.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/property_suggestion_batch_actions.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/property_suggestion_group_tile.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre, sobre la pantalla actual, los demás elementos a los que el modelo les
/// sugiere lo mismo que a [excludeItemId]: «14 elementos más parecen ser
/// `Región: Roma`».
///
/// Es una hoja y no una pantalla a propósito: quien está triando una fuente por
/// vez no tiene que dejar la Bandeja para aplicar una sugerencia a catorce
/// elementos de golpe. La tarjeta sigue debajo, en su lugar, y al cerrar la
/// hoja —con lo aplicado, con lo descartado o sin nada— es la misma.
///
/// El grupo se identifica por [definitionId] y [normalizedValue], la misma
/// clave con la que la revisión en lote agrupa, y [excludeItemId] es el
/// elemento de la tarjeta: el que se está mirando se decide con sus chips, no
/// acá.
Future<void> showPropertySuggestionGroupSheet(
  BuildContext context, {
  required String definitionId,
  required String normalizedValue,
  String? excludeItemId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => PropertySuggestionGroupSheet(
    definitionId: definitionId,
    normalizedValue: normalizedValue,
    excludeItemId: excludeItemId,
  ),
);

/// El contenido de la hoja: el grupo, con sus elementos a la vista para marcar
/// uno por uno, y la barra para aceptar o descartar lo marcado.
///
/// El lote acelera la confirmación, no la quita: arranca sin nada marcado y
/// cada elemento se ve, con su título y el comienzo de su texto, antes de
/// aceptarlo. Se actualiza solo —lo que se resolvió desde otro lado sale de la
/// lista— porque mira el mismo flujo que la pantalla del lote.
class PropertySuggestionGroupSheet extends ConsumerStatefulWidget {
  const PropertySuggestionGroupSheet({
    required this.definitionId,
    required this.normalizedValue,
    this.excludeItemId,
    super.key,
  });

  final String definitionId;
  final String normalizedValue;
  final String? excludeItemId;

  @override
  ConsumerState<PropertySuggestionGroupSheet> createState() =>
      _PropertySuggestionGroupSheetState();
}

class _PropertySuggestionGroupSheetState
    extends ConsumerState<PropertySuggestionGroupSheet> {
  final _selected = <String>{};
  var _busy = false;

  /// Por qué no se pudo aplicar, si no se pudo. Adentro de la hoja y no en un
  /// aviso: la barrera de una hoja modal tapa los avisos de la pantalla de
  /// abajo.
  String? _error;

  Future<void> _apply(List<String> ids, {required bool accept}) async {
    final repository = ref.read(suggestionRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });

    final count = await applyPropertySuggestionBatch(
      context: context,
      repository: repository,
      ids: ids,
      accept: accept,
      onFailure: (message) => _error = message,
    );
    if (!mounted) return;

    // Aplicado: la hoja se cierra y el aviso —con su «Deshacer»— queda a la
    // vista en la pantalla de abajo. Si no, la selección queda para reintentar.
    if (count != null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final groups =
        ref.watch(pendingPropertySuggestionGroupsProvider).valueOrNull ??
        const [];
    final group = groups
        .where(
          (g) =>
              g.definitionId == widget.definitionId &&
              g.normalizedValue == widget.normalizedValue,
        )
        .firstOrNull;
    final others = [
      if (group != null)
        for (final s in group.suggestions)
          if (s.targetItemId != widget.excludeItemId) s,
    ];
    // Una sugerencia que ya se resolvió sale de la lista: no puede seguir
    // marcada.
    final selected = _selected.intersection({for (final s in others) s.id});

    if (group == null || others.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Center(child: Text(l10n.suggestionReviewEmpty)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${group.definitionName}: ${group.value}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.suggestionReviewHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: PropertySuggestionGroupTile(
              group: group.copyWith(suggestions: others),
              selected: selected,
              enabled: !_busy,
              initiallyExpanded: true,
              onToggleGroup: (select) => setState(() {
                for (final s in others) {
                  if (select) {
                    _selected.add(s.id);
                  } else {
                    _selected.remove(s.id);
                  }
                }
              }),
              onToggleOne: ({required id, required marked}) => setState(() {
                if (marked) {
                  _selected.add(id);
                } else {
                  _selected.remove(id);
                }
              }),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              _error!,
              key: const ValueKey('group-sheet-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (selected.isNotEmpty)
          PropertySuggestionActionBar(
            count: selected.length,
            busy: _busy,
            onAccept: () => _apply(selected.toList(), accept: true),
            onReject: () => _apply(selected.toList(), accept: false),
          ),
      ],
    );
  }
}
