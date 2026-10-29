import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_icon.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de «Lo creado» (F43, punto 2 del plan): el ícono de su tipo con su
/// color, el título que puso la IA, «N fuentes · Hace X días» y su ⋮.
///
/// - **Mientras se genera** aparece con un brillo que recorre —quieto con
///   «sin animaciones»— y dice en qué va: en la cola, el paso y cuánto falta.
/// - **Si falló**, dice por qué en una línea y ofrece «Reintentar».
/// - **Lista**, tocarla abre su visor.
/// - Abajo, **sus fuentes como chips tocables** (M6): el documento, el
///   cuaderno o el tema, con «Fuente borrada» si ya no está.
///
/// La usan «Lo creado» de Repasar y la sección «En Repasar» de un documento
/// procesado y de un cuaderno.
class CreationTile extends ConsumerWidget {
  const CreationTile({required this.creation, super.key});

  final StudyCreation creation;

  /// Cuántas fuentes se muestran como chips; el resto va en «+N».
  static const maxSourceChips = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
    final ready = creation.status == CreationStatus.ready;

    final tile = Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('creation-tile-${creation.id}'),
        onTap: ready ? () => openCreation(context, creation) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CreationKindIcon(spec: spec),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      studyCreationTitle(l10n, creation),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _Status(creation: creation),
                    const SizedBox(height: 8),
                    CreationSourceChips(
                      creation: creation,
                      maxDocuments: maxSourceChips,
                    ),
                  ],
                ),
              ),
              CreationMenuButton(creation: creation),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: studyCreationKindLabel(l10n, creation.kind),
      child: creation.status.isPending ? _Shimmer(child: tile) : tile,
    );
  }
}

/// La línea de su estado: lista, en la cola, generándose o fallida.
class _Status extends ConsumerWidget {
  const _Status({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final locale = Localizations.localeOf(context).toLanguageTag();

    switch (creation.status) {
      case CreationStatus.ready:
        final now = ref.watch(clockProvider)();
        return Text(
          '${l10n.f43StudioSourceCount(creation.sourceIds.length)} · '
          '${creationAgo(l10n, creation.createdAt, now, locale: locale)}',
          key: ValueKey('creation-status-${creation.id}'),
          style: muted,
        );
      case CreationStatus.queued:
        return Text(
          creation.runNow
              ? l10n.f43StudioStatusQueued
              : l10n.f43StudioStatusLater,
          key: ValueKey('creation-status-${creation.id}'),
          style: muted,
        );
      case CreationStatus.generating:
        final progress = creation.progress;
        final step = creation.step;
        final percent = progress == null
            ? null
            : NumberFormat.percentPattern(locale).format(progress);
        final stepLabel = step == null
            ? l10n.f43DataStepWriting
            : creationStepLabel(l10n, step);
        final label = percent == null ? stepLabel : '$stepLabel · $percent';
        return Column(
          key: ValueKey('creation-status-${creation.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: muted),
            if (progress != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1).toDouble(),
                  minHeight: 4,
                ),
              ),
            ],
          ],
        );
      case CreationStatus.failed:
        final failure = creation.failure ?? CreationFailure.error;
        return Wrap(
          key: ValueKey('creation-status-${creation.id}'),
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              creationFailureMessage(l10n, failure),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
            TextButton.icon(
              key: ValueKey('creation-retry-${creation.id}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () =>
                  unawaited(ref.read(creationQueueProvider).retry(creation.id)),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.f43StudioRetry),
            ),
          ],
        );
    }
  }
}

/// El brillo que recorre la fila mientras se genera. Con «sin animaciones»
/// queda quieto: un velo apenas más claro, sin moverse.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.06);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final still = !_controller.isAnimating;
        final t = still ? 0.5 : _controller.value;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('creation-shimmer'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment(-1.5 + 3 * t, -0.3),
                      end: Alignment(-0.5 + 3 * t, 0.3),
                      colors: [
                        highlight.withValues(alpha: 0),
                        highlight,
                        highlight.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
