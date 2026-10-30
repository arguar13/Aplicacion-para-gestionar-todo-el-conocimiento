import 'dart:async';
import 'dart:math';

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
import 'package:sinapsis/features/study/presentation/widgets/study_progress_strip.dart';
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
/// - **Una fila de tres fichas compactas** (F45, paso 4), del mismo alto, cada
///   una con **su color de resaltador** —el punto, que hace de leyenda: ya no
///   hay una leyenda aparte que repita los tres colores—, **su estado** —«Sin
///   hacer», «Haciendo… 40 %», «Hecho» u «Oculto»— y **cuántas marcas
///   tiene**. Debajo, solo con el resumen y la síntesis a la vista, cómo se
///   ve una oración de los dos: celeste con la línea verde. Y, mientras la IA
///   marca, la franja de siempre con «Parar» ([StudyProgressStrip]).
/// - **Eligiendo a mano**, una línea dice qué se elige y cómo, con «Listo».
///   En el documento, donde el original es su primera página quieta,
///   [onOpenOriginal] lleva al original entero, donde se toca.
///
/// Sin animaciones: el avance es un número y una barra que se llenan, nunca
/// una ruedita que gira. Entra en 360 dp con la letra al doble: las fichas
/// pasan a dos renglones —o a uno cada una— sin cortar una palabra.
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
          _StudyChips(
            chips: [
              for (final kind in StudyMarkKind.values)
                _StudyChip(
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
          if (view.summary && view.synthesis) const _BothLegend(),
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

/// Las tres fichas en una fila, del mismo ancho y el mismo alto (F45, paso
/// 4); si no entran —360 dp con la letra al doble—, en dos renglones: las dos
/// primeras arriba y la tercera abajo, a lo ancho. Si tampoco, una debajo de
/// la otra. Nunca se corta una palabra: la cuenta mide la palabra más larga de
/// cada ficha con la letra de ahora.
class _StudyChips extends StatelessWidget {
  const _StudyChips({required this.chips});

  final List<_StudyChip> chips;

  /// El aire entre una ficha y la otra.
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final needed = chips
        .map((chip) => chip.minWidth(context))
        .fold<double>(0, max);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perRow = studyChipsPerRow(
          width: width,
          needed: needed,
          count: chips.length,
        );
        final rows = [
          for (var start = 0; start < chips.length; start += perRow)
            chips.sublist(start, min(start + perRow, chips.length)),
        ];
        return Column(
          key: Key('original-study-chips-$perRow'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (column, chip) in row.indexed) ...[
                      if (column > 0) const SizedBox(width: gap),
                      Expanded(child: chip),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Cuántas fichas van por renglón en [width]: todas si cada una tiene el
/// ancho que necesita ([needed]), si no la mitad redondeada para arriba —dos
/// renglones—, y si tampoco, una.
@visibleForTesting
int studyChipsPerRow({
  required double width,
  required double needed,
  required int count,
}) {
  double each(int perRow) => (width - _StudyChips.gap * (perRow - 1)) / perRow;
  if (each(count) >= needed) return count;
  final half = (count + 1) ~/ 2;
  if (half > 1 && each(half) >= needed) return half;
  return 1;
}

/// Una ficha de estudio (F45, paso 4): compacta, del alto de sus vecinas, con
/// su color, su estado y un toque para crearla o verla.
///
/// - **El punto de color** es la leyenda: el color de su resaltador, lleno a
///   la vista y hueco si está oculto.
/// - **Hecha y a la vista**: llena con su color y la letra oscura, como lo que
///   resalta, con cuántas marcas tiene y el ⋯ de su menú.
/// - **Oculta**: con el borde de su color y «Oculto».
/// - **Sin hacer**: tenue, con «Sin hacer»; tocarla crea.
/// - **Haciéndose**: «Haciendo… 40 %» y una barra que se llena, sin girar.
class _StudyChip extends StatelessWidget {
  const _StudyChip({
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

  bool get _done => count > 0;

  static const _padding = EdgeInsets.fromLTRB(10, 8, 2, 8);
  static const _dot = 10.0;
  static const _dotGap = 6.0;
  static const _menu = 32.0;

  /// El aire a la derecha del nombre y de la barra, que no llegan al ⋯.
  static const _end = 8.0;

  TextStyle? _nameStyle(ThemeData theme) =>
      theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);

  TextStyle? _stateStyle(ThemeData theme) => theme.textTheme.labelSmall;

  String _state(AppLocalizations l10n) {
    if (progress case final percent?) return l10n.f45S4StateWorking(percent);
    if (!_done) return l10n.f43OrigStateNone;
    return shown
        ? l10n.f43OrigStateDone(kind.name)
        : l10n.f43OrigStateHidden(kind.name);
  }

  /// El ancho que necesita para no cortar ninguna palabra con la letra de
  /// ahora: la más larga de su nombre, con el punto; o la más larga de su
  /// estado —también la de «Haciendo… 100 %», para que la fila no cambie de
  /// forma mientras la IA avanza— con el ⋯ al lado.
  double minWidth(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double widest(String text, TextStyle? style) => text
        .split(RegExp(r'\s+'))
        .map((word) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        })
        .fold<double>(0, max);
    final name =
        _dot +
        _dotGap +
        widest(originalStudyName(l10n, kind), _nameStyle(theme)) +
        _end;
    final state =
        [
          widest(l10n.f45S4StateWorking(100), _stateStyle(theme)),
          widest(_state(l10n), _stateStyle(theme)),
          if (_done) widest(_countText, _stateStyle(theme)),
        ].fold<double>(0, max) +
        (_done ? _menu : _end);
    // Un píxel de más: lo que mide el texto y lo que ocupa redondean
    // distinto.
    return _padding.horizontal + max(name, state) + 1;
  }

  /// Cuántas marcas tiene, al lado del estado: «Hecho · 3».
  String get _countText => '· $count';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = originalStudyColor(StudyPalette.of(theme.brightness), kind);
    final name = originalStudyName(l10n, kind);
    final generating = progress != null;
    final filled = _done && shown;
    final ink = filled ? StudyPalette.ink : scheme.onSurface;
    final soft = filled
        ? StudyPalette.ink.withValues(alpha: 0.75)
        : scheme.onSurfaceVariant;
    final state = _state(l10n);

    return Semantics(
      button: true,
      label: l10n.f43OrigButtonSemantics(
        name,
        originalStudyCount(l10n, kind, count),
        state,
      ),
      excludeSemantics: true,
      onTap: onTap,
      onTapHint: !_done && !generating
          ? l10n.f45S4ChipCreateHint
          : shown
          ? l10n.f45S4ChipHideHint
          : l10n.f45S4ChipShowHint,
      onLongPress: _done ? onMenu : null,
      onLongPressHint: _done ? l10n.f43OrigMoreTooltip(name) : null,
      child: Material(
        color: filled
            ? color
            : _done
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: filled
                ? color
                : _done
                ? color.withValues(alpha: 0.9)
                : scheme.outlineVariant,
            width: _done ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: _done ? onMenu : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: _padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: _end),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // Centrado con el primer renglón del nombre.
                          padding: const EdgeInsets.only(top: 5),
                          child: _Dot(
                            key: Key('original-study-dot-${kind.name}'),
                            color: filled ? StudyPalette.ink : color,
                            hollow: _done && !shown,
                          ),
                        ),
                        const SizedBox(width: _dotGap),
                        Expanded(
                          child: Text(
                            name,
                            style: _nameStyle(theme)?.copyWith(color: ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: _done ? 0 : _end),
                          child: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                state,
                                key: Key('original-study-state-${kind.name}'),
                                style: _stateStyle(
                                  theme,
                                )?.copyWith(color: soft),
                              ),
                              if (_done)
                                Text(
                                  _countText,
                                  key: Key('original-study-count-${kind.name}'),
                                  style: _stateStyle(theme)?.copyWith(
                                    color: soft,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_done)
                        SizedBox.square(
                          dimension: _menu,
                          child: IconButton(
                            key: Key('original-study-more-${kind.name}'),
                            tooltip: l10n.f43OrigMoreTooltip(name),
                            padding: EdgeInsets.zero,
                            color: ink,
                            icon: const Icon(Icons.more_vert, size: 18),
                            onPressed: onMenu,
                          ),
                        ),
                    ],
                  ),
                  if (progress case final percent?) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: _end),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          key: Key('original-study-progress-${kind.name}'),
                          // Una barra que se llena: un valor siempre, nunca la
                          // que va y viene sola (sin animaciones).
                          value: percent / 100,
                          minHeight: 4,
                          color: filled ? StudyPalette.ink : color,
                          backgroundColor: (filled ? StudyPalette.ink : color)
                              .withValues(alpha: 0.2),
                        ),
                      ),
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

/// El punto de color de una ficha: su resaltador. Hueco, con el borde de su
/// color, si lo marcado está oculto.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.hollow, super.key});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Container(
    width: _StudyChip._dot,
    height: _StudyChip._dot,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? null : color,
      border: Border.all(color: color, width: 2),
    ),
  );
}

/// Con el resumen y la síntesis a la vista, cómo se ve una oración de los
/// dos: celeste con la línea verde. Es lo único que los puntos de las fichas
/// no dicen solos.
class _BothLegend extends StatelessWidget {
  const _BothLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = StudyPalette.of(theme.brightness);

    return Padding(
      key: const Key('original-study-legend-both'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: palette.synthesis,
              borderRadius: BorderRadius.circular(3),
              border: const Border(
                bottom: BorderSide(color: StudyPalette.summaryLine, width: 3),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.f43OrigLegendBoth,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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
