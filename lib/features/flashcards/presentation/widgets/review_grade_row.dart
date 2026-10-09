import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/review_interval.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La altura de todos los botones grandes de repasar: calificar, mostrar la
/// respuesta, seguir practicando.
const kReviewButtonHeight = 64.0;

/// El estilo de los botones anchos de repasar —«Mostrar respuesta»,
/// «Comprobar», «Practicar igual»—: la misma forma y altura que los de
/// calificar.
ButtonStyle reviewWideButtonStyle() => FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(kReviewButtonHeight),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

/// El nombre de cada calificación.
String reviewGradeLabel(AppLocalizations l10n, ReviewGrade grade) =>
    switch (grade) {
      ReviewGrade.again => l10n.reviewGradeAgain,
      ReviewGrade.hard => l10n.reviewGradeHard,
      ReviewGrade.good => l10n.reviewGradeGood,
      ReviewGrade.easy => l10n.reviewGradeEasy,
    };

/// Los colores de cada calificación: el fondo y lo que se dibuja encima. Los
/// usan los botones y el aviso al deslizar la tarjeta, así que el color dice
/// lo mismo en los dos lados.
(Color background, Color foreground) reviewGradeColors(
  ColorScheme colors,
  ReviewGrade grade,
) => switch (grade) {
  ReviewGrade.again => (colors.errorContainer, colors.onErrorContainer),
  ReviewGrade.hard => (colors.tertiaryContainer, colors.onTertiaryContainer),
  ReviewGrade.good => (colors.primaryContainer, colors.onPrimaryContainer),
  ReviewGrade.easy => (colors.secondaryContainer, colors.onSecondaryContainer),
};

/// Un ícono para cada calificación, el mismo que se ve al deslizar la tarjeta
/// hacia su lado.
IconData reviewGradeIcon(ReviewGrade grade) => switch (grade) {
  ReviewGrade.again => Icons.replay,
  ReviewGrade.hard => Icons.trending_down,
  ReviewGrade.good => Icons.check,
  ReviewGrade.easy => Icons.bolt,
};

/// Los cuatro botones de calificación del algoritmo SM-2 —iguales sea cual
/// sea la forma de la tarjeta, la calificación es cuánto costó recordar, no
/// algo que la corrección de una opción múltiple pueda decidir sola—.
class ReviewGradeRow extends ConsumerWidget {
  const ReviewGradeRow({
    required this.card,
    required this.grading,
    required this.onGrade,
    super.key,
  });

  final Flashcard card;
  final bool grading;
  final ValueChanged<ReviewGrade> onGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Lo que pasaría con cada respuesta, calculado con el mismo planificador
    // que la aplica de verdad.
    final intervals = previewIntervals(card, now: ref.read(clockProvider)());

    return Row(
      children: [
        for (final grade in ReviewGrade.values) ...[
          Expanded(
            child: _GradeButton(
              key: Key('grade-${grade.name}'),
              grade: grade,
              label: reviewGradeLabel(l10n, grade),
              interval: _intervalText(l10n, intervals[grade]!),
              onPressed: grading ? null : () => onGrade(grade),
            ),
          ),
          if (grade != ReviewGrade.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  String _intervalText(AppLocalizations l10n, ReviewInterval interval) =>
      switch (interval.unit) {
        IntervalUnit.minutes => l10n.reviewIntervalMinutes(interval.count),
        IntervalUnit.hours => l10n.reviewIntervalHours(interval.count),
        IntervalUnit.days => l10n.reviewIntervalDays(interval.count),
        IntervalUnit.weeks => l10n.reviewIntervalWeeks(interval.count),
        IntervalUnit.months => l10n.reviewIntervalMonths(interval.count),
        IntervalUnit.years => l10n.reviewIntervalYears(interval.count),
      };
}

/// Un botón de calificar: el nombre en una sola línea y, debajo, cuándo vuelve
/// la tarjeta.
///
/// Los cuatro miden lo mismo y tienen la misma forma. Antes eran
/// `OutlinedButton`s con el relleno lateral estándar: en un teléfono a cada
/// uno le quedaban unos 40 puntos para el texto, y «De nuevo» se partía letra
/// por letra y estiraba su botón. Acá el texto se achica para entrar antes
/// que partirse, y el color dice de qué se trata antes de leerlo.
class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.grade,
    required this.label,
    required this.interval,
    required this.onPressed,
    super.key,
  });

  final ReviewGrade grade;
  final String label;
  final String interval;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground) = reviewGradeColors(
      Theme.of(context).colorScheme,
      grade,
    );
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.reviewGradeSemantics(label, interval),
      excludeSemantics: true,
      child: Material(
        color: enabled ? background : background.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  unawaited(HapticFeedback.selectionClick());
                  onPressed!();
                }
              : null,
          child: SizedBox(
            height: kReviewButtonHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      interval,
                      maxLines: 1,
                      softWrap: false,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
