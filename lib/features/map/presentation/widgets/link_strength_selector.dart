import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué vínculos mostrar en la vista «Vínculos» del Mapa según cuánto pesan
/// (F39, paso 8): los más fuertes, los menos fuertes o todos, en el mismo
/// estilo de chips horizontales que el selector de grado del grafo
/// (`DegreeSelector`).
class LinkStrengthSelector extends StatelessWidget {
  const LinkStrengthSelector({
    required this.strength,
    required this.onChanged,
    super.key,
  });

  final LinkStrengthFilter strength;
  final ValueChanged<LinkStrengthFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final labels = {
      LinkStrengthFilter.strongest: l10n.mapLinksStrengthStrongest,
      LinkStrengthFilter.weakest: l10n.mapLinksStrengthWeakest,
      LinkStrengthFilter.all: l10n.mapLinksStrengthAll,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                l10n.mapLinksStrengthLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final option in labels.keys)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: ValueKey('map-links-strength-${option.name}'),
                  label: Text(labels[option]!),
                  selected: strength == option,
                  onSelected: (_) => onChanged(option),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
