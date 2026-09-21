import 'package:flutter/material.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_coverage.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

extension AtlasCoveragePresentation on AtlasCoverage {
  String label(AppLocalizations l10n) => switch (this) {
    AtlasCoverage.empty => l10n.atlasCoverageEmpty,
    AtlasCoverage.sourcesOnly => l10n.atlasCoverageSourcesOnly,
    AtlasCoverage.fragments => l10n.atlasCoverageFragments,
    AtlasCoverage.growing => l10n.atlasCoverageGrowing,
    AtlasCoverage.mature => l10n.atlasCoverageMature,
  };

  /// El color de las barras llenas: el de las fuentes mientras solo hay
  /// material crudo, y el de las notas desde que hay algo escrito. Es el mismo
  /// criterio con que el resto de la app distingue una fuente de una nota.
  Color color(ColorScheme colors) => this == AtlasCoverage.sourcesOnly
      ? EntityRole.source.accent(colors)
      : EntityRole.note.accent(colors);
}

/// El estado de cobertura de una rama, legible de un vistazo: cuatro barras
/// que se llenan de izquierda a derecha —ninguna es «sin material», las cuatro
/// es «madura»—.
///
/// El estado no depende del color: es CUÁNTAS barras hay llenas, y el nombre
/// va en el tooltip y en la semántica para quien no las ve.
class CoverageMeter extends StatelessWidget {
  const CoverageMeter({required this.coverage, super.key});

  final AtlasCoverage coverage;

  /// Las barras que se pueden llenar: todos los estados menos «sin material».
  static const _bars = 4;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = coverage.label(AppLocalizations.of(context)!);
    final filled = coverage.index;

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _bars; i++)
                Container(
                  width: 7,
                  height: 16,
                  margin: EdgeInsetsDirectional.only(
                    end: i < _bars - 1 ? 2 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: i < filled
                        ? coverage.color(colors)
                        : colors.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La leyenda de los cinco estados: qué significa cada nivel de las barras.
class CoverageLegend extends StatelessWidget {
  const CoverageLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.atlasCoverageTitle,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final coverage in AtlasCoverage.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CoverageMeter(coverage: coverage),
                const SizedBox(width: 6),
                Text(coverage.label(l10n), style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
