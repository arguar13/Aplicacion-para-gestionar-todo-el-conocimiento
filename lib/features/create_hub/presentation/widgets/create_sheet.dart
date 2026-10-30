import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/create_hub/presentation/create_runs.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de «Crear» (F45, paso 7b, mejora 14, decisión G): lo que se crea
/// del documento, en dos grupos —**Con IA**, con el modelo que lo hace, y **A
/// mano**—. Devuelve lo elegido, o `null` si se cerró.
///
/// Cada fila dice qué hace y, si está trabajando, cómo va —«Leyendo la parte
/// 1 de 2…», con su barra— con «Cancelar»; lo que hace la cola de la IA de
/// fondo, con «Ver», que lleva a lo que hizo. Lo que no se puede ahora se ve
/// apagado, con el porqué.
Future<CreateKind?> showCreateSheet(BuildContext context, CreateTarget target) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<CreateKind>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => CreateSheet(target: target),
  );
}

/// Lo que se ve en la hoja de «Crear»: ver [showCreateSheet].
class CreateSheet extends ConsumerWidget {
  const CreateSheet({required this.target, super.key});

  final CreateTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final itemId = target.item.id;
    final runs = ref.watch(createRunsProvider(itemId));
    final queued = queuedCreateOf(ref.watch(aiOrganizeStatusProvider), itemId);
    final model = modelLabel(ref.watch(chosenLanguageModelNameProvider));
    final offered = target.offered;

    Widget row(CreateKind kind) => _CreateRow(
      key: Key('create-${kind.name}'),
      kind: kind,
      progress: runs[kind],
      queued: kind == queued,
      block: target.blockOf(kind),
      onTap: () => Navigator.of(context).pop(kind),
      onCancel: () =>
          ref.read(createRunsProvider(itemId).notifier).cancel(kind),
      onSee: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        unawaited(router.push(RoutePaths.aiActivityFor(itemId)));
      },
    );

    return ListView(
      key: const Key('create-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.f45S7bCreate,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            CreationCloseButton(tooltip: l10n.f43OrigClose),
          ],
        ),
        _GroupLabel(l10n.f45S7bWithAi(model)),
        for (final kind in offered)
          if (kind.withAi) row(kind),
        _GroupLabel(l10n.f45S7bByHand),
        for (final kind in offered)
          if (!kind.withAi) row(kind),
      ],
    );
  }
}

/// El nombre de un grupo de la hoja.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Una fila de la hoja: el ícono, qué es y qué hace o cómo va.
///
/// - **Lista**: tocarla la elige.
/// - **Trabajando en esta pantalla** ([progress]): cómo va, su barra y
///   «Cancelar».
/// - **Trabajando en la cola de fondo** ([queued]): cómo va y «Ver».
/// - **Apagada** ([block]): por qué no se puede ahora.
class _CreateRow extends StatelessWidget {
  const _CreateRow({
    required this.kind,
    required this.progress,
    required this.queued,
    required this.block,
    required this.onTap,
    required this.onCancel,
    required this.onSee,
    super.key,
  });

  final CreateKind kind;
  final CreateProgress? progress;
  final bool queued;
  final CreateBlock? block;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onSee;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = this.progress;
    final working = progress != null || queued;
    final enabled = block == null && !working;
    final title = createTitle(l10n, kind);
    final detail = switch ((progress, block)) {
      (final CreateProgress progress?, _) => switch (progress.reading) {
        final part? => l10n.flashcardsReadingPart(part, progress.total!),
        null => l10n.f45S7bWorking,
      },
      _ when queued =>
        kind == CreateKind.dates
            ? l10n.f45S7bFindingDates
            : l10n.f45S7bOrganizing,
      (_, final CreateBlock block?) => createBlockReason(l10n, block),
      _ => createHint(l10n, kind),
    };
    final soft = scheme.onSurfaceVariant;
    final faded = enabled || working ? 1.0 : 0.5;

    return Semantics(
      button: enabled,
      enabled: enabled || working,
      label: '$title. $detail',
      onTap: enabled ? onTap : null,
      excludeSemantics: !working,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Opacity(
              opacity: faded,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kind.withAi)
                    AiSparkCircle(size: 40, icon: createIcon(kind))
                  else
                    _HandCircle(icon: createIcon(kind)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          key: Key('create-${kind.name}-detail'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: soft,
                          ),
                        ),
                        if (working) ...[
                          // Sin saber cuánto lleva y sin animaciones, la barra
                          // no aporta: lo dice el texto.
                          if (progress?.fraction != null ||
                              !MediaQuery.disableAnimationsOf(context)) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                key: Key('create-${kind.name}-progress'),
                                value: progress?.fraction,
                                minHeight: 4,
                              ),
                            ),
                          ],
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: queued
                                ? TextButton(
                                    key: Key('create-${kind.name}-see'),
                                    onPressed: onSee,
                                    child: Text(l10n.aiItemLineSee),
                                  )
                                : TextButton(
                                    key: Key('create-${kind.name}-cancel'),
                                    onPressed: onCancel,
                                    child: Text(l10n.commonCancel),
                                  ),
                          ),
                        ],
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

/// El círculo de lo que se hace a mano: el mismo tamaño que el ✨ de la IA,
/// en el color tenue de la superficie.
class _HandCircle extends StatelessWidget {
  const _HandCircle({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.secondaryContainer,
      ),
      child: Icon(icon, size: 20, color: scheme.onSecondaryContainer),
    );
  }
}

/// El nombre de [kind] en la hoja.
String createTitle(AppLocalizations l10n, CreateKind kind) => switch (kind) {
  CreateKind.organize => l10n.f45S7bOrganize,
  CreateKind.flashcards => l10n.flashcardsTitle,
  CreateKind.quiz => l10n.f45S7bQuiz,
  CreateKind.derivedNote => l10n.f45S7bDerivedNote,
  CreateKind.dates => l10n.f45S7bDates,
  CreateKind.card => l10n.f45S7bCard,
  CreateKind.note => l10n.f45S7bNote,
  CreateKind.link => l10n.f45S7bLink,
};

/// Qué hace [kind], debajo de su nombre.
String createHint(AppLocalizations l10n, CreateKind kind) => switch (kind) {
  CreateKind.organize => l10n.f45S7bOrganizeHint,
  CreateKind.flashcards => l10n.f45S7bFlashcardsHint,
  CreateKind.quiz => l10n.f45S7bQuizHint,
  CreateKind.derivedNote => l10n.f45S7bDerivedNoteHint,
  CreateKind.dates => l10n.f45S7bDatesHint,
  CreateKind.card => l10n.f45S7bCardHint,
  CreateKind.note => l10n.f45S7bNoteHint,
  CreateKind.link => l10n.f45S7bLinkHint,
};

/// Por qué no se puede ahora.
String createBlockReason(AppLocalizations l10n, CreateBlock block) =>
    switch (block) {
      CreateBlock.noText => l10n.f45S7bBlockNoText,
      CreateBlock.notReady => l10n.f45S7bBlockNotReady,
      CreateBlock.sourceInTrash => l10n.f45S7bBlockSourceInTrash,
      CreateBlock.sourceGone => l10n.f45S7bBlockSourceGone,
    };

/// El ícono de [kind]: el mismo que tenía donde estaba antes.
IconData createIcon(CreateKind kind) => switch (kind) {
  CreateKind.organize => Icons.auto_awesome,
  CreateKind.flashcards => Icons.style_outlined,
  CreateKind.quiz => Icons.quiz_outlined,
  CreateKind.derivedNote => Icons.auto_stories_outlined,
  CreateKind.dates => Icons.timeline,
  CreateKind.card => Icons.add_card_outlined,
  CreateKind.note => Icons.sticky_note_2_outlined,
  CreateKind.link => Icons.add_link,
};
