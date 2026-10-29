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
    }
  }

  @override
  bool shouldRepaint(InfographicBackgroundPainter oldDelegate) =>
      oldDelegate.style.palette != style.palette ||
      oldDelegate.style.background != style.background ||
      oldDelegate.style.spec.id != style.spec.id ||
      oldDelegate.seed != seed;
}
