import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que tiene marcado un original, en un renglón chico debajo de su vista
/// previa (F45, paso 7b, mejora 15): «Marcado: ● Resumen · ● Palabras
/// clave». Las fichas donde se marca van adentro del original, a pantalla
/// completa; acá queda a la vista qué hay, sin abrirlo.
///
/// - Cada clase marcada lleva **su punto de color**, el mismo de su ficha:
///   lleno a la vista, hueco si se dejó oculta.
/// - **Mientras la IA marca**, lo dice con su avance: lo que antes era la
///   franja de la barra, que se para adentro.
/// - **Sin nada marcado**, dice dónde se marca.
///
/// El mismo en el documento de Procesado, sobre su copia, y en el detalle de
/// una fuente de la Biblioteca, sobre la fuente: cada uno mira lo suyo
/// ([OriginalStudy]).
class OriginalMarksLine extends ConsumerWidget {
  const OriginalMarksLine({required this.study, super.key});

  final OriginalStudy study;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = StudyPalette.of(theme.brightness);
    final soft = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(color: soft);
    final key = study.original.renditionId;
    final view = ref.watch(studyViewProvider(key));
    final marks =
        ref.watch(documentStudyProvider(key)).valueOrNull ??
        DocumentStudy.notStarted;
    final analysis = ref.watch(studyAnalysisProvider(study.ownKey));
    final marked = [
      for (final kind in StudyMarkKind.values)
        if (marks.of(kind).isNotEmpty) kind,
    ];

    final String said;
    final List<Widget> shown;
    if (analysis case StudyAnalysisRunning(:final progress)) {
      said = l10n.f45S7bMarksWorking(progress?.percent ?? 0);
      shown = [Text(said, style: style)];
    } else if (marked.isEmpty) {
      said = l10n.f45S7bMarksNone;
      shown = [Text(said, style: style)];
    } else {
      String named(StudyMarkKind kind) {
        final name = originalStudyName(l10n, kind);
        return originalShows(view, kind) ? name : l10n.f45S7bMarksHidden(name);
      }

      final names = [for (final kind in marked) named(kind)];
      said = l10n.f45S7bMarksSaid(names.join(', '));
      shown = [
        Text(l10n.f45S7bMarksLead, style: style),
        for (final (index, kind) in marked.indexed)
          Row(
            key: Key('original-marks-${kind.name}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0) Text(' · ', style: style),
              _Dot(
                color: originalStudyColor(palette, kind),
                hollow: !originalShows(view, kind),
              ),
              const SizedBox(width: 4),
              // Con la letra grande, un nombre que no entra en el renglón se
              // parte en vez de salirse.
              Flexible(
                child: Text(originalStudyName(l10n, kind), style: style),
              ),
            ],
          ),
      ];
    }

    return Semantics(
      key: const Key('original-marks-line'),
      container: true,
      label: said,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.border_color_outlined, size: 16, color: soft),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: shown,
            ),
          ),
        ],
      ),
    );
  }
}

/// El punto de color de una clase marcada: el de su resaltador, hueco si
/// está oculta.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.hollow});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? null : color,
      border: Border.all(color: color, width: 2),
    ),
  );
}
