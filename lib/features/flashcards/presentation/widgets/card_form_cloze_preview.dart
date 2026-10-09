import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El frente de una tarjeta de huecos, dibujado desde sus [ClozeSegment]: el
/// hueco que se pregunta resaltado (`[...]` o `[pista]`) y los demás ya
/// revelados. Lo usan el formulario, para que se vea cómo queda cada tarjeta
/// mientras se escribe, y la revisión de lo que propone la IA.
class ClozeQuestionText extends StatelessWidget {
  const ClozeQuestionText({required this.segments, this.style, super.key});

  final List<ClozeSegment> segments;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final segment in segments)
            TextSpan(
              text: segment.text,
              style: switch (segment.kind) {
                ClozeSegmentKind.plain => null,
                ClozeSegmentKind.hidden => TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
                ClozeSegmentKind.revealed => const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              },
            ),
        ],
      ),
    );
  }
}

/// Una tarjeta por cada número de hueco de [text], con su frente tal como se va
/// a ver. Sin huecos, no dibuja nada.
class ClozeCardsPreview extends StatelessWidget {
  const ClozeCardsPreview({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cards = parseCloze(text).cards;
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cardFormClozeCount(cards.length),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.cardFormClozeCardTitle(card.number),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClozeQuestionText(segments: card.questionSegments),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
