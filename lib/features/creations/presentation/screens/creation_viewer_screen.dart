import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_icon.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de una creación (F43, punto 5 del plan), con la barra que
/// comparten todos los tipos: ←, el título, «Ver N fuentes» con las fuentes
/// como chips tocables (M6), los botones propios del tipo —compartir,
/// exportar, pantalla completa— y ⋮.
///
/// Lo de abajo de la barra lo pone el tipo (`CreationKindSpec.viewerBuilder`).
/// Un tipo que todavía no tiene visor muestra «su visor está en camino»: la
/// creación ya quedó guardada y se abre acá en cuanto llegue. Una que se
/// genera dice en qué va; una fallida, por qué, con «Reintentar».
class CreationViewerScreen extends ConsumerWidget {
  const CreationViewerScreen({required this.creationId, super.key});

  final String creationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final watched = ref.watch(studyCreationProvider(creationId));
    final creation = watched.valueOrNull;

    if (creation == null) {
      return Scaffold(
        appBar: AppBar(),
        body: watched.isLoading
            ? const SizedBox.shrink()
            : _Message(
                key: const Key('creation-viewer-missing'),
                icon: Icons.link_off,
                text: l10n.f43StudioViewerMissing,
              ),
      );
    }

    final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
    final ready = creation.status == CreationStatus.ready;
    return Scaffold(
      key: ValueKey('creation-viewer-${creation.id}'),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CreationKindIcon(spec: spec, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                studyCreationTitle(l10n, creation),
                key: const Key('creation-viewer-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        actions: [
          if (ready && !creation.isTrashed)
            ...?spec.viewerActions?.call(context, creation),
          if (!creation.isTrashed)
            CreationMenuButton(creation: creation, includeOpen: false),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SourcesBar(creation: creation),
          Expanded(child: _body(context, ref, spec, creation)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    CreationKindSpec spec,
    StudyCreation creation,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (creation.isTrashed) {
      return _Message(
        key: const Key('creation-viewer-trashed'),
        icon: Icons.delete_outline,
        text: l10n.f43StudioViewerTrashed,
      );
    }
    switch (creation.status) {
      case CreationStatus.queued || CreationStatus.generating:
        final step = creation.step;
        return _Message(
          key: const Key('creation-viewer-pending'),
          icon: Icons.hourglass_top,
          text: l10n.f43StudioViewerPending,
          detail: step == null ? null : creationStepLabel(l10n, step),
          progress: creation.progress,
        );
      case CreationStatus.failed:
        return _Message(
          key: const Key('creation-viewer-failed'),
          icon: Icons.error_outline,
          text: creationFailureMessage(
            l10n,
            creation.failure ?? CreationFailure.error,
          ),
          action: FilledButton.icon(
            onPressed: () =>
                unawaited(ref.read(creationQueueProvider).retry(creation.id)),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.f43StudioRetry),
          ),
        );
      case CreationStatus.ready:
        final viewer = spec.viewerBuilder;
        if (viewer != null) return viewer(context, creation);
        return _Message(
          key: const Key('creation-viewer-coming'),
          icon: spec.iconData,
          iconColor: spec.accent.of(context),
          text: l10n.f43StudioViewerComing,
          detail: l10n.f43StudioViewerComingHint(spec.label(l10n)),
        );
    }
  }
}

/// «Ver N fuentes» y las fuentes como chips, debajo de la barra.
class _SourcesBar extends StatelessWidget {
  const _SourcesBar({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            key: const Key('creation-viewer-sources'),
            avatar: const Icon(Icons.source_outlined, size: 16),
            label: Text(l10n.f43StudioViewSources(creation.sourceIds.length)),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(showCreationSources(context, creation)),
          ),
          CreationSourceChips(creation: creation, maxDocuments: 3),
        ],
      ),
    );
  }
}

/// Un mensaje centrado, con su ícono y, si hace falta, el avance o una acción.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.detail,
    this.iconColor,
    this.progress,
    this.action,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? detail;
  final Color? iconColor;
  final double? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = iconColor ?? scheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(28),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(height: 20),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0, 1).toDouble(),
                    minHeight: 6,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}
