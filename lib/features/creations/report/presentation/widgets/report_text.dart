import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

/// La tipografía de un informe en pantalla: Lora en los títulos y Source
/// Sans 3 en el texto (el par «de libro», `CreationFontPair.book`), a un
/// tamaño y un interlineado para leer largo, con los colores del tema —los
/// nueve, claros y oscuros—. La letra que la persona agrandó en el sistema
/// se respeta sola: los tamaños son lógicos.
@immutable
class ReportTypography {
  const ReportTypography._({
    required this.accent,
    required this.ink,
    required this.muted,
    required this.keyword,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.sectionTitle,
    required this.subheading,
    required this.body,
    required this.small,
    required this.term,
  });

  factory ReportTypography.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const pair = CreationFontPair.book;
    // El del ícono del informe, llevado a 4,5:1 —lo de un texto— sobre las
    // dos superficies donde se escribe: la de las secciones y la de las
    // preguntas.
    final spec = defaultCreationKindSpec(StudyCreationKind.report).accent;
    final accent = CreationContrast.ensureOnAll(
      theme.brightness == Brightness.dark ? spec.dark : spec.light,
      [scheme.surfaceContainerLow, scheme.surfaceContainer, scheme.surface],
    );
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return ReportTypography._(
      accent: accent,
      ink: ink,
      muted: muted,
      keyword: StudyPalette.of(theme.brightness).keyword,
      kicker: pair.bodyStyle(
        size: 13,
        color: accent,
        weight: 700,
        height: 1.3,
        tracking: 0.06,
      ),
      title: pair.displayStyle(size: 30, color: ink, height: 1.18),
      subtitle: pair.bodyStyle(size: 17, color: muted, height: 1.45),
      sectionTitle: pair.displayStyle(size: 21, color: ink, height: 1.25),
      subheading: pair.displayStyle(size: 17.5, color: ink, height: 1.3),
      body: pair.bodyStyle(size: 16.5, color: ink, height: 1.58),
      small: pair.bodyStyle(size: 14, color: muted, height: 1.4),
      term: pair.displayStyle(size: 17.5, color: ink, height: 1.3),
    );
  }

  /// El color del informe: el de su ícono, legible sobre el tema.
  final Color accent;
  final Color ink;
  final Color muted;

  /// El rosa de las palabras clave (decisión 85), con la letra oscura
  /// encima en los dos modos, como un resaltador sobre papel.
  final Color keyword;

  final TextStyle kicker;
  final TextStyle title;
  final TextStyle subtitle;
  final TextStyle sectionTitle;
  final TextStyle subheading;
  final TextStyle body;
  final TextStyle small;
  final TextStyle term;

  /// [base] con lo de [inline]: la negrita, la itálica y el rosa de las
  /// palabras clave (en negrita, con la letra oscura).
  TextStyle styleOf(ReportInline inline, TextStyle base) {
    var style = base;
    if (inline.bold || inline.keyword) {
      style = style.copyWith(
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
      );
    }
    if (inline.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (inline.keyword) {
      style = style.copyWith(color: StudyPalette.ink, backgroundColor: keyword);
    }
    return style;
  }
}

/// [inlines] con su estilo sobre [style], en un solo párrafo.
class ReportRichText extends StatelessWidget {
  const ReportRichText({
    required this.inlines,
    required this.style,
    required this.typography,
    this.textAlign,
    super.key,
  });

  final List<ReportInline> inlines;
  final TextStyle style;
  final ReportTypography typography;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: style,
      children: [
        for (final inline in inlines)
          TextSpan(text: inline.text, style: typography.styleOf(inline, style)),
      ],
    ),
    textAlign: textAlign,
  );
}

/// Los bloques del texto de una sección, con su ritmo: los párrafos con aire
/// entre ellos, las viñetas pegadas, los subtítulos con más aire arriba.
class ReportBlocks extends StatelessWidget {
  const ReportBlocks({
    required this.blocks,
    required this.typography,
    super.key,
  });

  final List<ReportBlock> blocks;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    ReportBlock? previous;
    for (final block in blocks) {
      final gap = switch ((previous, block)) {
        (null, _) => 0.0,
        (ReportBullet(), ReportBullet()) => 6.0,
        (_, ReportSubheading()) => 20.0,
        _ => 12.0,
      };
      if (gap > 0) children.add(SizedBox(height: gap));
      children.add(_block(block));
      previous = block;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _block(ReportBlock block) {
    final t = typography;
    return switch (block) {
      ReportParagraph() => ReportRichText(
        inlines: block.inlines,
        style: t.body,
        typography: t,
      ),
      ReportSubheading() => ReportRichText(
        inlines: block.inlines,
        style: t.subheading,
        typography: t,
      ),
      ReportQuote() => Container(
        padding: const EdgeInsetsDirectional.only(start: 14),
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: t.accent, width: 3),
          ),
        ),
        child: ReportRichText(
          inlines: block.inlines,
          style: t.body.copyWith(fontStyle: FontStyle.italic),
          typography: t,
        ),
      ),
      ReportBullet(:final level, :final number) => Padding(
        padding: EdgeInsetsDirectional.only(start: level * 22.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: number == null ? 22 : 30,
              child: number == null
                  ? Padding(
                      // El punto, a la altura de la primera línea.
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        level == 0 ? '•' : '◦',
                        style: t.body.copyWith(
                          color: t.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : Text(
                      '$number.',
                      style: t.body.copyWith(
                        color: t.accent,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                      ),
                    ),
            ),
            Expanded(
              child: ReportRichText(
                inlines: block.inlines,
                style: t.body,
                typography: t,
              ),
            ),
          ],
        ),
      ),
    };
  }
}
