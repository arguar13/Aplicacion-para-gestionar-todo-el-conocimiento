import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/creation_textures.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart'
    show InfographicIconLook;
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_background_painter.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';

/// La ilustración ya hecha de un bloque (o de la cabecera), por su
/// referencia (la ruta o la clave guardada en `illustrationRef`), o null si
/// no se encuentra: entonces se dibuja la de reserva.
typedef InfographicIllustrationResolver =
    ImageProvider? Function(String reference);

/// Lo que toda composición necesita saber además de sus bloques.
@immutable
class InfoContext {
  const InfoContext({
    required this.style,
    required this.sheet,
    this.illustrations,
  });

  final InfographicStyle style;
  final Infographic sheet;
  final InfographicIllustrationResolver? illustrations;

  /// Los bloques que se dibujan, ya elegidos (ver `InfographicAuto`).
  List<InfographicBlock> get blocks => style.arrangement.blocks;

  InfographicStyleSpec get spec => style.spec;

  /// Una semilla estable para lo que se dibuja «al azar» en esta lámina.
  int get seed => sheet.title.length * 7 + blocks.length;
}

/// El ícono de reserva de cada tipo de bloque, si la IA no eligió uno.
String defaultIconName(InfographicBlock block) => switch (block) {
  StatBlock() => 'insights',
  FactBlock() => 'lightbulb',
  StepBlock() => 'route',
  ComparisonBlock() => 'compare',
  EventBlock() => 'calendar',
  ConceptBlock() => 'category',
  QuoteBlock() => 'quote',
  ChartBlock() => 'bar_chart',
};

/// El ícono de [block]: el que eligió la IA, o el de su tipo.
IconData blockIcon(InfographicBlock block) =>
    CreationIcons.resolve(block.iconName ?? defaultIconName(block));

/// Una caja con el aspecto del estilo: la de un bloque.
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    required this.style,
    required this.child,
    this.index = 0,
    this.fill,
    super.key,
  });

  final InfographicStyle style;
  final Widget child;

  /// La posición entre sus hermanos: el color del borde en Infantil, el del
  /// relleno en Kawaii.
  final int index;

  /// Un relleno propio en vez de la superficie (el bloque destacado).
  final Color? fill;

  /// El relleno de adentro de una caja, sin sus bordes.
  static EdgeInsets innerPadding(InfographicStyle style) =>
      EdgeInsets.all(style.gap * 0.95);

  /// Lo que la caja le quita a su contenido —relleno y bordes—: con esto, una
  /// composición sabe de antemano el lugar exacto que tiene el texto de cada
  /// bloque y puede darles a todos la misma letra.
  static EdgeInsets insets(InfographicStyle style) {
    final inner = innerPadding(style);
    return switch (style.spec.panel) {
      InfoPanelLook.hairline => EdgeInsets.only(top: style.gap * 0.7 + 3),
      InfoPanelLook.outline => inner + const EdgeInsets.all(2),
      InfoPanelLook.neon => inner + const EdgeInsets.all(3),
      InfoPanelLook.framed => inner + const EdgeInsets.all(11),
      InfoPanelLook.playful => inner + const EdgeInsets.all(6),
      InfoPanelLook.sticker => inner + const EdgeInsets.fromLTRB(4, 4, 12, 12),
      InfoPanelLook.flat ||
      InfoPanelLook.tile ||
      InfoPanelLook.card ||
      InfoPanelLook.chalk ||
      InfoPanelLook.tinted => inner,
      InfoPanelLook.clay => inner + const EdgeInsets.only(top: 2),
      InfoPanelLook.block => inner + const EdgeInsets.fromLTRB(4, 4, 12, 12),
      InfoPanelLook.note => inner + EdgeInsets.only(top: style.gap * 0.3),
    };
  }

  /// El color sobre el que queda el texto de la caja [index] (para medir el
  /// contraste de lo que va encima).
  static Color surfaceOf(InfographicStyle style, int index, {Color? fill}) {
    if (fill != null) return fill;
    final p = style.palette;
    return switch (style.spec.panel) {
      InfoPanelLook.hairline ||
      InfoPanelLook.outline ||
      InfoPanelLook.chalk => p.background,
      InfoPanelLook.tinted => Color.alphaBlend(
        style.tint(index).withValues(alpha: 0.14),
        p.surfaceOnBackground,
      ),
      InfoPanelLook.note => p.noteColor,
      _ => p.surfaceOnBackground,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = style.palette;
    final radius = BorderRadius.circular(style.spec.radius);
    final inner = innerPadding(style);
    final tint = style.tint(index);
    switch (style.spec.panel) {
      case InfoPanelLook.hairline:
        return Container(
          padding: EdgeInsets.only(top: style.gap * 0.7),
          decoration: BoxDecoration(
            color: fill,
            border: Border(top: BorderSide(color: p.text, width: 3)),
          ),
          child: child,
        );
      case InfoPanelLook.flat:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            borderRadius: radius,
          ),
          child: child,
        );
      case InfoPanelLook.outline:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color: p.muted.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
          child: child,
        );
      case InfoPanelLook.tile:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.32 : 0.07),
                blurRadius: 40,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        );
      case InfoPanelLook.card:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: p.text.withValues(alpha: p.isDark ? 0.2 : 0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );
      case InfoPanelLook.chalk:
        return CustomPaint(
          painter: _HandBoxPainter(
            color: (fill == null ? p.text : CreationContrast.readableOn(fill!))
                .withValues(alpha: 0.75),
            seed: index,
          ),
          child: Container(padding: inner, color: fill, child: child),
        );
      case InfoPanelLook.neon:
        final glow = index.isEven ? p.primary : p.secondary;
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            borderRadius: radius,
            border: Border.all(color: glow, width: 3),
            boxShadow: [
              BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 28),
            ],
          ),
          child: child,
        );
      case InfoPanelLook.framed:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            border: Border.all(
              color: p.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Container(
            padding: inner,
            decoration: BoxDecoration(
              border: Border.all(color: p.primary.withValues(alpha: 0.3)),
            ),
            child: child,
          ),
        );
      case InfoPanelLook.playful:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            borderRadius: radius,
            border: Border.all(color: tint, width: 6),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.25),
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      case InfoPanelLook.sticker:
        return Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            borderRadius: radius,
            border: Border.all(color: _ink(p), width: 4),
            boxShadow: [BoxShadow(color: _ink(p), offset: const Offset(8, 8))],
          ),
          child: child,
        );
      case InfoPanelLook.clay:
        final base = fill ?? p.surface;
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: 0.35), base),
                base,
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.7),
                width: 2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: p.isDark ? 0.35 : 0.22),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        );
      case InfoPanelLook.tinted:
        return Container(
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? surfaceOf(style, index),
            borderRadius: radius,
          ),
          child: child,
        );
      case InfoPanelLook.block:
        // La sombra dura va adentro del lugar del bloque (el margen de abajo
        // a la derecha), así no pisa al vecino.
        return Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: inner,
          decoration: BoxDecoration(
            color: fill ?? p.surface,
            border: Border.all(color: p.text, width: 4),
            boxShadow: [BoxShadow(color: p.text, offset: const Offset(8, 8))],
          ),
          child: child,
        );
      case InfoPanelLook.note:
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill ?? p.noteColor,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: p.isDark ? 0.3 : 0.1,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
            // La cinta que la sostiene, arriba al medio.
            Positioned(
              top: -style.gap * 0.25,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.rotate(
                  angle: (index.isEven ? 1 : -1) * 0.04,
                  child: Container(
                    width: 96,
                    height: style.gap * 0.6,
                    color: p.text.withValues(alpha: 0.09),
                  ),
                ),
              ),
            ),
            Padding(
              padding: inner + EdgeInsets.only(top: style.gap * 0.3),
              child: child,
            ),
          ],
        );
    }
  }

  /// El negro de la historieta: el texto si es oscuro, si no el de siempre.
  static Color _ink(CreationPalette p) =>
      p.isDark ? const Color(0xFF000000) : p.text;
}

class _HandBoxPainter extends CustomPainter {
  const _HandBoxPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = color;
    final r = (Offset.zero & size).deflate(2);
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
  bool shouldRepaint(_HandBoxPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// El ícono de un bloque, con el aspecto elegido (ver
/// [InfographicIconLook]), sobre el color [surface].
class InfoIcon extends StatelessWidget {
  const InfoIcon({
    required this.style,
    required this.icon,
    required this.size,
    required this.tint,
    this.surface,
    super.key,
  });

  final InfographicStyle style;
  final IconData icon;
  final double size;
  final Color tint;

  /// Sobre qué color queda el ícono: el contraste se mide contra él.
  final Color? surface;

  /// El lado más chico, en puntos del lienzo, con que un ícono se dibuja:
  /// por debajo ya no se distingue (y la letra de los íconos, a ese tamaño,
  /// no entra en su propio cuadrado). Un bloque apretado queda sin ícono.
  static const double minimumSide = 24;

  @override
  Widget build(BuildContext context) {
    final p = style.palette;
    final under = surface ?? p.surfaceOnBackground;
    final neon = style.spec.panel == InfoPanelLook.neon;
    if (size < minimumSide) return SizedBox.square(dimension: size);
    switch (style.iconLook) {
      case InfographicIconLook.none:
        return SizedBox.square(dimension: size);
      case InfographicIconLook.bare:
        return SizedBox.square(
          dimension: size,
          child: Icon(
            icon,
            size: size * 0.86,
            color: CreationContrast.ensure(tint, under, minimum: 3),
          ),
        );
      case InfographicIconLook.soft:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(tint.withValues(alpha: 0.18), under),
          ),
          child: Icon(
            icon,
            size: size * 0.52,
            color: CreationContrast.ensure(
              tint,
              Color.alphaBlend(tint.withValues(alpha: 0.18), under),
              minimum: 3,
            ),
          ),
        );
      case InfographicIconLook.solid:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tint,
            boxShadow: style.spec.panel == InfoPanelLook.clay
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.4),
                      blurRadius: size * 0.2,
                      offset: Offset(0, size * 0.08),
                    ),
                  ]
                : null,
            border: style.spec.panel == InfoPanelLook.sticker
                ? Border.all(color: InfoPanel._ink(p), width: 3)
                : null,
          ),
          child: Icon(
            icon,
            size: size * 0.52,
            color: CreationContrast.readableOn(tint),
          ),
        );
      case InfographicIconLook.outline:
        final line = CreationContrast.ensure(tint, under, minimum: 3);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: line, width: math.max(2, size * 0.045)),
            boxShadow: neon
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.5),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Icon(icon, size: size * 0.5, color: line),
        );
    }
  }
}

/// Un círculo con un número adentro: los pasos y los niveles.
class InfoNumberBadge extends StatelessWidget {
  const InfoNumberBadge({
    required this.style,
    required this.label,
    required this.size,
    this.color,
    super.key,
  });

  final InfographicStyle style;
  final String label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? style.palette.primary;
    final neon = style.spec.panel == InfoPanelLook.neon;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: neon ? style.palette.background : fill,
        border: neon
            ? Border.all(color: fill, width: 4)
            : style.spec.panel == InfoPanelLook.sticker
            ? Border.all(color: InfoPanel._ink(style.palette), width: 3)
            : null,
        boxShadow: neon
            ? [BoxShadow(color: fill.withValues(alpha: 0.6), blurRadius: 22)]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: FittedBox(
          child: Text(
            label,
            maxLines: 1,
            style: style.figure(
              size: size * 0.44,
              color: neon
                  ? style.palette.text
                  : CreationContrast.readableOn(fill),
            ),
          ),
        ),
      ),
    );
  }
}

/// La ilustración de un bloque o de la cabecera: la de verdad si está, o la
/// de reserva con el trazo y los colores del estilo —«el lugar dibujado»:
/// la lámina se ve terminada igual, y una ilustración que llegue después
/// ocupa justo este lugar—.
class InfoArt extends StatelessWidget {
  const InfoArt({
    required this.context,
    required this.reference,
    required this.seed,
    this.icon,
    this.radius,
    super.key,
  });

  final InfoContext context;
  final String? reference;
  final int seed;
  final IconData? icon;
  final double? radius;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final corner = radius ?? style.spec.radius;
    final placeholder = CreationArt(
      style: style.spec.art,
      palette: style.palette,
      seed: seed,
      icon: icon,
      radius: corner,
    );
    final image = reference == null
        ? null
        : context.illustrations?.call(reference!);
    final art = image == null
        ? placeholder
        : ClipRRect(
            borderRadius: BorderRadius.circular(corner),
            child: Image(
              image: image,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => placeholder,
            ),
          );
    if (style.spec.panel != InfoPanelLook.sticker) return art;
    // En la historieta, la viñeta lleva su borde negro.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(corner),
        border: Border.all(color: InfoPanel._ink(style.palette), width: 4),
      ),
      child: art,
    );
  }
}

/// Las líneas que unen cosas —la cronología, el proceso, los rayos, el
/// mapa—, cada una un camino, con el trazo del estilo y, si se pide, una
/// punta de flecha al final.
class InfoLinesPainter extends CustomPainter {
  const InfoLinesPainter({
    required this.paths,
    required this.color,
    required this.look,
    this.width = 4,
    this.arrows = false,
    this.seed = 0,
  });

  final List<List<Offset>> paths;
  final Color color;
  final InfoConnectorLook look;
  final double width;
  final bool arrows;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..color = color;
    for (final (index, points) in paths.indexed) {
      if (points.length < 2) continue;
      if (look == InfoConnectorLook.glow) {
        canvas.drawPath(
          _smooth(points),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * 3
            ..color = color.withValues(alpha: 0.3)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2),
        );
      }
      switch (look) {
        case InfoConnectorLook.solid || InfoConnectorLook.glow:
          canvas.drawPath(_smooth(points), paint);
        case InfoConnectorLook.dashed:
          _dashed(canvas, _smooth(points), paint);
        case InfoConnectorLook.hand:
          for (var i = 0; i < points.length - 1; i++) {
            CreationTextures.handLine(
              canvas,
              points[i],
              points[i + 1],
              paint,
              seed: seed + index * 7 + i,
              jitter: width * 0.6,
            );
          }
      }
      if (arrows) {
        _arrowHead(canvas, points[points.length - 2], points.last, paint);
      }
    }
  }

  /// Un camino por los puntos; con tres o más, las esquinas redondeadas con
  /// curvas para que no se vea quebrado.
  static Path _smooth(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      return path..lineTo(points.last.dx, points.last.dy);
    }
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    return path..lineTo(points.last.dx, points.last.dy);
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    final dash = width * 3.5;
    final space = width * 2.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + space;
      }
    }
  }

  void _arrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final delta = to - from;
    if (delta.distance == 0) return;
    final direction = delta / delta.distance;
    final length = width * 4;
    for (final turn in [2.6, -2.6]) {
      final head = Offset(
        direction.dx * math.cos(turn) - direction.dy * math.sin(turn),
        direction.dx * math.sin(turn) + direction.dy * math.cos(turn),
      );
      canvas.drawLine(to, to + head * length, paint);
    }
  }

  @override
  bool shouldRepaint(InfoLinesPainter oldDelegate) =>
      oldDelegate.paths != paths ||
      oldDelegate.color != color ||
      oldDelegate.look != look ||
      oldDelegate.width != width ||
      oldDelegate.arrows != arrows;
}

/// El cuadro de toda lámina: el fondo del estilo, los márgenes, la cabecera
/// arriba, la idea para llevarse y la fuente abajo, y el resto para [body].
class InfoFrame extends StatelessWidget {
  const InfoFrame({required this.context, required this.body, super.key});

  final InfoContext context;
  final Widget body;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final banner = style.spec.header == InfoHeaderLook.banner;
    final footer = _Footer(context: context);
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: InfographicBackgroundPainter(
                style: style,
                seed: context.seed,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner)
                _Header(context: context)
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    style.marginX,
                    style.marginY,
                    style.marginX,
                    0,
                  ),
                  child: _Header(context: context),
                ),
              SizedBox(height: style.gap * 1.4),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: style.marginX),
                  child: body,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  style.marginX,
                  style.gap * 1.2,
                  style.marginX,
                  style.marginY,
                ),
                child: footer,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La cabecera: el antetítulo, el título y la bajada, con el aspecto del
/// estilo. Ocupa a lo sumo una parte del alto; un título largo achica su
/// letra.
class _Header extends StatelessWidget {
  const _Header({required this.context});

  final InfoContext context;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final sheet = context.sheet;
    final p = style.palette;
    final look = style.spec.header;
    final maxHeight = style.canvas.height * (style.isPortrait ? 0.19 : 0.25);
    final centered = look == InfoHeaderLook.centered;
    final onBanner = look == InfoHeaderLook.banner;
    final ink = onBanner ? p.onPrimary : p.text;
    final align = centered ? TextAlign.center : TextAlign.start;
    final titleSize = look == InfoHeaderLook.poster
        ? style.titleSize * 1.14
        : style.titleSize;
    final items = [
      if (sheet.kicker.isNotEmpty)
        FitTextItem(
          text: sheet.kicker.toUpperCase(),
          style: style.kicker(color: onBanner ? p.onPrimary : null),
          textAlign: align,
          maxLines: 1,
        ),
      FitTextItem(
        text: style.titleCase(sheet.title),
        style: _titleStyle(style, titleSize, ink),
        textAlign: align,
        maxLines: 3,
        gapBefore: sheet.kicker.isEmpty ? 0 : style.gap * 0.5,
      ),
      if (sheet.subtitle.isNotEmpty)
        FitTextItem(
          text: sheet.subtitle,
          style: style.subtitle(color: onBanner ? p.onPrimary : null),
          textAlign: align,
          maxLines: 3,
          gapBefore: style.gap * 0.55,
        ),
    ];
    final ornament = switch (look) {
      // El filete doble de abajo de la cabecera de un diario.
      InfoHeaderLook.masthead => Container(
        margin: EdgeInsets.only(top: style.gap * 0.7),
        height: 9,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: p.text, width: 4),
            bottom: BorderSide(color: p.text, width: 1.5),
          ),
        ),
      ),
      InfoHeaderLook.editorial => Container(
        margin: EdgeInsets.only(top: style.gap * 0.8),
        height: 3,
        color: p.text.withValues(alpha: 0.85),
      ),
      InfoHeaderLook.centered => Padding(
        padding: EdgeInsets.only(top: style.gap * 0.7),
        child: Center(child: _Ornament(color: p.primary)),
      ),
      InfoHeaderLook.poster => Container(
        margin: EdgeInsets.only(top: style.gap * 0.8),
        width: 160,
        height: 14,
        alignment: Alignment.centerLeft,
        color: p.primary,
      ),
      InfoHeaderLook.banner || InfoHeaderLook.hero => null,
    };
    // Lo que queda para el texto, sin el adorno de abajo.
    final textHeight =
        maxHeight -
        (ornament == null ? 0 : style.gap * 0.8 + 28) -
        (look == InfoHeaderLook.masthead ? 6 + style.gap * 0.45 : 0);
    Widget text = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: textHeight),
      child: FitTextGroup(
        items: items,
        minScale: 0.4,
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
      ),
    );
    if (look == InfoHeaderLook.poster) {
      text = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: text)],
      );
    }
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      children: [
        // Y el grueso de arriba, sobre el rótulo.
        if (look == InfoHeaderLook.masthead) ...[
          Container(height: 6, color: p.text),
          SizedBox(height: style.gap * 0.45),
        ],
        text,
        ?ornament,
      ],
    );
    switch (look) {
      case InfoHeaderLook.banner:
        return Container(
          color: p.primary,
          padding: EdgeInsets.fromLTRB(
            style.marginX,
            style.marginY,
            style.marginX,
            style.gap * 1.4,
          ),
          child: column,
        );
      case InfoHeaderLook.hero:
        final artWidth = math.min(maxHeight * 1.45, style.canvas.width * 0.36);
        return SizedBox(
          height: maxHeight,
          child: Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: column),
              ),
              SizedBox(width: style.gap * 1.2),
              SizedBox(
                width: artWidth,
                height: maxHeight,
                child: InfoArt(
                  context: context,
                  reference: sheet.illustrationRef,
                  seed: context.seed,
                  radius: style.spec.radius * 1.2,
                ),
              ),
            ],
          ),
        );
      case InfoHeaderLook.editorial ||
          InfoHeaderLook.poster ||
          InfoHeaderLook.centered ||
          InfoHeaderLook.masthead:
        return column;
    }
  }

  static TextStyle _titleStyle(InfographicStyle style, double size, Color ink) {
    final base = style.title(size: size, color: ink);
    if (style.spec.panel != InfoPanelLook.neon) return base;
    return base.copyWith(
      shadows: [
        Shadow(color: style.palette.primary, blurRadius: 26),
        Shadow(
          color: style.palette.primary.withValues(alpha: 0.6),
          blurRadius: 56,
        ),
      ],
    );
  }
}

/// Un filete, un rombo y otro filete.
class _Ornament extends StatelessWidget {
  const _Ornament({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Container(height: 2, color: color.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 16),
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 14, height: 14, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(height: 2, color: color.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// El pie: la idea para llevarse en una franja, y de dónde sale en letra
/// chica. Sin palabras propias —solo el contenido y un ícono—, así la lámina
/// se dibuja igual en cualquier idioma y fuera de pantalla.
class _Footer extends StatelessWidget {
  const _Footer({required this.context});

  final InfoContext context;

  @override
  Widget build(BuildContext buildContext) {
    final style = context.style;
    final sheet = context.sheet;
    final p = style.palette;
    if (sheet.takeaway.isEmpty && sheet.source.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxHeight = style.canvas.height * 0.12;
    final children = <Widget>[];
    if (sheet.takeaway.isNotEmpty) {
      final fill = p.primary;
      final ink = CreationContrast.readableOn(fill);
      children.add(
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: style.gap * 1.1,
            vertical: style.gap * 0.7,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(
              math.min(style.spec.radius, 40),
            ),
            border: style.spec.panel == InfoPanelLook.sticker
                ? Border.all(color: InfoPanel._ink(p), width: 4)
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 44, color: ink),
              SizedBox(width: style.gap * 0.8),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight * 0.62),
                  child: FitText(
                    sheet.takeaway,
                    style: style.heading(size: 32, color: ink),
                    maxLines: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (sheet.source.isNotEmpty) {
      children.add(
        Padding(
          padding: EdgeInsets.only(
            top: sheet.takeaway.isEmpty ? 0 : style.gap * 0.6,
          ),
          child: Row(
            mainAxisAlignment: style.spec.centered
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(Icons.menu_book_outlined, size: 24, color: p.muted),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  sheet.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.small(size: 22, color: p.muted),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Cómo se alinean los textos de los bloques en el estilo.
TextAlign blockAlign(InfographicStyle style) =>
    style.spec.centered ? TextAlign.center : TextAlign.start;
