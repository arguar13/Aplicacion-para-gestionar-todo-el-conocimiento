import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Apariencia» (Aa) del marco de lectura (F47, paso 1, captura 5).
Future<void> showReadingAppearance(
  BuildContext context, {
  required ReadingBodyKind bodyKind,
  required ReadingFrameController controller,
  required ThemeData appTheme,
}) => _showSheet(
  context,
  ReadingAppearanceSheet(
    bodyKind: bodyKind,
    controller: controller,
    appTheme: appTheme,
  ),
);

/// Abre la misma «Apariencia» desde Ajustes › Voz y lectura (F47, paso 7b),
/// sin un documento abierto: con todo lo que se guarda para los lectores
/// —la letra y su tamaño, el tono de la página, el resaltado y el modo— y
/// sin el zoom, que es de la página que se está viendo.
Future<void> showReadingAppearanceSettings(BuildContext context) => _showSheet(
  context,
  ReadingAppearanceSheet.saved(appTheme: Theme.of(context)),
);

Future<void> _showSheet(BuildContext context, Widget sheet) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => sheet,
  );
}

/// Lo de adentro de «Apariencia»: lo que se puede cambiar en el cuerpo que
/// se lee, y que **se guarda para todos los lectores**
/// (`readingAppearanceProvider`).
///
/// - **La fuente**, en el texto: el tipo, entre las cinco de lectura —cada
///   una escrita con su propia letra—, y el tamaño, con un deslizador.
/// - **La página**, en un PDF o una foto: el zoom y su tono (original, oscura
///   o sepia).
/// - **El color**: el «Resaltado de lectura», el fondo de la línea que suena.
/// - **El modo**: Sistema · Claro · Oscuro · Sepia, cada uno con su muestra.
///
/// Cada cambio se ve en el acto detrás de la hoja: el marco mira lo mismo.
///
/// Desde Ajustes ([ReadingAppearanceSheet.saved]) no hay un cuerpo detrás:
/// muestra todo lo que se guarda, con la página rotulada para un PDF o una
/// foto, y la muestra de la letra hace de vista previa.
class ReadingAppearanceSheet extends ConsumerWidget {
  const ReadingAppearanceSheet({
    required ReadingBodyKind this.bodyKind,
    required ReadingFrameController this.controller,
    required this.appTheme,
    super.key,
  });

  /// Sin un documento abierto: desde Ajustes › Voz y lectura (F47, paso 7b).
  const ReadingAppearanceSheet.saved({required this.appTheme, super.key})
    : bodyKind = null,
      controller = null;

  /// El cuerpo que se lee; `null` desde Ajustes, donde vale para todos.
  final ReadingBodyKind? bodyKind;

  /// El del marco abierto, que tiene el zoom de su página; `null` desde
  /// Ajustes.
  final ReadingFrameController? controller;

  /// El tema de la app, debajo del modo de lectura: el de «Sistema».
  final ThemeData appTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final appearance = ref.watch(readingAppearanceProvider);
    final notifier = ref.read(readingAppearanceProvider.notifier);

    return SingleChildScrollView(
      key: const Key('reading-appearance-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.f47P1AppearanceTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            l10n.f47P1AppearanceSaved,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (bodyKind == null ||
              bodyKind == ReadingBodyKind.text ||
              bodyKind == ReadingBodyKind.pageWithText) ...[
            _Heading(l10n.f47P1AppearanceFont),
            _FontChoices(
              selected: appearance.font,
              onSelected: (font) => unawaited(notifier.setFont(font)),
            ),
            const SizedBox(height: 12),
            _SizeSlider(
              scale: appearance.scale,
              onChanged: (value) => unawaited(notifier.setScale(value)),
            ),
            _Sample(appearance: appearance),
          ],
          if (bodyKind == null ||
              bodyKind == ReadingBodyKind.page ||
              bodyKind == ReadingBodyKind.pageWithText) ...[
            _Heading(l10n.f47P1AppearancePage),
            if (controller case final controller?)
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => switch (controller.zoom) {
                  final zoom? => _ZoomRow(zoom: zoom),
                  null => const SizedBox.shrink(),
                },
              )
            else
              // Desde Ajustes no hay página a la vista: se dice a qué se
              // aplica el tono.
              Text(
                l10n.f47P7bAppearancePageHint,
                key: const Key('reading-paper-hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            _PaperChoices(
              selected: appearance.paper,
              onSelected: (paper) => unawaited(notifier.setPaper(paper)),
            ),
          ],
          _Heading(l10n.f47P1AppearanceHighlight),
          _HighlightChoices(
            selected: appearance.highlight,
            onSelected: (highlight) =>
                unawaited(notifier.setHighlight(highlight)),
          ),
          _Heading(l10n.f47P1AppearanceMode),
          _ModeChoices(
            selected: appearance.mode,
            onSelected: (mode) => unawaited(notifier.setMode(mode)),
            appTheme: appTheme,
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// El nombre de cada letra y para qué es.
(String, String) readingFontNames(AppLocalizations l10n, ReadingFont font) =>
    switch (font) {
      ReadingFont.lora => ('Lora', l10n.f47P1FontLoraHint),
      ReadingFont.sourceSans => ('Source Sans', l10n.f47P1FontSourceSansHint),
      ReadingFont.inter => ('Inter', l10n.f47P1FontInterHint),
      ReadingFont.nunito => ('Nunito', l10n.f47P1FontNunitoHint),
      ReadingFont.atkinson => ('Atkinson', l10n.f47P1FontAtkinsonHint),
    };

/// El nombre del color de lo que suena: «Amarillo», «Durazno»…
String readingHighlightName(
  AppLocalizations l10n,
  ReadingHighlight highlight,
) => switch (highlight) {
  ReadingHighlight.yellow => l10n.f47P1HighlightYellow,
  ReadingHighlight.peach => l10n.f47P1HighlightPeach,
  ReadingHighlight.lilac => l10n.f47P1HighlightLilac,
  ReadingHighlight.lime => l10n.f47P1HighlightLime,
};

/// Las cinco letras, cada una escrita con su letra: se elige viéndola.
class _FontChoices extends StatelessWidget {
  const _FontChoices({required this.selected, required this.onSelected});

  final ReadingFont selected;
  final ValueChanged<ReadingFont> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        for (final font in ReadingFont.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ChoiceTile(
              key: Key('reading-font-${font.name}'),
              selected: font == selected,
              onTap: () => onSelected(font),
              leading: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: font.family,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              title: readingFontNames(l10n, font).$1,
              titleStyle: theme.textTheme.titleMedium?.copyWith(
                fontFamily: font.family,
              ),
              subtitle: readingFontNames(l10n, font).$2,
            ),
          ),
      ],
    );
  }
}

/// Una opción elegible: un renglón con su muestra, con borde de acento si es
/// la elegida y la marca de elegida para el lector de pantalla.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    this.titleStyle,
    this.subtitle,
    super.key,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final TextStyle? titleStyle;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                SizedBox(width: 40, child: Center(child: leading)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle),
                      if (subtitle case final subtitle?)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El tamaño de la letra, de 80 % a 160 %, de a 10.
class _SizeSlider extends StatelessWidget {
  const _SizeSlider({required this.scale, required this.onChanged});

  final double scale;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final percent = (scale * 100).round();
    return Row(
      children: [
        const Icon(Icons.text_decrease, size: 20),
        Expanded(
          child: Slider(
            key: const Key('reading-size'),
            value: scale,
            min: ReadingAppearanceNotifier.minScale,
            max: ReadingAppearanceNotifier.maxScale,
            divisions: ReadingAppearanceNotifier.scaleStops - 1,
            label: l10n.f47P1AppearanceSizeValue(percent),
            semanticFormatterCallback: (value) =>
                l10n.f47P1AppearanceSizeValue((value * 100).round()),
            onChanged: onChanged,
          ),
        ),
        const Icon(Icons.text_increase, size: 20),
        const SizedBox(width: 8),
        Text(
          l10n.f47P1AppearanceSizeValue(percent),
          key: const Key('reading-size-value'),
          style: theme.textTheme.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Cómo se ve lo que se lee con lo elegido: la letra, su tamaño y el
/// resaltado de lo que suena.
class _Sample extends StatelessWidget {
  const _Sample({required this.appearance});

  final ReadingAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = appearance.bodyStyle(theme);
    return Container(
      key: const Key('reading-appearance-sample'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: '${l10n.f47P1AppearanceSampleBefore} '),
            TextSpan(
              text: l10n.f47P1AppearanceSampleReading,
              style: style.copyWith(
                backgroundColor: appearance.highlight.color,
                color: StudyPalette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El zoom de la página: alejar, cuánto, acercar y ajustar al ancho.
class _ZoomRow extends StatelessWidget {
  const _ZoomRow({required this.zoom});

  final ReadingZoom zoom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.outlined(
          key: const Key('reading-zoom-out'),
          tooltip: l10n.f47P1AppearanceZoomOut,
          onPressed: zoom.zoomOut,
          icon: const Icon(Icons.zoom_out_rounded),
        ),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: zoom.level,
            builder: (context, level, _) => Text(
              l10n.f47P1AppearanceSizeValue((level * 100).round()),
              key: const Key('reading-zoom-value'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        IconButton.outlined(
          key: const Key('reading-zoom-in'),
          tooltip: l10n.f47P1AppearanceZoomIn,
          onPressed: zoom.zoomIn,
          icon: const Icon(Icons.zoom_in_rounded),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('reading-zoom-fit'),
          onPressed: zoom.fit,
          child: Text(l10n.f47P1AppearanceZoomFit),
        ),
      ],
    );
  }
}

/// El tono de la página: original, oscura o sepia.
class _PaperChoices extends StatelessWidget {
  const _PaperChoices({required this.selected, required this.onSelected});

  final ReadingPaper selected;
  final ValueChanged<ReadingPaper> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String label(ReadingPaper paper) => switch (paper) {
      ReadingPaper.original => l10n.f47P1PaperOriginal,
      ReadingPaper.dark => l10n.f47P1PaperDark,
      ReadingPaper.sepia => l10n.f47P1PaperSepia,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final paper in ReadingPaper.values)
          ChoiceChip(
            key: Key('reading-paper-${paper.name}'),
            label: Text(label(paper)),
            selected: paper == selected,
            onSelected: (_) => onSelected(paper),
          ),
      ],
    );
  }
}

/// El color de lo que suena: una muestra de cada uno, con su nombre.
class _HighlightChoices extends StatelessWidget {
  const _HighlightChoices({required this.selected, required this.onSelected});

  final ReadingHighlight selected;
  final ValueChanged<ReadingHighlight> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    String label(ReadingHighlight highlight) =>
        readingHighlightName(l10n, highlight);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final highlight in ReadingHighlight.values)
          Semantics(
            selected: highlight == selected,
            inMutuallyExclusiveGroup: true,
            button: true,
            label: label(highlight),
            excludeSemantics: true,
            onTap: () => onSelected(highlight),
            child: InkWell(
              key: Key('reading-highlight-${highlight.name}'),
              borderRadius: BorderRadius.circular(28),
              onTap: () => onSelected(highlight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: highlight.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: highlight == selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: highlight == selected ? 3 : 1,
                      ),
                    ),
                    child: highlight == selected
                        ? const Icon(
                            Icons.check_rounded,
                            color: StudyPalette.ink,
                          )
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(label(highlight)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// El modo: cada uno con su muestra —el papel y la letra que va a tener—.
class _ModeChoices extends StatelessWidget {
  const _ModeChoices({
    required this.selected,
    required this.onSelected,
    required this.appTheme,
  });

  final ReadingMode selected;

  /// El tema de la app, el de «Sistema»: la hoja se ve con el del marco.
  final ThemeData appTheme;
  final ValueChanged<ReadingMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String label(ReadingMode mode) => switch (mode) {
      ReadingMode.system => l10n.f47P1ModeSystem,
      ReadingMode.light => l10n.f47P1ModeLight,
      ReadingMode.dark => l10n.f47P1ModeDark,
      ReadingMode.sepia => l10n.f47P1ModeSepia,
    };
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final mode in ReadingMode.values)
          _ModeSwatch(
            key: Key('reading-mode-${mode.name}'),
            label: label(mode),
            // La muestra con los colores del modo, no los del marco: la de
            // «Sistema» es la de la app.
            theme: mode.themeOver(appTheme),
            selected: mode == selected,
            onTap: () => onSelected(mode),
          ),
      ],
    );
  }
}

class _ModeSwatch extends StatelessWidget {
  const _ModeSwatch({
    required this.label,
    required this.theme,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final ThemeData theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paper = theme.colorScheme.surface;
    final ink = theme.colorScheme.onSurface;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Text(
                'Aa',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: ReadingFont.lora.family,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
