import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/i18n/category_label.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/reference/presentation/widgets/metadata_suggestion_banner.dart';
import 'package:sinapsis/features/suggestions/domain/entities/pending_review_item.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Aparece y se va plegándose y fundiéndose (F27): lo que se acepta o se
/// descarta no desaparece de golpe, se cierra, y lo de abajo sube sin saltar.
///
/// Se pliega ANTES de que la base confirme —la fila ya está resuelta para la
/// persona—, y cuando la sugerencia sale de la lista ya no ocupa lugar.
class AiCollapse extends StatelessWidget {
  const AiCollapse({required this.visible, required this.child, super.key});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 260),
      sizeCurve: Curves.easeOutCubic,
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeIn,
      crossFadeState: visible
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstChild: child,
      secondChild: const SizedBox(width: double.infinity),
    );
  }
}

/// El encabezado de «Para revisar»: cuántas hay, de dónde salen y las dos
/// acciones en lote.
class AiReviewHeader extends StatelessWidget {
  const AiReviewHeader({
    required this.count,
    required this.onAcceptAll,
    required this.onDiscardAll,
    super.key,
  });

  final int count;
  final VoidCallback? onAcceptAll;
  final VoidCallback? onDiscardAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.aiReviewTitle, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              // El número cambia al aceptar o descartar: se funde, no salta.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Badge(
                  key: ValueKey(count),
                  backgroundColor: scheme.tertiary,
                  textColor: scheme.onTertiary,
                  label: Text('$count'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.aiReviewHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                key: const Key('ai-review-accept-all'),
                onPressed: onAcceptAll,
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(l10n.aiReviewAcceptAll),
              ),
              TextButton.icon(
                key: const Key('ai-review-discard-all'),
                onPressed: onDiscardAll,
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(l10n.aiReviewDiscardAll),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lo que espera revisión de un elemento: su título —que lo abre— y una fila
/// por sugerencia, con aceptar y descartar de un toque.
///
/// Decodifica sus sugerencias recién cuando se construye: en una lista larga,
/// solo las tarjetas que están en pantalla le preguntan a la base.
class AiReviewItemCard extends ConsumerWidget {
  const AiReviewItemCard({
    required this.item,
    required this.hidden,
    required this.onAccept,
    required this.onDiscard,
    this.onOpen,
    super.key,
  });

  final PendingReviewItem item;

  /// Las sugerencias ya resueltas para la persona —aceptadas, descartadas o
  /// esperando el «Deshacer» de un lote— que la base todavía no sacó.
  final Set<String> hidden;
  final ValueChanged<Suggestion> onAccept;
  final ValueChanged<Suggestion> onDiscard;

  /// Abre el elemento; `null` si ya se está mirando solo ese.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final suggestions = ref.watch(itemReviewSuggestionsProvider(item.itemId));
    final rows = suggestions.valueOrNull ?? const <Suggestion>[];
    final anyVisible =
        !suggestions.hasValue || rows.any((s) => !hidden.contains(s.id));

    return AiCollapse(
      visible: anyVisible,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          key: Key('ai-review-item-${item.itemId}'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.itemTitle,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onOpen != null)
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
              for (final suggestion in rows)
                AiCollapse(
                  key: ValueKey(suggestion.id),
                  visible: !hidden.contains(suggestion.id),
                  child: _ReviewRow(
                    suggestion: suggestion,
                    onAccept: () => onAccept(suggestion),
                    onDiscard: () => onDiscard(suggestion),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.suggestion,
    required this.onAccept,
    required this.onDiscard,
  });

  final Suggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, color, title, detail) = switch (suggestion) {
      RelationSuggestionEntry(
        :final kind,
        :final relatedItemTitle,
        :final reason,
      ) =>
        (
          kind.icon,
          kind.color(scheme),
          kind.describe(
            l10n,
            direction: RelationDirection.outgoing,
            otherItemTitle: relatedItemTitle,
          ),
          reason.trim().isEmpty ? null : reason,
        ),
      PropertySuggestion(
        :final definitionName,
        :final value,
        :final isNewValue,
      ) =>
        (
          Icons.sell_outlined,
          scheme.secondary,
          '${categoryValueLabel(l10n, definitionName)}: $value',
          isNewValue ? l10n.suggestionsNewValueBadge : null,
        ),
      MetadataSuggestion(:final extracted) => (
        Icons.menu_book_outlined,
        scheme.secondary,
        l10n.aiReviewMetadataTitle,
        extractedMetadataSummary(l10n, extracted),
      ),
      // El Atlas (F27): el tema, ya con el padre delante, como se lee en el
      // árbol; y la madurez, de cuál a cuál.
      TopicParentSuggestion(:final parentName, :final valueName) => (
        Icons.account_tree_outlined,
        scheme.secondary,
        '$parentName › $valueName',
        null,
      ),
      MaturitySuggestion(:final from, :final to) => (
        Icons.trending_up,
        to.color(scheme),
        '${from.label(l10n)} → ${to.label(l10n)}',
        l10n.noteMaturityChangeTooltip,
      ),
      // Nunca llega: `itemReviewSuggestionsProvider` los deja afuera.
      DuplicateSuggestionEntry() => throw StateError(
        'Un duplicado no se revisa en «Para revisar»: tiene su pantalla.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: Key('ai-review-discard-${suggestion.id}'),
            tooltip: l10n.aiReviewDiscard,
            onPressed: onDiscard,
            icon: const Icon(Icons.close),
          ),
          IconButton.filledTonal(
            key: Key('ai-review-accept-${suggestion.id}'),
            tooltip: l10n.aiReviewAccept,
            onPressed: onAccept,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
    );
  }
}
