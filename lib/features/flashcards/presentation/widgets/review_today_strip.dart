import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_empty_state.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Para hoy», compacto (F43, decisiones B y K): una sola franja con las tres
/// cifras —nuevas, aprendiendo, por repasar— y «Empezar», debajo de «Lo
/// creado» en Repasar, contando lo del recorte elegido.
///
/// Con letra grande o en una pantalla angosta, lo que no entra en una fila
/// baja a la siguiente: nunca se corta. Sin nada para hoy, el vacío de
/// siempre, que dice por qué (F30), en su forma compacta.
///
/// Con [onMyCards], «Mis tarjetas» va adentro, con borde, al lado de
/// «Empezar» (M14): el repaso del día y todas las tarjetas, en un solo lugar.
/// Está siempre, también sin nada para hoy.
class ReviewTodayStrip extends ConsumerWidget {
  const ReviewTodayStrip({
    required this.scope,
    required this.onStart,
    required this.onPractice,
    this.onResetScope,
    this.onMyCards,
    super.key,
  });

  final StudyScope scope;
  final VoidCallback onStart;
  final VoidCallback onPractice;

  /// «Estudiar todo», si el recorte no se pudo contar; sin esto no se ofrece.
  final VoidCallback? onResetScope;

  /// «Mis tarjetas»; sin esto no se ofrece.
  final VoidCallback? onMyCards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = ref.watch(studyCountsProvider(scope));

    final Widget content;
    // Sin «Empezar» —el vacío o la falla—, «Mis tarjetas» va solo, debajo.
    var alone = true;
    if (counts.hasError && !counts.hasValue) {
      content = Column(
        key: const Key('review-entry-count-failed'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reviewEntryCountFailed,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
          if (!scope.isAll && onResetScope != null)
            TextButton(
              onPressed: onResetScope,
              child: Text(l10n.reviewEntryScopeReset),
            ),
        ],
      );
    } else if (counts.valueOrNull case final value?) {
      alone = value.isEmpty;
      content = value.isEmpty
          ? ReviewEmptyState(onPractice: onPractice, compact: true)
          : _Counts(value: value, onStart: onStart, onMyCards: onMyCards);
    } else {
      // Lo que tarda en contar es un instante: el lugar, quieto.
      alone = false;
      content = const SizedBox(height: 48);
    }
    final myCards = onMyCards;

    return Container(
      key: const Key('review-entry-today'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: alone && myCards != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                content,
                const SizedBox(height: 8),
                _Buttons(onMyCards: myCards),
              ],
            )
          : content,
    );
  }
}

/// «Mis tarjetas», con borde, y «Empezar», lleno, a la derecha. Si no entran
/// en una fila —360 dp con la letra al doble—, bajan uno debajo del otro,
/// «Empezar» arriba, alineados a la derecha: nunca se cortan.
class _Buttons extends StatelessWidget {
  const _Buttons({this.onStart, this.onMyCards});

  final VoidCallback? onStart;
  final VoidCallback? onMyCards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final start = onStart;
    final myCards = onMyCards;
    return OverflowBar(
      key: const Key('review-entry-today-buttons'),
      alignment: MainAxisAlignment.end,
      spacing: 8,
      overflowSpacing: 8,
      overflowAlignment: OverflowBarAlignment.end,
      overflowDirection: VerticalDirection.up,
      children: [
        if (myCards != null)
          OutlinedButton.icon(
            key: const Key('review-entry-cards'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: myCards,
            icon: const Icon(Icons.style_outlined),
            label: Text(l10n.reviewEntryMyCards),
          ),
        if (start != null)
          FilledButton.icon(
            key: const Key('review-entry-start'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: start,
            icon: const Icon(Icons.play_arrow),
            label: Text(l10n.reviewEntryStart),
          ),
      ],
    );
  }
}

class _Counts extends ConsumerWidget {
  const _Counts({required this.value, required this.onStart, this.onMyCards});

  final StudyCounts value;
  final VoidCallback onStart;
  final VoidCallback? onMyCards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = value.nextLearningDue == null
        ? null
        : (value.nextLearningDue!
                      .difference(ref.read(clockProvider)())
                      .inSeconds /
                  60)
              .ceil();

    return Column(
      key: const Key('review-entry-counts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: [
                Text(
                  l10n.f43StudioTodayTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _Count(
                  key: const Key('review-entry-new'),
                  label: l10n.reviewSessionQueueNew,
                  count: value.newCards,
                  color: scheme.primary,
                ),
                _Count(
                  key: const Key('review-entry-learning'),
                  label: l10n.reviewSessionQueueLearning,
                  count: value.learning,
                  color: scheme.error,
                ),
                _Count(
                  key: const Key('review-entry-review'),
                  label: l10n.reviewSessionQueueReview,
                  count: value.reviews,
                  color: scheme.tertiary,
                ),
              ],
            ),
            _Buttons(onStart: onStart, onMyCards: onMyCards),
          ],
        ),
        if (value.newBeyondLimit > 0)
          _Note(
            key: const Key('review-entry-new-beyond'),
            text: l10n.reviewEntryNewBeyond(value.newBeyondLimit),
          ),
        if (value.reviewsBeyondLimit > 0)
          _Note(
            key: const Key('review-entry-reviews-beyond'),
            text: l10n.reviewEntryReviewsBeyond(value.reviewsBeyondLimit),
          ),
        if (minutes != null && minutes > 0)
          _Note(
            key: const Key('review-entry-next-learning'),
            text: l10n.reviewEntryNextLearning(minutes),
          ),
      ],
    );
  }
}

/// Una cifra con su nombre al lado: «20 Nuevas».
class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.count,
    required this.color,
    super.key,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $count',
      excludeSemantics: true,
      // Un `Wrap` y no una fila: con la letra al doble, el nombre baja debajo
      // de la cifra en vez de salirse de la franja.
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$count',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
