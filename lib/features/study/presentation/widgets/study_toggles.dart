import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Prende [layer] —el resumen o la síntesis— en [text], o lo apaga si ya
/// estaba (F36). Cada uno por su lado: se ven los dos juntos, uno o ninguno
/// (F39).
///
/// Si todavía no hay nada de [layer] y nadie lo está armando, en vez de
/// prenderlo ofrece armarlo con la IA o a mano (F39): ver
/// [showStudySuggestion]. Si hay, se prende, y un análisis que quedó a mitad
/// sigue; uno que nunca empezó —lo elegido a mano— no arranca solo.
///
/// Apagar el resaltado que se está eligiendo a mano deja de elegirlo: se
/// elige lo que se ve.
Future<void> toggleStudyLayer(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
  StudyLayer layer, {
  VoidCallback? onManual,
}) async {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  final on = !view.state.shows(layer);
  if (on) {
    final suggest = await studyNeedsSuggestion(ref, text, layer.kind);
    if (!context.mounted) return;
    if (suggest) {
      await showStudySuggestion(
        context,
        ref,
        text,
        layer.kind,
        onManual: onManual,
      );
      return;
    }
  }
  final next = view.state.withLayer(layer, on: on);
  view.state = next.copyWith(pick: () => _stillPicking(next));
  if (on) await _continueAnalysis(ref, context, text);
}

/// Lo que se sigue eligiendo a mano en [view]: las palabras clave siguen; el
/// resumen o la síntesis, solo si se ve.
StudyMarkKind? _stillPicking(StudyView view) {
  final pick = view.pick;
  return pick == null ||
          pick == StudyMarkKind.keyword ||
          view.layers.any((layer) => layer.kind == pick)
      ? pick
      : null;
}

/// Sigue un análisis que quedó a mitad; no arranca uno nuevo.
Future<void> _continueAnalysis(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
) async {
  final study = await ref
      .read(studyRepositoryProvider)
      .watch(text.renditionId)
      .first;
  if (!study.started || !context.mounted) return;
  await analyzeForStudyIfNeeded(ref, context, text);
}

/// Si a lo de [kind] le falta todo y nadie lo está armando (F39): ni la IA
/// lo marcó ni se eligió a mano, y no hay un análisis a mitad que lo vaya a
/// traer.
///
/// Lee lo guardado, no lo que ya cargó la pantalla: el lector a pantalla
/// completa puede no estar mirándolo todavía, y no hay que ofrecer armar un
/// resumen que existe.
Future<bool> studyNeedsSuggestion(
  WidgetRef ref,
  StudyText text,
  StudyMarkKind kind,
) async {
  if (ref.read(studyAnalysisProvider(text.renditionId))
      is StudyAnalysisRunning) {
    return false;
  }
  final study = await ref
      .read(studyRepositoryProvider)
      .watch(text.renditionId)
      .first;
  if (study.of(kind).isNotEmpty) return false;
  return !study.started || study.complete;
}

/// Cómo se arma lo que falta (F39): con el modelo elegido o a mano.
enum StudySuggestionChoice { ai, manual }

/// Arma lo de [kind] en [text] como se eligió (F39).
///
/// - **Con la IA**: lo prende y analiza lo que falte.
/// - **A mano**: lo prende y pasa a elegirlo —tocar una oración o una
///   palabra—; con [onManual], además, quien muestra la tarjeta despliega el
///   texto donde se toca. Al terminar de elegir sigue prendido: se ve lo que
///   se eligió.
Future<void> applyStudySuggestion(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
  StudyMarkKind kind,
  StudySuggestionChoice choice, {
  VoidCallback? onManual,
}) async {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  final layer = StudyLayer.values.where((l) => l.kind == kind).firstOrNull;
  final manual = choice == StudySuggestionChoice.manual;
  final shown = layer == null
      ? view.state.copyWith(keywords: true)
      : view.state.withLayer(layer, on: true);
  view.state = shown.copyWith(
    pick: manual ? () => kind : () => _stillPicking(shown),
  );
  if (manual) {
    onManual?.call();
    return;
  }
  await analyzeForStudyIfNeeded(ref, context, text);
}

/// Ofrece armar lo de [kind] con la IA o a mano, en una hoja (F39): lo que
/// pasa al tocar «Resumir», «Sintetizar» o «Palabras clave» sin nada todavía.
Future<void> showStudySuggestion(
  BuildContext context,
  WidgetRef ref,
  StudyText text,
  StudyMarkKind kind, {
  VoidCallback? onManual,
}) async {
  final choice = await showModalBottomSheet<StudySuggestionChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: StudySuggestion(
          text: text,
          kind: kind,
          onChosen: (choice) => Navigator.of(sheetContext).pop(choice),
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await applyStudySuggestion(
    ref,
    context,
    text,
    kind,
    choice,
    onManual: onManual,
  );
}

/// Qué falta y los dos caminos para armarlo (F39): **«Resumir con …»**, con el
/// modelo elegido por su nombre, y **«Elegir a mano»**. En la hoja de los
/// botones de estudiar y en la fila vacía de «Extraer».
///
/// Si la IA ya analizó todo y no encontró nada, queda solo «Elegir a mano»:
/// pedírselo de nuevo daría lo mismo.
class StudySuggestion extends ConsumerWidget {
  const StudySuggestion({
    required this.text,
    required this.kind,
    required this.onChosen,
    super.key,
  });

  final StudyText text;
  final StudyMarkKind kind;
  final ValueChanged<StudySuggestionChoice> onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final model = modelLabel(ref.watch(chosenLanguageModelNameProvider));
    final analyzed =
        ref
            .watch(documentStudyProvider(text.renditionId))
            .valueOrNull
            ?.complete ??
        false;
    final (title, body, withAi) = switch (kind) {
      StudyMarkKind.summary => (
        l10n.studySuggestTitleSummary,
        l10n.studySuggestBodySummary,
        l10n.studySuggestSummarizeWith(model),
      ),
      StudyMarkKind.synthesis => (
        l10n.studySuggestTitleSynthesis,
        l10n.studySuggestBodySynthesis,
        l10n.studySuggestSynthesizeWith(model),
      ),
      StudyMarkKind.keyword => (
        l10n.studySuggestTitleKeywords,
        l10n.studySuggestBodyKeywords(kMaxKeywordsPerSentence),
        l10n.studySuggestKeywordsWith(model),
      ),
    };

    return Column(
      key: Key('study-suggestion-${kind.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!analyzed)
              FilledButton.icon(
                key: const Key('study-suggest-ai'),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(withAi),
                onPressed: () => onChosen(StudySuggestionChoice.ai),
              ),
            OutlinedButton.icon(
              key: const Key('study-suggest-manual'),
              icon: const Icon(Icons.touch_app_outlined, size: 18),
              label: Text(l10n.studySuggestManual),
              onPressed: () => onChosen(StudySuggestionChoice.manual),
            ),
          ],
        ),
      ],
    );
  }
}

/// Prende [layer] en [text] —si ya estaba, queda— y analiza lo que falte
/// (F36): «Resumir» del panel de la fuente.
Future<void> showStudyLayer(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
  StudyLayer layer,
) async {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  view.state = view.state.withLayer(layer, on: true);
  await analyzeForStudyIfNeeded(ref, context, text);
}

/// Muestra u oculta las palabras clave de [text] (F36). Sin ninguna
/// todavía, ofrece armarlas con la IA o a mano (F39); con alguna, mostrarlas
/// sigue un análisis que quedó a mitad.
Future<void> toggleStudyKeywords(
  WidgetRef ref,
  BuildContext context,
  StudyText text, {
  VoidCallback? onManual,
}) async {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  final on = !view.state.keywords;
  if (on) {
    final suggest = await studyNeedsSuggestion(
      ref,
      text,
      StudyMarkKind.keyword,
    );
    if (!context.mounted) return;
    if (suggest) {
      await showStudySuggestion(
        context,
        ref,
        text,
        StudyMarkKind.keyword,
        onManual: onManual,
      );
      return;
    }
  }
  view.state = view.state.copyWith(keywords: on);
  if (on) {
    // Lo analizado antes de que cada oración llevara sus palabras clave se
    // completa acá, con el respaldo local: aparecen cuando terminan, sin IA.
    unawaited(ensureStudyKeywords(ref, text));
    await _continueAnalysis(ref, context, text);
  }
}

/// Prende o apaga elegir palabras clave a mano en [text] (F36).
void toggleStudyPicking(WidgetRef ref, StudyText text) {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  final on = view.state.pick != StudyMarkKind.keyword;
  view.state = view.state.copyWith(
    pick: () => on ? StudyMarkKind.keyword : null,
  );
}

/// Analiza lo que falta de [text], si falta algo y no se está analizando ya
/// (F36). Una sola pasada da el resumen, la síntesis y las palabras: lo ya
/// analizado no se pide de nuevo, y un análisis cortado sigue desde ahí.
///
/// Usa el modelo elegido en Ajustes; si no está listo, lo avisa con el botón
/// que lo resuelve y no baja nada solo.
Future<void> analyzeForStudyIfNeeded(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
) async {
  final notifier = ref.read(studyAnalysisProvider(text.renditionId).notifier);
  if (notifier.isRunning) return;
  final study = await ref
      .read(studyRepositoryProvider)
      .watch(text.renditionId)
      .first;
  if (study.complete || !context.mounted) return;
  final ready = await ensureStudyModelReady(context, ref);
  if (!ready || !context.mounted) return;
  unawaited(
    notifier.start(
      content: text.content,
      markdown: text.markdown,
      itemId: text.itemId,
    ),
  );
}

/// Si el modelo elegido está listo para estudiar; si no, lo avisa con el
/// botón que lo resuelve.
Future<bool> ensureStudyModelReady(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  return ensureLanguageModelReady(
    context,
    ref,
    downloadMessage: l10n.studyModelRequired,
    downloadLabel: l10n.summarizeDownloadAction,
  );
}

/// Los tres botones de estudiar un texto (F36): **Resumir**,
/// **Sintetizar** y **Palabras clave**, con su lápiz para elegirlas a mano.
/// Cada uno con su color de resaltador, y cada uno se prende por su lado: se
/// ven juntos, de a uno, de a dos o ninguno (F39).
///
/// Los mismos en la tarjeta del detalle y en la barra del lector a pantalla
/// completa: lo que se prende en uno se ve en el otro —ver
/// [studyViewProvider]—.
class StudyToggles extends ConsumerWidget {
  const StudyToggles({required this.text, this.onManual, super.key});

  final StudyText text;

  /// Al pasar a elegir a mano desde la sugerencia: la tarjeta despliega el
  /// texto donde se toca.
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final palette = StudyPalette.of(Theme.of(context).brightness);
    final view = ref.watch(studyViewProvider(text.renditionId));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StudyChip(
          key: const Key('study-toggle-summary'),
          icon: Icons.notes_outlined,
          label: l10n.studySummarize,
          color: palette.summary,
          selected: view.summary,
          onTap: () => unawaited(
            toggleStudyLayer(
              ref,
              context,
              text,
              StudyLayer.summary,
              onManual: onManual,
            ),
          ),
        ),
        _StudyChip(
          key: const Key('study-toggle-synthesis'),
          icon: Icons.filter_center_focus_outlined,
          label: l10n.studySynthesize,
          color: palette.synthesis,
          selected: view.synthesis,
          onTap: () => unawaited(
            toggleStudyLayer(
              ref,
              context,
              text,
              StudyLayer.synthesis,
              onManual: onManual,
            ),
          ),
        ),
        _StudyChip(
          key: const Key('study-toggle-keywords'),
          icon: Icons.key_outlined,
          label: l10n.studyKeywords,
          color: palette.keyword,
          selected: view.showsKeywords,
          onTap: () => unawaited(
            toggleStudyKeywords(ref, context, text, onManual: onManual),
          ),
        ),
        IconButton(
          key: const Key('study-toggle-pick'),
          tooltip: l10n.studyPickKeywords,
          isSelected: view.pick == StudyMarkKind.keyword,
          icon: const Icon(Icons.edit_outlined),
          selectedIcon: const Icon(Icons.edit),
          style: IconButton.styleFrom(
            backgroundColor: view.pick == StudyMarkKind.keyword
                ? palette.keyword
                : null,
            foregroundColor: view.pick == StudyMarkKind.keyword
                ? StudyPalette.ink
                : null,
          ),
          onPressed: () => toggleStudyPicking(ref, text),
        ),
        // Eligiendo a mano, qué se elige y cómo terminar.
        if (view.pick case final pick?)
          FilledButton.tonalIcon(
            key: const Key('study-pick-done'),
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              '${switch (pick) {
                StudyMarkKind.summary => l10n.studyPickingSummary,
                StudyMarkKind.synthesis => l10n.studyPickingSynthesis,
                StudyMarkKind.keyword => l10n.studyPickingKeywords,
              }} · ${l10n.studyPickingDone}',
            ),
            onPressed: () {
              final notifier = ref.read(
                studyViewProvider(text.renditionId).notifier,
              );
              notifier.state = notifier.state.copyWith(pick: () => null);
            },
          ),
      ],
    );
  }
}

/// Un botón de estudiar: prendido, lleno con su color de resaltador y la
/// letra oscura, como lo que resalta; apagado, con un círculo de su color.
class _StudyChip extends StatelessWidget {
  const _StudyChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: CircleAvatar(
        backgroundColor: selected ? Colors.white54 : color,
        child: Icon(icon, size: 14, color: StudyPalette.ink),
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? StudyPalette.ink : scheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : null,
      ),
      selectedColor: color,
      side: BorderSide(color: selected ? color : scheme.outlineVariant),
      onSelected: (_) => onTap(),
    );
  }
}

/// Los botones de estudiar en una sola fila, que se desliza de costado si no
/// entra (F36): la barra de un lector a pantalla completa.
class StudyBar extends StatelessWidget {
  const StudyBar({
    required this.text,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    super.key,
  });

  final StudyText text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: StudyToggles(text: text),
  );
}
