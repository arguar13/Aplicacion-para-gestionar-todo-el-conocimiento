import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Marcar con la IA lo que le falta a una extracción (F43, paso 7, M8): **la
/// misma máquina que los botones de estudio del original** (M5) —el análisis
/// de siempre (F36) sobre el texto propio de cada documento, con su clave
/// `procesado:…`—. Lo que la IA marca queda en el documento mismo, y lo ven
/// a la vez el original, el documento y este visor: nunca hay dos versiones.
///
/// Antes de empezar, lo que se marca se deja a la vista en el original —lo
/// que la persona pidió ver no puede quedar oculto allá—. Los documentos se
/// analizan de a uno, en orden: la IA es una sola, y así cada uno se llena
/// entero antes de pasar al siguiente. Un análisis que ya terminó —y lo que
/// falta se borró, o la IA no encontró nada— se rehace desde el principio,
/// como «Rehacer con IA» del original: lo elegido a mano queda.
///
/// Sin el modelo listo, lo avisa con el botón que lo resuelve y no empieza.
Future<void> markExtractWithAi(
  WidgetRef ref,
  BuildContext context, {
  required StudyMarkKind kind,
  required List<ExtractSection> sections,
}) async {
  final ready = await ensureStudyModelReady(context, ref);
  if (!ready || !context.mounted) return;
  final repository = ref.read(studyRepositoryProvider);
  final jobs = <_MarkJob>[];
  for (final section in sections) {
    final own = section.own;
    if (own == null) continue;
    await ref
        .read(processedOriginalHiddenProvider(section.documentId).notifier)
        .setHidden(kind, hidden: false);
    jobs.add((
      analysis: ref.read(studyAnalysisProvider(own.key).notifier),
      own: own,
      fromStart: section.study.complete,
    ));
  }
  unawaited(_markInTurn(repository, jobs));
}

typedef _MarkJob = ({
  StudyAnalysisNotifier analysis,
  ProcessedStudyText own,
  bool fromStart,
});

/// Cada análisis espera al anterior. Lo que ya se está analizando —desde el
/// original, desde otra extracción— no se pide dos veces.
Future<void> _markInTurn(
  StudyRepository repository,
  List<_MarkJob> jobs,
) async {
  for (final job in jobs) {
    if (job.analysis.isRunning) continue;
    if (job.fromStart) await repository.clearAi(job.own.key);
    await job.analysis.start(
      content: job.own.content,
      markdown: job.own.markdown,
      itemId: job.own.documentId,
    );
  }
}

/// La hoja de «Marcar con IA» (M8): qué va a hacer, con qué modelo y, en
/// «Con tu IA actual», cuánto consume analizar lo que falta de [sections]
/// —la misma cuenta que el original (`processedStudyPlanProvider`)—. `true`
/// si se confirmó.
Future<bool> showExtractMarkSheet(
  BuildContext context, {
  required StudyMarkKind kind,
  required List<ExtractSection> sections,
}) async {
  final still = MediaQuery.disableAnimationsOf(context);
  final confirmed = await showModalBottomSheet<bool>(
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
      child: ExtractMarkSheet(
        kind: kind,
        sections: sections,
        onDone: (value) => Navigator.of(sheetContext).pop(value),
      ),
    ),
  );
  return confirmed ?? false;
}

/// Lo de adentro de [showExtractMarkSheet].
class ExtractMarkSheet extends ConsumerWidget {
  const ExtractMarkSheet({
    required this.kind,
    required this.sections,
    required this.onDone,
    super.key,
  });

  final StudyMarkKind kind;
  final List<ExtractSection> sections;
  final ValueChanged<bool> onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = originalStudyColor(StudyPalette.of(theme.brightness), kind);
    final model = modelLabel(ref.watch(chosenLanguageModelNameProvider));
    final title = switch (kind) {
      StudyMarkKind.summary => l10n.f43TextMarkTitleSummary,
      StudyMarkKind.synthesis => l10n.f43TextMarkTitleSynthesis,
      StudyMarkKind.keyword => l10n.f43TextMarkTitleKeywords,
    };
    return Column(
      key: const Key('extract-mark-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(
                originalStudyIcon(kind),
                size: 22,
                color: StudyPalette.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            CreationCloseButton(
              tooltip: l10n.f43TextClose,
              onPressed: () => onDone(false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          sections.length == 1
              ? l10n.f43TextMarkBody(model)
              : l10n.f43TextMarkBodyMany(sections.length, model),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _MarkEstimate(sections: sections),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => onDone(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton.icon(
              key: const Key('extract-mark-confirm'),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(l10n.f43TextMarkWithAi),
              onPressed: () => onDone(true),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Con tu IA actual» para marcar [sections]: la suma de lo que va a leer y
/// escribir el análisis de cada una —desde donde quedó, o desde el principio
/// si ya había terminado—, con su tarjeta de siempre.
class _MarkEstimate extends ConsumerWidget {
  const _MarkEstimate({required this.sections});

  final List<ExtractSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    var input = 0;
    var output = 0;
    var parts = 0;
    for (final section in sections) {
      final plan = ref
          .watch(
            processedStudyPlanProvider((
              documentId: section.documentId,
              fromStart: section.study.complete,
            )),
          )
          .valueOrNull;
      if (plan == null) {
        // Sin ruedita: sin animaciones, y la cuenta tarda un instante.
        return Text(
          l10n.f43OrigEstimating,
          key: const Key('extract-mark-estimating'),
          style: Theme.of(context).textTheme.bodySmall,
        );
      }
      input += plan.inputTokens;
      output += plan.outputTokens;
      parts += plan.parts;
    }
    final estimate = ref.watch(
      creationEstimateProvider(
        CreationEstimateRequest(
          inputTokens: input,
          expectedOutputTokens: output,
          textRequests: parts < 1 ? 1 : parts,
        ),
      ),
    );
    return AiCapabilityCard(estimate: estimate);
  }
}
