import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/creation_textures.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_background_painter.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';

/// La ilustración ya hecha de una diapositiva, por su referencia (la ruta o
/// la clave guardada en `Slide.illustrationRef`), o null si no se encuentra:
/// entonces se dibuja la de reserva.
typedef SlideIllustrationResolver = ImageProvider? Function(String reference);

/// Lo que todo diseño de diapositiva necesita saber además de su contenido.
@immutable
class SlideContext {
  const SlideContext({
    required this.style,
    required this.slide,
    required this.index,
    required this.total,
    this.sectionNumber = 0,
    this.illustrations,
  });

  final DeckStyle style;
  final Slide slide;

  /// La posición en el mazo, desde 0.
  final int index;
  final int total;

  /// El número de la parte, si es una sección (desde 1).
  final int sectionNumber;

  final SlideIllustrationResolver? illustrations;

  DeckTemplate get template => style.template;

  /// Una semilla estable para lo que se dibuja «al azar» en esta diapositiva.
  int get seed => index * 7 + slide.headline.length;
}

/// El cuadro de toda diapositiva: el fondo de la plantilla, los márgenes y,
/// abajo, el número y el pie con el título del mazo.
class SlideFrame extends StatelessWidget {
  const SlideFrame({
    required this.context,
    required this.child,
    this.padded = true,
    this.footerLeft,
    super.key,
  });

  final SlideContext context;
  final Widget child;

  /// Sin márgenes: el diseño los maneja él (una banda a sangre).
  final bool padded;

  /// Dónde empieza el pie, si no es en el margen: después de una banda de
  /// color a la izquierda, para no escribir el título del mazo encima.
  final double? footerLeft;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final showFooter =
        context.slide.layout != SlideLayout.cover && style.footerHeight > 0;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: DeckBackgroundPainter(
                style: style,
                layout: context.slide.layout,
                index: context.index,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: padded
                ? EdgeInsets.fromLTRB(
                    style.marginX,
                    style.marginY,
                    style.marginX,
                    style.marginY + (showFooter ? style.footerHeight : 0),
                  )
                : EdgeInsets.zero,
            child: child,
          ),
        ),
        if (showFooter)
          Positioned(
            left: footerLeft ?? style.marginX,
            right: style.marginX,
            bottom: style.marginY * 0.55,
            height: style.footerHeight * 0.7,
            child: _Footer(context: context),
          ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.context});

  final SlideContext context;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final design = style.design;
    final color = style.muted;
    final number = '${context.index + 1}'.padLeft(2, '0');
    return Row(
      children: [
        if (design.footer && style.deckTitle.isNotEmpty)
          Expanded(
            child: Text(
              style.deckTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.small(size: 24, color: color),
            ),
          )
        else
          const Spacer(),
        if (design.numbering) ...[
          const SizedBox(width: 24),
          Text(
            number,
            style: style.figure(size: 26, color: color, weight: 500),
          ),
          Text(
            ' / ${'${context.total}'.padLeft(2, '0')}',
            style: style.figure(
              size: 26,
              color: color.withValues(alpha: 0.6),
              weight: 400,
            ),
          ),
        ],
      ],
    );
  }
}

/// El título de una diapositiva de contenido, con el adorno de la plantilla.
/// Ocupa a lo sumo [maxHeight]; un título largo achica su letra.
class SlideTitle extends StatelessWidget {
  const SlideTitle({
    required this.context,
    required this.text,
    this.maxHeight = 230,
    super.key,
  });

  final SlideContext context;
  final String text;
  final double maxHeight;

  /// El trazo del resaltador: el acento sobre el fondo, tan fuerte como deje
  /// que el título se siga leyendo encima a 4,5:1 (en las noches, el acento
  /// pleno taparía la letra clara).
  static Color highlightOf(CreationPalette palette) {
    for (var alpha = 0.55; alpha > 0.1; alpha -= 0.05) {
      final mark = Color.alphaBlend(
        palette.accent.withValues(alpha: alpha),
        palette.background,
      );
      if (CreationContrast.ratio(palette.text, mark) >= 4.5) return mark;
    }
    return Color.alphaBlend(
      palette.accent.withValues(alpha: 0.1),
      palette.background,
    );
  }

  @override
  Widget build(BuildContext buildContext) {
    if (text.isEmpty) return const SizedBox.shrink();
    final style = context.style;
    final template = style.template;
    final palette = style.palette;
    final centered = template.centeredTitles;
    final look = template.title;
    final onBand = look == TitleLook.band;
    final titleStyle = style.title(
      color: onBand ? palette.onPrimary : palette.text,
    );
    final title = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: FitText(
        style.titleCase(text),
        style: look == TitleLook.glow
            ? titleStyle.copyWith(
                shadows: [
                  Shadow(color: palette.primary, blurRadius: 28),
                  Shadow(
                    color: palette.primary.withValues(alpha: 0.6),
                    blurRadius: 60,
                  ),
                ],
              )
            : titleStyle,
        maxLines: 3,
        minScale: 0.55,
        textAlign: centered ? TextAlign.center : TextAlign.start,
      ),
    );
    final cross = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return switch (look) {
      TitleLook.plain || TitleLook.glow => title,
      // El resaltador va detrás del comienzo del título, bajo su último
      // tercio de alto: sobre la primera línea si es una sola, entre las
      // líneas si son más; nunca tapa la letra, que va encima.
      TitleLook.highlight => Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: centered
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              child: Container(
                width: style.canvas.width * 0.24,
                height: style.titleSize * 0.42,
                margin: EdgeInsets.only(bottom: style.gap * 0.15),
                decoration: BoxDecoration(
                  color: highlightOf(palette),
                  borderRadius: BorderRadius.circular(style.titleSize * 0.08),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: style.gap * 0.3),
            child: title,
          ),
        ],
      ),
      TitleLook.underline => Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          SizedBox(height: style.gap * 0.55),
          Container(
            width: 112,
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(
                colors: [palette.primary, palette.accent],
              ),
            ),
          ),
        ],
      ),
      TitleLook.rule => Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${context.index + 1}'.padLeft(2, '0'), style: style.kicker()),
          SizedBox(height: style.gap * 0.4),
          title,
        ],
      ),
      TitleLook.band => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: style.gap,
          vertical: style.gap * 0.6,
        ),
        decoration: BoxDecoration(
          color: palette.primary,
          borderRadius: BorderRadius.circular(template.radius),
        ),
        child: title,
      ),
      TitleLook.bar => Container(
        padding: EdgeInsets.only(left: style.gap * 0.8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.primary, width: 12)),
        ),
        child: title,
      ),
      TitleLook.hand => Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          SizedBox(
            width: 340,
            height: 26,
            child: CustomPaint(
              painter: _HandUnderlinePainter(
                color: palette.primary,
                seed: context.index,
              ),
            ),
          ),
        ],
      ),
    };
  }
}

class _HandUnderlinePainter extends CustomPainter {
  const _HandUnderlinePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    CreationTextures.handLine(
      canvas,
      Offset(0, size.height * 0.6),
      Offset(size.width, size.height * 0.45),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8
        ..color = color,
      seed: seed,
      jitter: 4,
    );
  }

  @override
  bool shouldRepaint(_HandUnderlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// La marca de una viñeta, dibujada a la escala del texto.
class BulletMarkView extends StatelessWidget {
  const BulletMarkView({
    required this.style,
    required this.mark,
    required this.fontSize,
    this.index = 0,
    this.color,
    super.key,
  });

  final DeckStyle style;
  final BulletMark mark;
  final double fontSize;
  final int index;
  final Color? color;

  /// El ancho que ocupa la marca con su aire, a [fontSize].
  static double widthFor(BulletMark mark, double fontSize) => switch (mark) {
    BulletMark.numeral => fontSize * 1.7,
    BulletMark.check ||
    BulletMark.arrow ||
    BulletMark.prompt => fontSize * 1.35,
    _ => fontSize * 1.1,
  };

  @override
  Widget build(BuildContext context) {
    final palette = style.palette;
    final tint = color ?? palette.primary;
    final s = fontSize;
    // La marca se centra en la primera línea del texto.
    final lineHeight = s * CreationFontPair.bodyHeight;
    Widget mark;
    switch (this.mark) {
      case BulletMark.dash:
        mark = Container(width: s * 0.55, height: s * 0.1, color: tint);
      case BulletMark.dot:
        mark = Container(
          width: s * 0.3,
          height: s * 0.3,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        );
      case BulletMark.square:
        mark = Container(width: s * 0.28, height: s * 0.28, color: tint);
      case BulletMark.diamond:
        mark = Transform.rotate(
          angle: math.pi / 4,
          child: Container(width: s * 0.26, height: s * 0.26, color: tint),
        );
      case BulletMark.numeral:
        mark = Text(
          '${index + 1}'.padLeft(2, '0'),
          maxLines: 1,
          style: style.figure(size: s * 0.72, color: palette.accentText),
        );
      case BulletMark.check:
        mark = Icon(Icons.check_rounded, size: s * 0.9, color: tint);
      case BulletMark.arrow:
        mark = Icon(Icons.arrow_forward_rounded, size: s * 0.85, color: tint);
      case BulletMark.chalk:
        mark = SizedBox(
          width: s * 0.6,
          height: s * 0.3,
          child: CustomPaint(
            painter: _HandUnderlinePainter(color: tint, seed: index + 7),
          ),
        );
      case BulletMark.glow:
        mark = Container(
          width: s * 0.28,
          height: s * 0.28,
          decoration: BoxDecoration(
            color: tint,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: tint, blurRadius: s * 0.5),
              BoxShadow(color: tint.withValues(alpha: 0.5), blurRadius: s),
            ],
          ),
        );
      case BulletMark.pill:
        mark = Container(
          width: s * 0.5,
          height: s * 0.24,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(s),
          ),
        );
      case BulletMark.prompt:
        mark = Text(
          '>',
          maxLines: 1,
          style: style.figure(
            size: s * 0.9,
            color: color ?? palette.accentText,
          ),
        );
      case BulletMark.shape:
        // El círculo, el cuadrado y el triángulo, cada uno de su color; con
        // un color pedido (una columna), todos de ese.
        final tints = [palette.primary, palette.secondary, palette.accent];
        final fill = color ?? tints[index % 3];
        mark = SizedBox.square(
          dimension: s * 0.34,
          child: CustomPaint(
            painter: _ShapeMarkPainter(shape: index % 3, color: fill),
          ),
        );
    }
    return SizedBox(
      height: lineHeight,
      child: Align(alignment: Alignment.centerLeft, child: mark),
    );
  }
}

class _ShapeMarkPainter extends CustomPainter {
  const _ShapeMarkPainter({required this.shape, required this.color});

  /// 0 el círculo, 1 el cuadrado, 2 el triángulo.
  final int shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rect = Offset.zero & size;
    switch (shape) {
      case 0:
        canvas.drawCircle(rect.center, size.shortestSide / 2, paint);
      case 1:
        canvas.drawRect(rect.deflate(size.width * 0.06), paint);
      default:
        canvas.drawPath(
          Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_ShapeMarkPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

/// Las viñetas de [items] como textos de un grupo que se ajusta junto.
List<FitTextItem> bulletItems(
  DeckStyle style,
  List<String> items, {
  double? fontSize,
  Color? color,
  Color? markColor,
  double gapFactor = 0.5,
  BulletMark? mark,
}) {
  final size = fontSize ?? style.bodySize;
  final bullet = mark ?? style.template.bullet;
  return [
    for (var i = 0; i < items.length; i++)
      FitTextItem(
        text: items[i],
        style: style.body(size: size, color: color),
        gapBefore: i == 0 ? 0 : style.gap * gapFactor,
        leadingWidth: BulletMarkView.widthFor(bullet, size),
        leading: (scale) => BulletMarkView(
          style: style,
          mark: bullet,
          fontSize: size * scale,
          index: i,
          color: markColor,
        ),
      ),
  ];
}

/// Un panel con el aspecto de la plantilla: la caja de una columna, una
/// tarjeta, un paso.
class DeckPanel extends StatelessWidget {
  const DeckPanel({
    required this.style,
    required this.child,
    this.index = 0,
    this.padding,
    this.fill,
    super.key,
  });

  final DeckStyle style;
  final Widget child;

  /// La posición entre sus hermanos: inclina un poco el papel recortado.
  final int index;
  final EdgeInsets? padding;

  /// Un relleno propio en vez de la superficie (una tarjeta de color).
  final Color? fill;

  /// El papel de una nota adhesiva: la superficie teñida del acento, lo justo
  /// para que se vea de color sin que el texto deje de leerse a 7:1.
  static Color noteColor(CreationPalette palette) {
    final base = palette.surfaceOnBackground;
    for (var tint = 0.3; tint > 0; tint -= 0.02) {
      final paper = Color.lerp(base, palette.accent, tint)!;
      if (CreationContrast.ratio(palette.text, paper) >= 7 &&
          CreationContrast.ratio(palette.muted, paper) >= 4.5) {
        return paper;
      }
    }
    return base;
  }

  /// El relleno de adentro de un panel, sin sus bordes.
  static EdgeInsets innerPadding(DeckStyle style) =>
      EdgeInsets.all(style.gap * 0.85);

  /// Lo que el panel le quita a su contenido —relleno y bordes—: con
  /// esto, una grilla sabe de antemano el lugar exacto que tiene el texto
  /// de cada tarjeta, y puede darles a todas la misma letra.
  static EdgeInsets insets(DeckStyle style, {EdgeInsets? padding}) {
    final inner = padding ?? innerPadding(style);
    return switch (style.template.panel) {
      PanelLook.hairline => EdgeInsets.only(top: style.gap * 0.6 + 3),
      PanelLook.outline => inner + const EdgeInsets.all(2),
      PanelLook.glass => inner + const EdgeInsets.all(2),
      PanelLook.neon => inner + const EdgeInsets.all(3),
      PanelLook.framed => inner + const EdgeInsets.all(11),
      PanelLook.block => inner + const EdgeInsets.all(5),
      PanelLook.note => inner + EdgeInsets.only(top: style.gap * 0.35),
      PanelLook.filled ||
      PanelLook.tile ||
      PanelLook.paper ||
      PanelLook.chalk => inner,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = style.palette;
    final radius = BorderRadius.circular(style.template.radius);
    final inner = padding ?? innerPadding(style);
    switch (style.template.panel) {
      case PanelLook.hairline:
        return Container(
          padding: EdgeInsets.only(top: style.gap * 0.6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.text, width: 3)),
          ),
          child: child,
        );
      case PanelLook.outline:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color: palette.muted.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
          child: child,
        );
      case PanelLook.filled:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? palette.surface,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: palette.text.withValues(alpha: 0.06),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      case PanelLook.tile:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? palette.surface,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: palette.isDark ? 0.3 : 0.06,
                ),
                blurRadius: 40,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        );
      case PanelLook.glass:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: fill ?? palette.surface,
            gradient: fill == null
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.08),
                        palette.surface,
                      ),
                      palette.surface,
                    ],
                  )
                : null,
            border: Border.all(
              color: Colors.white.withValues(
                alpha: palette.isDark ? 0.28 : 0.7,
              ),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: palette.isDark ? 0.25 : 0.06,
                ),
                blurRadius: 50,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        );
      case PanelLook.paper:
        return Transform.rotate(
          angle: (index.isEven ? -1 : 1) * 0.012,
          child: Container(
            padding: inner,
            decoration: BoxDecoration(
              color: fill ?? palette.surface,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: palette.text.withValues(alpha: 0.22),
                  offset: const Offset(10, 12),
                ),
              ],
            ),
            child: child,
          ),
        );
      case PanelLook.chalk:
        return CustomPaint(
          painter: _ChalkBoxPainter(
            color: palette.text.withValues(alpha: 0.75),
            seed: index,
          ),
          child: Padding(padding: inner, child: child),
        );
      case PanelLook.neon:
        final tint = index.isEven ? palette.primary : palette.secondary;
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? palette.surface,
            borderRadius: radius,
            border: Border.all(color: tint, width: 3),
            boxShadow: [
              BoxShadow(color: tint.withValues(alpha: 0.45), blurRadius: 30),
            ],
          ),
          child: child,
        );
      case PanelLook.block:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? palette.surface,
            border: Border.all(color: palette.text, width: 5),
            boxShadow: [
              BoxShadow(color: palette.text, offset: const Offset(12, 12)),
            ],
          ),
          child: child,
        );
      case PanelLook.note:
        return Transform.rotate(
          angle: (index.isEven ? -1 : 1) * 0.01,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: inner + EdgeInsets.only(top: style.gap * 0.35),
                decoration: BoxDecoration(
                  color: fill ?? noteColor(style.palette),
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: palette.isDark ? 0.3 : 0.1,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: child,
              ),
              // La cinta que la sostiene, arriba al medio.
              Positioned(
                top: -style.gap * 0.3,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.rotate(
                    angle: (index.isEven ? 1 : -1) * 0.04,
                    child: Container(
                      width: 120,
                      height: style.gap * 0.7,
                      color: palette.text.withValues(alpha: 0.09),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case PanelLook.framed:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: fill ?? palette.surface,
            border: Border.all(
              color: palette.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Container(
            padding: inner,
            decoration: BoxDecoration(
              border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
            ),
            child: child,
          ),
        );
    }
  }
}

class _ChalkBoxPainter extends CustomPainter {
  const _ChalkBoxPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = color;
    final r = Offset.zero & size;
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    for (var i = 0; i < 4; i++) {
      CreationTextures.handLine(
        canvas,
        corners[i],
        corners[(i + 1) % 4],
        paint,
        seed: seed * 4 + i,
        jitter: 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ChalkBoxPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// La ilustración de la diapositiva: la de verdad si está, o la de reserva
/// con los colores de la plantilla.
class SlideArt extends StatelessWidget {
  const SlideArt({required this.context, this.icon, this.radius, super.key});

  final SlideContext context;
  final IconData? icon;
  final double? radius;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final corner = radius ?? style.template.radius;
    final placeholder = CreationArt(
      style: style.template.art,
      palette: style.palette,
      seed: context.seed,
      icon: icon,
      radius: corner,
    );
    final reference = context.slide.illustrationRef;
    final image = reference == null
        ? null
        : context.illustrations?.call(reference);
    if (image == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: Image(
        image: image,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// El ornamento de las plantillas clásicas: un filete, un rombo y otro filete.
class OrnamentDivider extends StatelessWidget {
  const OrnamentDivider({required this.style, this.width = 360, super.key});

  final DeckStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = style.palette.primary;
    return SizedBox(
      width: width,
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Container(height: 2, color: color.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 18),
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 16, height: 16, color: color),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Container(height: 2, color: color.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// Un círculo con un número o una letra adentro: los pasos, las secciones.
class NumberBadge extends StatelessWidget {
  const NumberBadge({
    required this.style,
    required this.label,
    required this.size,
    this.color,
    super.key,
  });

  final DeckStyle style;
  final String label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? style.palette.primary;
    final glow = style.template.panel == PanelLook.neon;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glow ? style.palette.background : fill,
        border: glow ? Border.all(color: fill, width: 4) : null,
        boxShadow: glow
            ? [BoxShadow(color: fill.withValues(alpha: 0.6), blurRadius: 24)]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: FittedBox(
          child: Text(
            label,
            maxLines: 1,
            style: style.figure(
              size: size * 0.42,
              color: glow
                  ? style.palette.text
                  : CreationContrast.readableOn(fill),
            ),
          ),
        ),
      ),
    );
  }
}
