import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/creation_textures.dart';

/// Con qué trazo se dibuja la ilustración de reserva de cada estilo.
enum CreationArtStyle {
  /// Círculos, medios círculos y cuadrados, como un afiche suizo.
  geometric,

  /// Manchas suaves que se superponen, como la acuarela.
  organic,

  /// Arcos y líneas finas, a pluma.
  linework,

  /// Círculos y flechas a tiza.
  chalk,

  /// Anillos y líneas que brillan.
  neon,

  /// Recortes de papel en capas, con su sombra.
  paper,

  /// Barras y una curva, como un tablero.
  data,
}

/// La ilustración que se dibuja cuando no hay una de verdad (F43): mientras
/// no se generó, si la IA elegida no hace imágenes, o si se apagaron. Una
/// composición abstracta con los colores de la paleta, distinta para cada
/// [seed] —la diapositiva, el bloque—, y un ícono en el medio si lo hay.
///
/// Es «el lugar dibujado» del plan: la creación se ve terminada igual, y una
/// ilustración que llegue después ocupa justo este lugar.
class CreationArt extends StatelessWidget {
  const CreationArt({
    required this.style,
    required this.palette,
    this.seed = 0,
    this.icon,
    this.radius = 0,
    super.key,
  });

  final CreationArtStyle style;
  final CreationPalette palette;
  final int seed;
  final IconData? icon;

  /// El redondeo del recorte, en puntos del lienzo.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: CreationArtPainter(style: style, palette: palette, seed: seed),
        child: icon == null
            ? const SizedBox.expand()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide;
                  return Center(
                    child: Container(
                      width: side * 0.34,
                      height: side * 0.34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surfaceOnBackground.withValues(
                          alpha: 0.86,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: side * 0.06,
                            offset: Offset(0, side * 0.015),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        size: side * 0.17,
                        color: palette.accentText,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class CreationArtPainter extends CustomPainter {
  const CreationArtPainter({
    required this.style,
    required this.palette,
    this.seed = 0,
  });

  final CreationArtStyle style;
  final CreationPalette palette;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = palette.surfaceOnBackground);
    final random = math.Random(seed * 31 + style.index);
    final s = size.shortestSide;
    double r(double min, double max) => min + random.nextDouble() * (max - min);
    final colors = [palette.primary, palette.secondary, palette.accent];

    switch (style) {
      case CreationArtStyle.geometric:
        final c1 = Offset(
          size.width * r(0.25, 0.45),
          size.height * r(0.3, 0.5),
        );
        canvas
          ..drawCircle(c1, s * 0.34, Paint()..color = colors[seed % 3])
          ..drawArc(
            Rect.fromCircle(
              center: Offset(size.width * 0.72, size.height * 0.68),
              radius: s * 0.3,
            ),
            math.pi,
            math.pi,
            true,
            Paint()..color = colors[(seed + 1) % 3],
          )
          ..save()
          ..translate(size.width * 0.7, size.height * 0.28)
          ..rotate(0.4)
          ..drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: s * 0.3,
              height: s * 0.3,
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.025
              ..color = palette.text.withValues(alpha: 0.8),
          )
          ..restore();
        CreationTextures.dotGrid(
          canvas,
          Rect.fromLTWH(
            size.width * 0.06,
            size.height * 0.7,
            s * 0.4,
            s * 0.25,
          ),
          color: palette.text.withValues(alpha: 0.35),
          spacing: s * 0.05,
          radius: s * 0.007,
        );
      case CreationArtStyle.organic:
        for (var i = 0; i < 4; i++) {
          CreationTextures.watercolor(
            canvas,
            Offset(size.width * r(0.2, 0.8), size.height * r(0.25, 0.75)),
            s * r(0.25, 0.42),
            colors[(seed + i) % 3],
            seed: seed + i,
          );
        }
      case CreationArtStyle.linework:
        final center = Offset(size.width * r(0.4, 0.6), size.height * 0.55);
        final line = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.008
          ..color = palette.text.withValues(alpha: 0.7);
        for (var i = 1; i <= 6; i++) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: s * 0.07 * i),
            -math.pi * r(0.9, 1.1),
            math.pi * r(0.8, 1.3),
            false,
            line,
          );
        }
        canvas
          ..drawCircle(
            center + Offset(s * 0.22, -s * 0.2),
            s * 0.08,
            Paint()..color = colors[seed % 3],
          )
          ..drawLine(
            Offset(size.width * 0.08, size.height * 0.86),
            Offset(size.width * 0.92, size.height * 0.86),
            line,
          );
      case CreationArtStyle.chalk:
        // Un esquema a tiza: dos círculos que se cruzan, una flecha que
        // señala el cruce, un subrayado y unas estrellitas.
        final chalk = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.012
          ..color = palette.text.withValues(alpha: 0.85);
        final left = Offset(size.width * 0.4, size.height * 0.45);
        final right = Offset(size.width * 0.6, size.height * 0.45);
        canvas
          ..drawPath(
            CreationTextures.blob(left, s * 0.22, seed: seed, wobble: 0.035),
            chalk,
          )
          ..drawPath(
            CreationTextures.blob(
              right,
              s * 0.22,
              seed: seed + 1,
              wobble: 0.035,
            ),
            chalk..color = colors[seed % 3].withValues(alpha: 0.9),
          );
        final tip = Offset(size.width * 0.5, size.height * 0.5);
        final tail = Offset(size.width * 0.2, size.height * 0.86);
        final arrow = chalk..color = colors[(seed + 1) % 3];
        CreationTextures.handLine(canvas, tail, tip, arrow, seed: seed + 2);
        final direction = (tip - tail) / (tip - tail).distance;
        for (final turn in [2.5, -2.5]) {
          final head = Offset(
            direction.dx * math.cos(turn) - direction.dy * math.sin(turn),
            direction.dx * math.sin(turn) + direction.dy * math.cos(turn),
          );
          CreationTextures.handLine(
            canvas,
            tip,
            tip + head * s * 0.07,
            arrow,
            seed: seed + 3,
            jitter: 1,
          );
        }
        CreationTextures.handLine(
          canvas,
          Offset(size.width * 0.58, size.height * 0.84),
          Offset(size.width * 0.88, size.height * 0.82),
          chalk..color = palette.text.withValues(alpha: 0.6),
          seed: seed + 4,
        );
        final star = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.008
          ..color = colors[(seed + 2) % 3];
        for (var k = 0; k < 3; k++) {
          final center = Offset(
            size.width * r(0.1, 0.9),
            size.height * r(0.08, 0.22),
          );
          final arm = s * r(0.02, 0.035);
          for (var a = 0; a < 3; a++) {
            final angle = a * math.pi / 3;
            final d = Offset(math.cos(angle), math.sin(angle)) * arm;
            canvas.drawLine(center - d, center + d, star);
          }
        }
        CreationTextures.chalkDust(
          canvas,
          size,
          color: palette.text,
          seed: seed,
        );
      case CreationArtStyle.neon:
        canvas.drawRect(rect, Paint()..color = palette.background);
        for (var i = 0; i < 3; i++) {
          final color = colors[(seed + i) % 3];
          final center = Offset(
            size.width * (0.3 + 0.2 * i),
            size.height * r(0.35, 0.65),
          );
          final radius = s * (0.12 + 0.06 * i);
          canvas
            ..drawCircle(
              center,
              radius,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = s * 0.04
                ..color = color.withValues(alpha: 0.25)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
            )
            ..drawCircle(
              center,
              radius,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = s * 0.01
                ..color = color,
            );
        }
      case CreationArtStyle.paper:
        for (var i = 0; i < 4; i++) {
          final path = CreationTextures.blob(
            Offset(size.width * r(0.2, 0.8), size.height * (0.25 + i * 0.18)),
            s * r(0.22, 0.34),
            seed: seed * 7 + i,
            wobble: 0.08,
            lobes: 4,
          );
          canvas
            ..drawShadow(path, Colors.black, s * 0.02, false)
            ..drawPath(path, Paint()..color = colors[(seed + i) % 3]);
        }
      case CreationArtStyle.data:
        const bars = 6;
        final base = size.height * 0.85;
        final width = size.width * 0.7 / bars;
        for (var i = 0; i < bars; i++) {
          final height = size.height * r(0.18, 0.62);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                size.width * 0.15 + i * width + width * 0.15,
                base - height,
                width * 0.7,
                height,
              ),
              Radius.circular(width * 0.12),
            ),
            Paint()..color = colors[i % 3].withValues(alpha: 0.85),
          );
        }
        final curve = Path()..moveTo(size.width * 0.1, size.height * 0.6);
        for (var i = 1; i <= 6; i++) {
          curve.lineTo(
            size.width * (0.1 + i * 0.14),
            size.height * r(0.2, 0.55),
          );
        }
        canvas.drawPath(
          curve,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.012
            ..strokeJoin = StrokeJoin.round
            ..color = palette.text,
        );
    }
  }

  @override
  bool shouldRepaint(CreationArtPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.palette != palette ||
      oldDelegate.seed != seed;
}
