import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto de una tarjeta de huecos (F31, ola 2): lo de siempre en texto
/// común, el hueco que se pregunta como una marca `[...]` (o con su pista) y,
/// ya dada la vuelta, la respuesta resaltada.
class ReviewClozeText extends StatelessWidget {
  const ReviewClozeText({required this.segments, this.style, super.key});

  final List<ClozeSegment> segments;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? Theme.of(context).textTheme.titleLarge;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final segment in segments)
            switch (segment.kind) {
              ClozeSegmentKind.plain => TextSpan(text: segment.text),
              // El hueco que se pregunta: una marca visible, que no se
              // confunde con el texto.
              ClozeSegmentKind.hidden => TextSpan(
                text: segment.text,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  backgroundColor: scheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              // La respuesta: negrita y color, y fondo, para que no dependa
              // solo del color.
              ClozeSegmentKind.revealed => TextSpan(
                text: segment.text,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                  backgroundColor: scheme.primaryContainer,
                ),
              ),
            },
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// El resultado de comparar lo escrito con la respuesta correcta (F31, ola 2):
/// un veredicto, lo que la persona escribió con lo que sobra marcado, y la
/// respuesta correcta con lo que faltó marcado.
///
/// Un «casi» (un descuido de tipeo) no cuenta solo como acierto ni como error:
/// se muestra la diferencia y la persona califica.
class ReviewTypedResult extends StatelessWidget {
  const ReviewTypedResult({required this.result, super.key});

  final TypedAnswerResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (IconData icon, Color color, String verdict) = switch (result) {
      TypedAnswerResult(isBlank: true) => (
        Icons.edit_off_outlined,
        scheme.onSurfaceVariant,
        l10n.reviewSessionTypedBlank,
      ),
      TypedAnswerResult(verdict: TypedAnswerVerdict.match) => (
        Icons.check_circle_outline,
        scheme.primary,
        l10n.reviewSessionTypedMatch,
      ),
      TypedAnswerResult(verdict: TypedAnswerVerdict.close) => (
        Icons.rule,
        scheme.tertiary,
        l10n.reviewSessionTypedClose,
      ),
      _ => (
        Icons.cancel_outlined,
        scheme.error,
        l10n.reviewSessionTypedMismatch,
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                verdict,
                key: const Key('review-typed-verdict'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
        if (!result.isBlank) ...[
          const SizedBox(height: 12),
          _Labeled(
            label: l10n.reviewSessionTypedYours,
            child: Text.rich(
              key: const Key('review-typed-yours'),
              TextSpan(
                children: [
                  for (final segment in result.typedSegments)
                    TextSpan(
                      text: segment.typedText,
                      style: segment.kind == TypedAnswerSegmentKind.extra
                          ? TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.lineThrough,
                              backgroundColor: scheme.errorContainer.withValues(
                                alpha: 0.6,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Labeled(
          label: l10n.reviewSessionTypedExpected,
          child: Text.rich(
            key: const Key('review-typed-expected'),
            TextSpan(
              children: [
                for (final segment in result.expectedSegments)
                  TextSpan(
                    text: segment.expectedText,
                    style: segment.kind == TypedAnswerSegmentKind.missing
                        ? TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            backgroundColor: scheme.primaryContainer,
                          )
                        : null,
                  ),
              ],
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}
