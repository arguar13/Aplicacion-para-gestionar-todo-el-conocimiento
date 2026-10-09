import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_row.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/my_cards_formatting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto mide cada renglón de la lista: el mismo para todos, así la lista
/// sabe dónde cae cada tarjeta sin medirlas y con 10.000 saltar a la mitad no
/// cuesta nada. Crece con el tamaño de letra del sistema: el renglón tiene
/// cuatro líneas de texto (dos de frente y dos de datos) y un margen que no
/// escala.
double myCardsRowExtent(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return 20 + 84 * scale.clamp(1.0, 2.5);
}

/// Un renglón de «Mis tarjetas» (F31, ola 2, decisión 72): el frente, la etapa,
/// el intervalo, el vencimiento y la forma. Al elegir, deja de abrir el editor
/// y marca o desmarca.
class MyCardsRow extends StatelessWidget {
  const MyCardsRow({
    required this.row,
    required this.now,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final CardBrowserRow row;
  final DateTime now;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final card = row.card;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final shape = cardShapeLabel(l10n, card);
    final facts = <String>[
      cardStageLabel(l10n, card),
      if (card.intervalDays > 0) l10n.myCardsInterval(card.intervalDays),
      cardDueLabel(l10n, card, now),
      if (card.isBuriedAt(now)) l10n.myCardsStageBuried,
      if (row.lapses > 0) l10n.myCardsLapses(row.lapses),
    ];

    return Semantics(
      selected: selected,
      child: SizedBox(
        height: myCardsRowExtent(context),
        child: Material(
          color: selected
              ? theme.colorScheme.secondaryContainer
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: Key('my-cards-check-${card.id}'),
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        cardKindIcon(card.kind),
                        color: card.suspended
                            ? theme.colorScheme.outline
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cardListTitle(card),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: card.suspended
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          facts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                        Text(
                          shape == null
                              ? row.itemTitle
                              : '$shape · ${row.itemTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ],
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

/// El lugar de un renglón que todavía no llegó: del mismo alto, para que la
/// lista no salte al cargar.
class MyCardsRowPlaceholder extends StatelessWidget {
  const MyCardsRowPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: myCardsRowExtent(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              width: 220,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 10,
              width: 140,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
