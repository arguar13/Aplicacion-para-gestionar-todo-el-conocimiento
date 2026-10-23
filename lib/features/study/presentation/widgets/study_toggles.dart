import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Prende [layer] —el resumen o la síntesis— en [text], o lo apaga si ya
/// estaba (F36): es un interruptor de dos posiciones, nunca los dos encima.
/// Prenderlo analiza lo que falte.
Future<void> toggleStudyLayer(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
  StudyLayer layer,
) async {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  final on = view.state.layer != layer;
  view.state = view.state.copyWith(layer: () => on ? layer : null);
  if (on) await analyzeForStudyIfNeeded(ref, context, text);
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
  view.state = view.state.copyWith(layer: () => layer);
  await analyzeForStudyIfNeeded(ref, context, text);
}

/// Muestra u oculta las palabras clave de [text] (F36). Mostrarlas analiza lo
/// que falte: las propone la IA en la misma pasada.
Future<void> toggleStudyKeywords(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
) async {
  final view = ref.read(studyViewProvider(text.renditionId).notifier);
  final on = !view.state.keywords;
  view.state = view.state.copyWith(keywords: on);
  if (on) await analyzeForStudyIfNeeded(ref, context, text);
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
  unawaited(notifier.start(content: text.content, markdown: text.markdown));
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

/// Los tres botones de estudiar un texto (F36): **Resumir** y
/// **Sintetizar**, el interruptor de los dos resaltados, y **Palabras
/// clave**, con su lápiz para elegirlas a mano. Cada uno con su color de
/// resaltador.
///
/// Los mismos en la tarjeta del detalle y en la barra del lector a pantalla
/// completa: lo que se prende en uno se ve en el otro —ver
/// [studyViewProvider]—.
class StudyToggles extends ConsumerWidget {
  const StudyToggles({required this.text, super.key});

  final StudyText text;

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
          selected: view.layer == StudyLayer.summary,
          onTap: () => unawaited(
            toggleStudyLayer(ref, context, text, StudyLayer.summary),
          ),
        ),
        _StudyChip(
          key: const Key('study-toggle-synthesis'),
          icon: Icons.filter_center_focus_outlined,
          label: l10n.studySynthesize,
          color: palette.synthesis,
          selected: view.layer == StudyLayer.synthesis,
          onTap: () => unawaited(
            toggleStudyLayer(ref, context, text, StudyLayer.synthesis),
          ),
        ),
        _StudyChip(
          key: const Key('study-toggle-keywords'),
          icon: Icons.key_outlined,
          label: l10n.studyKeywords,
          color: palette.keyword,
          selected: view.showsKeywords,
          onTap: () => unawaited(toggleStudyKeywords(ref, context, text)),
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
