import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_sheets.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los botones de estudio del original de un documento procesado (F43, paso
/// 15, M5): **Resumen**, **Síntesis** y **Palabras clave**, el lugar donde se
/// marca —con la IA o a mano— y donde se prende y se apaga lo marcado.
///
/// - **Sin marcas**, el botón abre una hoja chica con dos opciones grandes:
///   «Con IA», con el modelo elegido y lo que va a consumir, y «A mano», que
///   pasa a elegir tocando en el original ([showOriginalStudyChoice]).
/// - **Con marcas**, el botón prende y apaga el resaltado, y queda recordado
///   por documento (`processedOriginalHiddenProvider`): las palabras clave,
///   una vez hechas, se ven en rosa cada vez que se abre el documento.
/// - **Su menú** —el ⋯ o mantenerlo apretado— ofrece rehacer con IA, retocar
///   a mano, ocultar o mostrar, y borrar las marcas ([showOriginalStudyMenu]).
/// - Cada uno con **su color de resaltador**, **cuántas marcas tiene** y **su
///   estado**: sin hacer, generándose con su avance, hecho u oculto. Debajo,
///   la **leyenda** de colores —con «Resumen y síntesis» cuando se ven los dos:
///   celeste con la línea verde— y, mientras la IA marca, la franja de siempre
///   con «Parar» ([StudyProgressStrip]).
/// - **Eligiendo a mano**, una línea dice qué se elige y cómo, con «Listo».
///   En el documento, donde el original es su primera página quieta,
///   [onOpenOriginal] lleva al original entero, donde se toca.
///
/// Sin animaciones: el avance es un número y una barra que se llenan, nunca
/// una ruedita que gira. Entra en 360 dp con la letra al doble: los botones se
/// acomodan en renglones y sus textos se parten.
class OriginalStudyBar extends ConsumerStatefulWidget {
  const OriginalStudyBar({required this.study, this.onOpenOriginal, super.key});

  final OriginalStudy study;

  /// Lleva al original entero, para elegir a mano tocándolo. `null` en el
  /// original entero, donde ya se toca.
  final VoidCallback? onOpenOriginal;

  @override
  ConsumerState<OriginalStudyBar> createState() => _OriginalStudyBarState();
}

class _OriginalStudyBarState extends ConsumerState<OriginalStudyBar> {
  /// El texto propio del documento —el que se analiza— y lo estudiado de él,
  /// ya cargados: lo que usan los botones al tocarlos, sin volver a leer un
  /// libro entero con cada toque.
  ProcessedStudyText? _own;
  DocumentStudy? _ownStudy;

  /// Si ya se pidió completar las palabras clave que faltan.
  var _filled = false;

  /// Lo analizado antes de que cada oración llevara sus palabras clave se
  /// completa al mostrarlas (decisión 85): acá se ven de entrada, así que se
  /// pide apenas están el texto y lo estudiado. Una vez por pantalla, y
  /// `ensureStudyKeywords` lo hace una vez por texto en la sesión.
  void _fillOnce(StudyView view) {
    final own = _own;
    if (_filled || own == null || !view.keywords) return;
    if (!(_ownStudy?.started ?? false)) return;
    _filled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ensureStudyKeywords(ref, own.asStudyText));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final study = widget.study;
    final key = study.original.renditionId;
    final view = ref.watch(studyViewProvider(key));
    final marks =
        ref.watch(documentStudyProvider(key)).valueOrNull ??
        DocumentStudy.notStarted;
    final analysis = ref.watch(studyAnalysisProvider(study.ownKey));
    final own = _own = ref
        .watch(processedStudyTextProvider(study.documentId))
        .valueOrNull
        ?.toNullable();
    _ownStudy = ref.watch(documentStudyProvider(study.ownKey)).valueOrNull;
    _fillOnce(view);

    return Semantics(
      container: true,
      label: l10n.processedOriginalLayers,
      child: Column(
        key: const Key('original-study-bar'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in StudyMarkKind.values)
                _StudyButton(
                  key: Key('original-study-${kind.name}'),
                  kind: kind,
                  count: marks.of(kind).length,
                  shown: originalShows(view, kind),
                  progress: switch (analysis) {
                    StudyAnalysisRunning(:final progress) =>
                      progress?.percent ?? 0,
                    _ => null,
                  },
                  onTap: () => unawaited(_tap(kind)),
                  onMenu: () => unawaited(_menu(kind)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Legend(view: view),
          if (view.pick case final pick?)
            _PickingLine(
              kind: pick,
              onOpenOriginal: widget.onOpenOriginal,
              onDone: () => stopPickingOnOriginal(ref, study),
            ),
          // La franja de siempre: la parte que va y «Parar»; si se cortó,
          // «Reintentar». Mide el análisis del texto propio, que es el que
          // marca el original.
          if (own != null) StudyProgressStrip(text: own.asStudyText),
        ],
      ),
    );
  }

  /// Sin marcas, la hoja de los dos caminos; con marcas —o mientras la IA las
  /// arma—, prender o apagar. Lo decide lo guardado, no lo que ya cargó la
  /// pantalla (F39).
  Future<void> _tap(StudyMarkKind kind) async {
    final study = widget.study;
    final running =
        ref.read(studyAnalysisProvider(study.ownKey)) is StudyAnalysisRunning;
    // Lo guardado, por el mismo proveedor que la barra ya mira: al día con
    // cada cambio, y sin esperar si ya llegó.
    final stored = await ref.read(
      documentStudyProvider(study.original.renditionId).future,
    );
    if (!mounted) return;
    if (stored.of(kind).isNotEmpty || running) {
      final view = ref.read(studyViewProvider(study.original.renditionId));
      await setOriginalShown(
        ref,
        study,
        kind,
        shown: !originalShows(view, kind),
        own: _own,
      );
      return;
    }
    await _choose(kind);
  }

  Future<void> _choose(StudyMarkKind kind) async {
    final study = widget.study;
    final choice = await showOriginalStudyChoice(context, study, kind);
    if (choice == null || !mounted) return;
    switch (choice) {
      case OriginalStudyChoice.ai:
        await markOriginalWithAi(
          ref,
          context,
          study,
          kind,
          own: _own,
          complete: _ownStudy?.complete ?? false,
        );
      case OriginalStudyChoice.manual:
        await _pick(kind);
    }
  }

  Future<void> _pick(StudyMarkKind kind) async {
    await pickOnOriginal(ref, widget.study, kind, own: _own);
    widget.onOpenOriginal?.call();
  }

  Future<void> _menu(StudyMarkKind kind) async {
    final study = widget.study;
    final view = ref.read(studyViewProvider(study.original.renditionId));
    final count =
        ref
            .read(documentStudyProvider(study.original.renditionId))
            .valueOrNull
            ?.of(kind)
            .length ??
        0;
    final action = await showOriginalStudyMenu(
      context,
      kind: kind,
      count: count,
      shown: originalShows(view, kind),
      running:
          ref.read(studyAnalysisProvider(study.ownKey)) is StudyAnalysisRunning,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case OriginalStudyAction.redoWithAi:
        final confirmed = await showOriginalRedoSheet(context, study);
        if (confirmed && mounted) {
          await redoOriginalWithAi(ref, context, study, kind, own: _own);
        }
      case OriginalStudyAction.retouch:
        await _pick(kind);
      case OriginalStudyAction.hide:
        await setOriginalShown(ref, study, kind, shown: false);
      case OriginalStudyAction.show:
        await setOriginalShown(ref, study, kind, shown: true, own: _own);
      case OriginalStudyAction.clear:
        final confirmed = await confirmOriginalClear(context, kind);
        if (confirmed && mounted) {
          await clearOriginalMarks(ref, context, study, kind);
        }
    }
  }
}

/// El nombre de cada botón, como en la leyenda.
String originalStudyName(AppLocalizations l10n, StudyMarkKind kind) =>
    switch (kind) {
      StudyMarkKind.summary => l10n.studyLegendSummary,
      StudyMarkKind.synthesis => l10n.studyLegendSynthesis,
      StudyMarkKind.keyword => l10n.studyKeywords,
    };

/// El color de resaltador de [kind].
Color originalStudyColor(StudyPalette palette, StudyMarkKind kind) =>
    switch (kind) {
      StudyMarkKind.summary => palette.summary,
      StudyMarkKind.synthesis => palette.synthesis,
      StudyMarkKind.keyword => palette.keyword,
    };

/// El ícono de cada uno, el mismo de la Biblioteca.
IconData originalStudyIcon(StudyMarkKind kind) => switch (kind) {
  StudyMarkKind.summary => Icons.notes_outlined,
  StudyMarkKind.synthesis => Icons.filter_center_focus_outlined,
  StudyMarkKind.keyword => Icons.key_outlined,
};

/// Cuántas marcas son [count], dicho como se cuentan: oraciones del resumen o
/// de la síntesis, palabras clave.
String originalStudyCount(
  AppLocalizations l10n,
  StudyMarkKind kind,
  int count,
) => kind == StudyMarkKind.keyword
    ? l10n.studyKeywordCount(count)
    : l10n.studySentenceCount(count);

/// Un botón de estudio: grande, redondeado y con su color de resaltador.
///
/// - **Hecho y a la vista**: lleno con su color y la letra oscura, como lo que
///   resalta.
/// - **Oculto**: con el borde de su color, apagado, y el ojo tachado.
/// - **Sin hacer**: tenue, con un «+» en su color.
/// - **Generándose**: un anillo que se llena con el avance, sin girar.
///
/// A la derecha, cuántas marcas tiene y el ⋯ de su menú.
class _StudyButton extends StatelessWidget {
  const _StudyButton({
    required this.kind,
    required this.count,
    required this.shown,
    required this.progress,
    required this.onTap,
    required this.onMenu,
    super.key,
  });

  final StudyMarkKind kind;
  final int count;
  final bool shown;

  /// El avance de la IA, de 0 a 100, mientras marca; `null` si no.
  final int? progress;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = originalStudyColor(StudyPalette.of(theme.brightness), kind);
    final name = originalStudyName(l10n, kind);
    final generating = progress != null;
    final done = count > 0;
    final filled = done && shown;
    final ink = filled ? StudyPalette.ink : scheme.onSurface;
    final state = generating
        ? l10n.f43OrigStateGenerating(progress!)
        : !done
        ? l10n.f43OrigStateNone
        : shown
        ? l10n.f43OrigStateDone(kind.name)
        : l10n.f43OrigStateHidden(kind.name);

    final badge = switch ((generating, done)) {
      (true, _) => SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          // Un anillo que se llena: un valor siempre, nunca la ruedita que
          // gira sola (sin animaciones).
          value: progress! / 100,
          strokeWidth: 3,
          color: filled ? StudyPalette.ink : color,
          backgroundColor: (filled ? StudyPalette.ink : color).withValues(
            alpha: 0.2,
          ),
        ),
      ),
      (false, true) => Icon(
        shown ? originalStudyIcon(kind) : Icons.visibility_off_outlined,
        size: 18,
        color: filled ? StudyPalette.ink : color,
      ),
      (false, false) => const Icon(
        Icons.add,
        size: 20,
        color: StudyPalette.ink,
      ),
    };

    return Semantics(
      button: true,
      label: l10n.f43OrigButtonSemantics(
        name,
        originalStudyCount(l10n, kind, count),
        state,
      ),
      excludeSemantics: true,
      onLongPress: done ? onMenu : null,
      child: Material(
        color: filled
            ? color
            : done
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: filled
                ? color
                : done
                ? color.withValues(alpha: 0.9)
                : scheme.outlineVariant,
            width: done ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: done ? onMenu : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 8, done ? 0 : 14, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? Colors.white.withValues(alpha: 0.45)
                          : done || generating
                          ? color.withValues(alpha: 0.18)
                          : color,
                    ),
                    child: badge,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          state,
                          key: Key('original-study-state-${kind.name}'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: filled
                                ? StudyPalette.ink.withValues(alpha: 0.75)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (done) ...[
                    const SizedBox(width: 10),
                    _CountBadge(count: count, filled: filled, color: color),
                    IconButton(
                      key: Key('original-study-more-${kind.name}'),
                      tooltip: l10n.f43OrigMoreTooltip(name),
                      visualDensity: VisualDensity.compact,
                      color: ink,
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: onMenu,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cuántas marcas tiene: un número en una pastilla.
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.count,
    required this.filled,
    required this.color,
  });

  final int count;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? Colors.white.withValues(alpha: 0.55) : color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: StudyPalette.ink,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Los colores y qué es cada uno; con el resumen y la síntesis a la vista,
/// también cómo se ve una oración de los dos.
class _Legend extends StatelessWidget {
  const _Legend({required this.view});

  final StudyView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = StudyPalette.of(theme.brightness);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget entry(Color color, String label, {Color? line, Key? key}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: line == null
                ? null
                : Border(bottom: BorderSide(color: line, width: 3)),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: style)),
      ],
    );

    return Wrap(
      key: const Key('original-study-legend'),
      spacing: 16,
      runSpacing: 4,
      children: [
        entry(palette.summary, l10n.studyLegendSummary),
        entry(palette.synthesis, l10n.studyLegendSynthesis),
        entry(palette.keyword, l10n.studyKeywords),
        if (view.summary && view.synthesis)
          entry(
            palette.synthesis,
            l10n.f43OrigLegendBoth,
            line: StudyPalette.summaryLine,
            key: const Key('original-study-legend-both'),
          ),
      ],
    );
  }
}

/// Eligiendo a mano: qué se elige, cómo, y «Listo». Desde el documento,
/// además, el original entero donde se toca.
class _PickingLine extends StatelessWidget {
  const _PickingLine({
    required this.kind,
    required this.onDone,
    this.onOpenOriginal,
  });

  final StudyMarkKind kind;
  final VoidCallback onDone;
  final VoidCallback? onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = originalStudyColor(StudyPalette.of(theme.brightness), kind);
    final (title, hint) = switch (kind) {
      StudyMarkKind.summary => (
        l10n.studyPickingSummary,
        l10n.f43OrigPickHintSentences,
      ),
      StudyMarkKind.synthesis => (
        l10n.studyPickingSynthesis,
        l10n.f43OrigPickHintSentences,
      ),
      StudyMarkKind.keyword => (
        l10n.studyPickingKeywords,
        l10n.f43OrigPickHintWords(kMaxKeywordsPerSentence),
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        key: const Key('original-study-picking'),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.touch_app_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (onOpenOriginal case final open?)
                  TextButton.icon(
                    key: const Key('original-study-pick-open'),
                    icon: const Icon(Icons.open_in_full, size: 18),
                    label: Text(l10n.f43OrigPickOpen),
                    onPressed: open,
                  ),
                FilledButton.tonalIcon(
                  key: const Key('original-study-pick-done'),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(l10n.studyPickingDone),
                  onPressed: onDone,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
