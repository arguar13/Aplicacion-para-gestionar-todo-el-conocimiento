import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Hasta cuántos saltos de distancia mostrar desde la semilla del grafo:
/// 0, 1, 2 o sin techo, en un estilo horizontal desplazable, en el grafo
/// local (`LocalGraphScreen`).
class DegreeSelector extends StatelessWidget {
  const DegreeSelector({
    required this.degree,
    required this.onChanged,
    super.key,
  });

  final int? degree;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
                l10n.graphDegreeLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final option in const [0, 1, 2, null])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(option == null ? l10n.graphDegreeAll : '$option'),
                  selected: degree == option,
                  onSelected: (_) => onChanged(option),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
