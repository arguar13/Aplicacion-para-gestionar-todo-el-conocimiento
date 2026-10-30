import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/creation_textures.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';

/// El fondo de una lámina (F43): liso, con la textura del estilo o con un
/// degradé suave de la paleta, todo dibujado.
///
/// Las texturas van tenues y sobre todo en los bordes, donde no hay texto:
/// el fondo acompaña, no compite. [seed] cambia un poco lo que se dibuja «al
/// azar» (siempre lo mismo para la misma lámina).
class InfographicBackgroundPainter extends CustomPainter {
  const InfographicBackgroundPainter({required this.style, this.seed = 0});

  final InfographicStyle style;
  final int seed;

  CreationPalette get p => style.palette;

  static Color _a(Color color, double alpha) =>
      color.withValues(alpha: color.a * alpha);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = p.background);
    switch (style.background) {
      case InfographicBackground.plain:
        break;
      case InfographicBackground.gradient:
        _gradient(canvas, size);
      case InfographicBackground.texture:
        _texture(canvas, size);
    }
  }

  void _gradient(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strength = p.isDark ? 0.22 : 0.12;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          p.background,
          Color.lerp(p.background, p.primary, strength)!,
        ]),
    );
    CreationTextures.glow(
      canvas,
      Offset(size.width * 0.92, size.height * 0.06),
      size.shortestSide * 0.7,
      _a(p.secondary, p.isDark ? 0.22 : 0.16),
    );
    CreationTextures.glow(
      canvas,
      Offset(size.width * 0.04, size.height * 0.96),
      size.shortestSide * 0.6,
      _a(p.accent, p.isDark ? 0.18 : 0.14),
    );
  }

  void _texture(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final s = size.shortestSide;
    switch (style.spec.texture) {
      case InfoTexture.grain:
        CreationTextures.grain(
          canvas,
          size,
          color: _a(p.text, 0.05),
          seed: 11 + seed,
        );
      case InfoTexture.dots:
        CreationTextures.dotGrid(
          canvas,
          rect,
          color: _a(p.text, p.isDark ? 0.1 : 0.07),
          spacing: 44,
          radius: 2.2,
        );
      case InfoTexture.grid:
        CreationTextures.lineGrid(
          canvas,
          rect,
          color: _a(p.primary, 0.05),
          majorColor: _a(p.primary, 0.1),
          spacing: 32,
        );
      case InfoTexture.chalk:
        CreationTextures.chalkDust(canvas, size, color: p.text, seed: seed);
      case InfoTexture.neon:
        CreationTextures.starfield(
          canvas,
          size,
          color: _a(p.text, 0.5),
          seed: 3 + seed,
          count: 180,
        );
        CreationTextures.perspectiveGrid(
          canvas,
          Rect.fromLTWH(0, size.height * 0.8, size.width, size.height * 0.2),
          color: _a(p.primary, 0.22),
        );
        CreationTextures.glow(
          canvas,
          Offset(size.width * 0.5, size.height * 0.8),
          s * 0.6,
          _a(p.secondary, 0.16),
        );
      case InfoTexture.parchment:
        CreationTextures.grain(
          canvas,
          size,
          color: _a(p.text, 0.07),
          seed: 21 + seed,
          density: 0.0024,
        );
        CreationTextures.watercolor(
          canvas,
          Offset(size.width * 0.9, size.height * 0.92),
          s * 0.3,
          _a(p.secondary, 0.2),
          seed: 4 + seed,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.radial(
              rect.center,
              size.longestSide * 0.62,
              [_a(p.text, 0), _a(p.text, 0.14)],
              const [0.62, 1],
            ),
        );
        final frame = Paint()
          ..style = PaintingStyle.stroke
          ..color = _a(p.primary, 0.55)
          ..strokeWidth = 3;
        canvas
          ..drawRect(rect.deflate(26), frame)
          ..drawRect(rect.deflate(36), frame..strokeWidth = 1.2);
      case InfoTexture.shapes:
        // Formas grandes de color que asoman de los bordes, como un afiche
        // de la Bauhaus. Tenues: el título y la fuente pasan por encima y
        // se tienen que seguir leyendo.
        canvas
          ..drawCircle(
            Offset(size.width * 1.02, size.height * -0.02),
            s * 0.3,
            Paint()..color = _a(p.primary, 0.2),
          )
          ..drawArc(
            Rect.fromCircle(
              center: Offset(size.width * -0.02, size.height * 1.02),
              radius: s * 0.26,
            ),
            -math.pi / 2,
            math.pi / 2,
            true,
            Paint()..color = _a(p.secondary, 0.18),
          )
          ..drawRect(
            Rect.fromLTWH(
              size.width - s * 0.09,
              size.height - s * 0.09,
              s * 0.09,
              s * 0.09,
            ),
            Paint()..color = _a(p.accent, 0.55),
          );
      case InfoTexture.confetti:
        final random = math.Random(31 + seed);
        for (var i = 0; i < 70; i++) {
          final center = Offset(
            random.nextDouble() * size.width,
            random.nextDouble() * size.height,
          );
          final paint = Paint()..color = _a(style.tint(i), 0.32);
          final side = 8 + random.nextDouble() * 14;
          if (i.isEven) {
            canvas.drawCircle(center, side / 2, paint);
          } else {
            canvas
              ..save()
              ..translate(center.dx, center.dy)
              ..rotate(random.nextDouble() * math.pi)
              ..drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(
                    center: Offset.zero,
                    width: side * 1.6,
                    height: side * 0.6,
                  ),
                  Radius.circular(side * 0.3),
                ),
                paint,
              )
              ..restore();
          }
        }
      case InfoTexture.halftone:
        final dot = Paint()..color = _a(p.text, 0.08);
        const step = 26.0;
        for (var y = step / 2; y < size.height; y += step) {
          for (var x = step / 2; x < size.width; x += step) {
            // Más grandes hacia la esquina de arriba a la derecha.
            final t = (x / size.width + (1 - y / size.height)) / 2;
            final radius = step * 0.36 * t * t;
            if (radius > 0.6) canvas.drawCircle(Offset(x, y), radius, dot);
          }
        }
      case InfoTexture.watercolor:
        for (final (i, corner) in [
          Offset(size.width * 0.96, size.height * 0.04),
          Offset(size.width * 0.04, size.height * 0.97),
          Offset(size.width * 0.98, size.height * 0.7),
        ].indexed) {
          CreationTextures.watercolor(
            canvas,
            corner,
            s * (0.26 - i * 0.05),
            _a(style.tint(i), 0.55),
            seed: seed + i * 3,
          );
        }
      case InfoTexture.isometric:
        final line = Paint()
          ..color = _a(p.text, 0.06)
          ..strokeWidth = 1.4;
        const spacing = 56.0;
        final slope = math.tan(math.pi / 6);
        for (var x = -size.height; x < size.width + size.height; x += spacing) {
          canvas
            ..drawLine(
              Offset(x, 0),
              Offset(x + size.height / slope, size.height),
              line,
            )
            ..drawLine(
              Offset(x, 0),
              Offset(x - size.height / slope, size.height),
              line,
            );
        }
      case InfoTexture.bokeh:
        final random = math.Random(17 + seed);
        for (var i = 0; i < 14; i++) {
          CreationTextures.glow(
            canvas,
            Offset(
              random.nextDouble() * size.width,
              random.nextDouble() * size.height,
            ),
            s * (0.05 + random.nextDouble() * 0.12),
            _a(style.tint(i), p.isDark ? 0.18 : 0.12),
          );
        }
      case InfoTexture.bubbles:
        final random = math.Random(41 + seed);
        for (var i = 0; i < 9; i++) {
          final center = Offset(
            (i.isEven ? 0.0 : 1.0) * size.width +
                (random.nextDouble() - 0.5) * size.width * 0.3,
            random.nextDouble() * size.height,
          );
          final radius = s * (0.08 + random.nextDouble() * 0.12);
          canvas
            ..drawCircle(
              center,
              radius,
              Paint()..color = _a(style.tint(i), 0.12),
            )
            ..drawCircle(
              center + Offset(-radius * 0.35, -radius * 0.35),
              radius * 0.22,
              Paint()..color = const Color(0x1FFFFFFF),
            );
        }
      // Las de F45: tenues y en los bordes, como las de F43; el texto de
      // los bloques pasa por encima y se tiene que seguir leyendo.
      case InfoTexture.newsprint:
        CreationTextures.grain(
          canvas,
          size,
          color: _a(p.text, 0.07),
          seed: 101 + seed,
          density: 0.0022,
        );
        final dot = Paint()..color = _a(p.text, 0.08);
        const step = 22.0;
        final from = Offset(size.width * 0.7, size.height * 0.84);
        for (var y = from.dy; y < size.height; y += step) {
          for (var x = from.dx; x < size.width; x += step) {
            final t =
                ((x - from.dx) / (size.width - from.dx) +
                    (y - from.dy) / (size.height - from.dy)) /
                2;
            final radius = step * 0.42 * t;
            if (radius > 0.8) canvas.drawCircle(Offset(x, y), radius, dot);
          }
        }
      case InfoTexture.inkWash:
        CreationTextures.grain(
          canvas,
          size,
          color: _a(p.text, 0.045),
          seed: 111 + seed,
        );
        CreationTextures.watercolor(
          canvas,
          Offset(size.width * 0.02, size.height * 0.99),
          s * 0.34,
          _a(p.text, 0.42),
          seed: 3 + seed,
        );
        CreationTextures.watercolor(
          canvas,
          Offset(size.width * 1.01, size.height * 0.01),
          s * 0.2,
          _a(p.accent, 0.55),
          seed: 9 + seed,
        );
        final seal = Rect.fromLTWH(
          size.width - style.marginX * 0.78,
          style.marginY * 0.35,
          38,
          38,
        );
        canvas
          ..drawRect(seal, Paint()..color = p.secondary)
          ..drawRect(
            seal.deflate(6),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = _a(p.onSecondary, 0.85),
          );
      case InfoTexture.colorBlock:
        // Una franja de color a sangre en el borde de arriba y una pestaña
        // del acento, como la cabecera de una sección de revista.
        canvas
          ..drawRect(
            Rect.fromLTWH(0, 0, size.width, style.marginY * 0.42),
            Paint()..color = p.primary,
          )
          ..drawRect(
            Rect.fromLTWH(style.marginX, style.marginY * 0.42, 160, 12),
            Paint()..color = p.accent,
          );
      case InfoTexture.bauhaus:
        canvas
          ..drawCircle(
            Offset(size.width * 1.02, size.height * -0.01),
            s * 0.22,
            Paint()..color = _a(p.primary, 0.28),
          )
          ..drawArc(
            Rect.fromCircle(
              center: Offset(size.width * 0.06, size.height * 1.01),
              radius: s * 0.2,
            ),
            math.pi,
            math.pi,
            true,
            Paint()..color = _a(p.secondary, 0.26),
          )
          ..drawPath(
            Path()
              ..moveTo(size.width - s * 0.2, size.height)
              ..lineTo(size.width - s * 0.1, size.height - s * 0.16)
              ..lineTo(size.width, size.height)
              ..close(),
            Paint()..color = _a(p.accent, 0.5),
          );
      case InfoTexture.brutal:
        canvas
          ..drawRect(
            rect.deflate(16),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10
              ..color = p.text,
          )
          ..drawRect(
            Rect.fromLTWH(size.width - 86, 21, 65, 65),
            Paint()..color = p.accent,
          );
      case InfoTexture.spotlight:
        CreationTextures.glow(
          canvas,
          Offset(size.width * 0.3, -size.height * 0.08),
          s * 0.9,
          _a(p.primary, 0.08),
        );
      case InfoTexture.scanlines:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.radial(rect.center, size.longestSide * 0.6, [
              _a(p.primary, 0.06),
              _a(p.primary, 0),
            ]),
        );
        final scan = Paint()..color = _a(p.text, 0.03);
        for (var y = 0.0; y < size.height; y += 5) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), scan);
        }
      case InfoTexture.deco:
        final gold = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = _a(p.primary, 0.75);
        const inset = 24.0;
        const step = 18.0;
        for (final (x, y, dx, dy) in [
          (inset, inset, 1.0, 1.0),
          (size.width - inset, inset, -1.0, 1.0),
          (inset, size.height - inset, 1.0, -1.0),
          (size.width - inset, size.height - inset, -1.0, -1.0),
        ]) {
          canvas.drawPath(
            Path()
              ..moveTo(x + dx * 120, y)
              ..lineTo(x + dx * step * 2, y)
              ..lineTo(x + dx * step * 2, y + dy * step)
              ..lineTo(x + dx * step, y + dy * step)
              ..lineTo(x + dx * step, y + dy * step * 2)
              ..lineTo(x, y + dy * step * 2)
              ..lineTo(x, y + dy * 120),
            gold,
          );
        }
        // El abanico, tenue, abajo al centro.
        final center = Offset(size.width / 2, size.height + 20);
        for (var i = 0; i < 13; i++) {
          final angle = math.pi + math.pi * (i + 0.5) / 13;
          canvas.drawLine(
            center,
            center + Offset(math.cos(angle), math.sin(angle)) * s * 0.22,
            Paint()
              ..strokeWidth = 2
              ..color = _a(p.primary, i.isEven ? 0.22 : 0.1),
          );
        }
      case InfoTexture.sunset:
        final colors = [p.primary, p.accent, p.secondary, p.primary];
        final corner = Offset(size.width, size.height);
        for (var i = 0; i < colors.length; i++) {
          canvas.drawCircle(
            corner,
            s * (0.3 - i * 0.06),
            Paint()..color = _a(colors[i], 0.28),
          );
        }
        CreationTextures.grain(
          canvas,
          size,
          color: _a(p.text, 0.035),
          seed: 121 + seed,
        );
      case InfoTexture.ruled:
        final line = Paint()
          ..color = _a(p.primary, 0.14)
          ..strokeWidth = 2;
        for (var y = style.marginY * 1.6; y < size.height - 10; y += 56) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        final margin = style.marginX * 0.6;
        canvas.drawLine(
          Offset(margin, 0),
          Offset(margin, size.height),
          Paint()
            ..color = _a(p.secondary, 0.45)
            ..strokeWidth = 3,
        );
      case InfoTexture.marker:
        final random = math.Random(131 + seed);
        for (var i = 0; i < 5; i++) {
          CreationTextures.glow(
            canvas,
            Offset(
              random.nextDouble() * size.width,
              random.nextDouble() * size.height,
            ),
            s * (0.15 + random.nextDouble() * 0.15),
            _a(p.text, 0.035),
          );
        }
        canvas.drawRect(
          rect.deflate(7),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
              Color.lerp(p.background, p.text, 0.18)!,
              Color.lerp(p.background, p.text, 0.32)!,
            ]),
        );
      case InfoTexture.blueprint:
        CreationTextures.lineGrid(
          canvas,
          rect,
          color: _a(p.text, 0.07),
          majorColor: _a(p.text, 0.13),
        );
        final ink = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _a(p.text, 0.5);
        for (final corner in [
          const Offset(32, 32),
          Offset(size.width - 32, 32),
          Offset(32, size.height - 32),
          Offset(size.width - 32, size.height - 32),
        ]) {
          canvas
            ..drawLine(
              corner - const Offset(14, 0),
              corner + const Offset(14, 0),
              ink,
            )
            ..drawLine(
              corner - const Offset(0, 14),
              corner + const Offset(0, 14),
              ink,
            )
            ..drawCircle(corner, 7, ink);
        }
    }
  }

  @override
  bool shouldRepaint(InfographicBackgroundPainter oldDelegate) =>
      oldDelegate.style.palette != style.palette ||
      oldDelegate.style.background != style.background ||
      oldDelegate.style.spec.id != style.spec.id ||
      oldDelegate.seed != seed;
}
