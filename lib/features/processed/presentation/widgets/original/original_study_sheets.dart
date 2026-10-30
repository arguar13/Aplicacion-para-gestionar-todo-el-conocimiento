import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo armar lo que falta en el original: con la IA o a mano.
enum OriginalStudyChoice { ai, manual }

/// Lo que ofrece el menú de un botón de estudio del original (M5).
enum OriginalStudyAction { redoWithAi, retouch, hide, show, clear }

/// Una hoja de los botones de estudio, sin deslizarse si la persona apagó
/// las animaciones.
Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder builder) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: builder(sheetContext),
    ),
  );
}

/// La hoja chica de un botón sin marcas (M5): dos opciones grandes, «Con IA»
/// —el modelo elegido, con lo que va a consumir— y «A mano». Devuelve la
/// elegida, o `null` si se cerró.
Future<OriginalStudyChoice?> showOriginalStudyChoice(
  BuildContext context,
  OriginalStudy study,
  StudyMarkKind kind,
) => _showSheet<OriginalStudyChoice>(
  context,
  (sheetContext) => OriginalStudyChoiceSheet(
    study: study,
    kind: kind,
    onChosen: (choice) => Navigator.of(sheetContext).pop(choice),
  ),
);

/// Lo que ve la persona al tocar un botón sin marcas: qué falta, las dos
/// opciones —en fila si entran, una debajo de la otra en un teléfono angosto
/// o con la letra grande— y, debajo de «Con IA», «Con tu IA actual» con lo
/// que va a consumir (`AiCapabilityCard`).
class OriginalStudyChoiceSheet extends ConsumerWidget {
  const OriginalStudyChoiceSheet({
    required this.study,
    required this.kind,
    required this.onChosen,
    super.key,
  });

  final OriginalStudy study;
  final StudyMarkKind kind;
  final ValueChanged<OriginalStudyChoice> onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = StudyPalette.of(theme.brightness);
    final color = originalStudyColor(palette, kind);
    final model = modelLabel(ref.watch(chosenLanguageModelNameProvider));
    final words = kind == StudyMarkKind.keyword;
    final (title, body) = switch (kind) {
      StudyMarkKind.summary => (
        l10n.studySuggestTitleSummary,
        l10n.studySuggestBodySummary,
      ),
      StudyMarkKind.synthesis => (
        l10n.studySuggestTitleSynthesis,
        l10n.studySuggestBodySynthesis,
      ),
      StudyMarkKind.keyword => (
        l10n.studySuggestTitleKeywords,
        l10n.studySuggestBodyKeywords(kMaxKeywordsPerSentence),
      ),
    };

    final ai = _OptionTile(
      key: const Key('original-study-choice-ai'),
      icon: Icons.auto_awesome,
      color: color,
      title: l10n.f43OrigChoiceAi,
      body: words
          ? l10n.f43OrigChoiceAiWords(model)
          : l10n.f43OrigChoiceAiSentences(model),
      onTap: () => onChosen(OriginalStudyChoice.ai),
    );
    final manual = _OptionTile(
      key: const Key('original-study-choice-manual'),
      icon: Icons.touch_app_outlined,
      color: color,
      title: l10n.f43OrigChoiceManual,
      body: words
          ? l10n.f43OrigChoiceManualWords(kMaxKeywordsPerSentence)
          : l10n.f43OrigChoiceManualSentences,
      onTap: () => onChosen(OriginalStudyChoice.manual),
    );

    return Column(
      key: Key('original-study-choice-${kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(kind: kind, title: title),
        const SizedBox(height: 6),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Dos de lado a lado necesitan aire: con la letra grande o en un
            // teléfono angosto van una debajo de la otra.
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final side = constraints.maxWidth / scale >= 420;
            if (!side) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [ai, const SizedBox(height: 10), manual],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ai),
                  const SizedBox(width: 10),
                  Expanded(child: manual),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        _AiNotice(study: study, fromStart: false),
      ],
    );
  }
}

/// El título de una hoja de los botones de estudio: el color del botón, qué
/// es, y la ✕.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.kind, required this.title});

  final StudyMarkKind kind;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = originalStudyColor(StudyPalette.of(theme.brightness), kind);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(
            originalStudyIcon(kind),
            size: 20,
            color: StudyPalette.ink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        CreationCloseButton(tooltip: l10n.f43OrigClose),
      ],
    );
  }
}

/// Una opción grande: el ícono en su círculo de color, qué es y qué hace.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: StudyPalette.ink),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Con tu IA actual»: qué modelo marca y cuánto va a consumir analizar lo
/// que falta del original —o el texto entero, con [fromStart]—.
class _AiNotice extends ConsumerWidget {
  const _AiNotice({required this.study, required this.fromStart});

  final OriginalStudy study;
  final bool fromStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final plan = ref
        .watch(originalStudyPlanProvider((study: study, fromStart: fromStart)))
        .valueOrNull;
    if (plan == null) {
      // Sin ruedita: sin animaciones, y la cuenta tarda un instante.
      return Text(
        l10n.f43OrigEstimating,
        key: const Key('original-study-estimating'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final estimate = ref.watch(
      creationEstimateProvider(
        CreationEstimateRequest(
          inputTokens: plan.inputTokens,
          expectedOutputTokens: plan.outputTokens,
          textRequests: plan.parts < 1 ? 1 : plan.parts,
        ),
      ),
    );
    return AiCapabilityCard(estimate: estimate);
  }
}

/// El menú de un botón con marcas (M5): rehacer con IA, retocar a mano,
/// ocultar o mostrar y, con [canClear], borrar las marcas. Mientras la IA
/// marca no se ofrece rehacer: ya está rehaciendo.
Future<OriginalStudyAction?> showOriginalStudyMenu(
  BuildContext context, {
  required StudyMarkKind kind,
  required int count,
  required bool shown,
  required bool running,
  required bool canClear,
}) => _showSheet<OriginalStudyAction>(context, (sheetContext) {
  final l10n = AppLocalizations.of(sheetContext)!;
  final theme = Theme.of(sheetContext);
  Widget item(OriginalStudyAction action, IconData icon, String label) =>
      ListTile(
        key: Key('original-study-menu-${action.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(icon),
        title: Text(label),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => Navigator.of(sheetContext).pop(action),
      );

  return Column(
    key: Key('original-study-menu-${kind.name}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _SheetHeader(kind: kind, title: originalStudyName(l10n, kind)),
      Padding(
        padding: const EdgeInsets.only(left: 48, bottom: 8),
        child: Text(
          originalStudyCount(l10n, kind, count),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      if (!running)
        item(
          OriginalStudyAction.redoWithAi,
          Icons.auto_awesome,
          l10n.f43OrigMenuRedo,
        ),
      item(
        OriginalStudyAction.retouch,
        Icons.touch_app_outlined,
        l10n.f43OrigMenuRetouch,
      ),
      if (shown)
        item(
          OriginalStudyAction.hide,
          Icons.visibility_off_outlined,
          l10n.f43OrigMenuHide,
        )
      else
        item(
          OriginalStudyAction.show,
          Icons.visibility_outlined,
          l10n.f43OrigMenuShow,
        ),
      if (canClear)
        item(
          OriginalStudyAction.clear,
          Icons.delete_outline,
          l10n.f43OrigMenuClear,
        ),
    ],
  );
});

/// «Rehacer con IA»: qué pasa y cuánto consume analizar el documento entero
/// de nuevo, antes de hacerlo. `true` si se confirmó.
Future<bool> showOriginalRedoSheet(
  BuildContext context,
  OriginalStudy study,
) async =>
    await _showSheet<bool>(context, (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final theme = Theme.of(sheetContext);
      return Column(
        key: const Key('original-study-redo'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.f43OrigRedoTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              CreationCloseButton(tooltip: l10n.f43OrigClose),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.f43OrigRedoBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _AiNotice(study: study, fromStart: true),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton.icon(
                key: const Key('original-study-redo-confirm'),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l10n.f43OrigRedoConfirm),
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        ],
      );
    }) ??
    false;

/// «Borrar las marcas», después de preguntar. `true` si se confirmó.
Future<bool> confirmOriginalClear(
  BuildContext context,
  StudyMarkKind kind,
) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.f43OrigClearTitle(kind.name)),
      content: Text(l10n.f43OrigClearBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('original-study-clear-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.f43OrigClearConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
