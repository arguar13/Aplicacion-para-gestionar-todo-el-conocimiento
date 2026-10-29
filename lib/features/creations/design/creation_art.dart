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

  /// Formas de plastilina: redondas, con su brillo y su sombra blanda.
  clay,

  /// Un personaje redondo y tierno, con su carita y unos destellos.
  kawaii,

  /// Bloques en perspectiva isométrica sobre su grilla.
  isometric,

  /// Una explosión de historieta sobre una trama de puntos.
  comic,

  /// Una foto desenfocada: un cielo, unas luces y un horizonte.
  photo,
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
      case CreationArtStyle.clay:
        _clay(canvas, size, colors, r);
      case CreationArtStyle.kawaii:
        _kawaii(canvas, size, colors, r);
      case CreationArtStyle.isometric:
        _isometric(canvas, size, colors);
      case CreationArtStyle.comic:
        _comic(canvas, size, colors, r);
      case CreationArtStyle.photo:
        _photo(canvas, size, colors, r);
    }
  }

  /// Un color más claro o más oscuro, sin cambiar su tono.
  static Color _shade(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0, 1)).toColor();
  }

  void _clay(
    Canvas canvas,
    Size size,
    List<Color> colors,
    double Function(double, double) r,
  ) {
    final s = size.shortestSide;
    for (var i = 0; i < 3; i++) {
      final color = colors[(seed + i) % 3];
      final center = Offset(
        size.width * (0.28 + 0.22 * i + r(-0.04, 0.04)),
        size.height * (i.isEven ? r(0.52, 0.62) : r(0.36, 0.46)),
      );
      final radius = s * (i == 1 ? 0.27 : 0.21);
      final path = CreationTextures.blob(
        center,
        radius,
        seed: seed * 5 + i,
        wobble: 0.06,
        lobes: 3,
      );
      canvas
        ..drawShadow(
          path.shift(Offset(0, s * 0.02)),
          Colors.black,
          s * 0.03,
          false,
        )
        ..drawPath(
          path,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.45),
              radius: 1.05,
              colors: [_shade(color, 0.14), color, _shade(color, -0.16)],
              stops: const [0, 0.55, 1],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        )
        // El brillo de la plastilina, arriba a la izquierda.
        ..drawOval(
          Rect.fromCenter(
            center: center + Offset(-radius * 0.38, -radius * 0.42),
            width: radius * 0.42,
            height: radius * 0.24,
          ),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.42)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
        );
    }
  }

  void _kawaii(
    Canvas canvas,
    Size size,
    List<Color> colors,
    double Function(double, double) r,
  ) {
    final s = size.shortestSide;
    final body = colors[seed % 3];
    final center = Offset(size.width * r(0.42, 0.58), size.height * 0.56);
    final radius = s * 0.3;
    final ink = CreationContrast.readableOn(body);
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: center + Offset(0, radius * 0.98),
          width: radius * 1.7,
          height: radius * 0.22,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.12),
      )
      ..drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * 2.1,
          height: radius * 1.85,
        ),
        Paint()..color = body,
      )
      ..drawOval(
        Rect.fromCenter(
          center: center + Offset(-radius * 0.45, -radius * 0.5),
          width: radius * 0.5,
          height: radius * 0.28,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
    // La carita: dos ojos con su brillo, los cachetes y la sonrisa.
    for (final side in [-1.0, 1.0]) {
      final eye = center + Offset(side * radius * 0.36, -radius * 0.05);
      canvas
        ..drawCircle(eye, radius * 0.11, Paint()..color = ink)
        ..drawCircle(
          eye + Offset(radius * 0.035, -radius * 0.04),
          radius * 0.035,
          Paint()..color = body,
        )
        ..drawOval(
          Rect.fromCenter(
            center: center + Offset(side * radius * 0.62, radius * 0.2),
            width: radius * 0.3,
            height: radius * 0.16,
          ),
          Paint()..color = const Color(0xBFFF8FAB),
        );
    }
    canvas.drawArc(
      Rect.fromCenter(
        center: center + Offset(0, radius * 0.16),
        width: radius * 0.3,
        height: radius * 0.22,
      ),
      0.15,
      math.pi - 0.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 0.05
        ..color = ink,
    );
    // Destellos de cuatro puntas alrededor.
    final sparkle = Paint()..color = colors[(seed + 1) % 3];
    for (var k = 0; k < 4; k++) {
      final at = Offset(
        size.width * (k.isEven ? r(0.08, 0.22) : r(0.78, 0.92)),
        size.height * (k < 2 ? r(0.12, 0.28) : r(0.64, 0.86)),
      );
      final arm = s * r(0.025, 0.045);
      final star = Path()
        ..moveTo(at.dx, at.dy - arm)
        ..quadraticBezierTo(at.dx, at.dy, at.dx + arm, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + arm)
        ..quadraticBezierTo(at.dx, at.dy, at.dx - arm, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - arm)
        ..close();
      canvas.drawPath(star, sparkle);
    }
  }

  void _isometric(Canvas canvas, Size size, List<Color> colors) {
    final s = size.shortestSide;
    final unit = s * 0.13;
    final origin = Offset(size.width * 0.5, size.height * 0.62);
    // Un punto de la grilla isométrica: x baja a la derecha, y baja a la
    // izquierda, z sube.
    Offset iso(double x, double y, double z) => origin.translate(
      (x - y) * unit * math.cos(math.pi / 6),
      (x + y) * unit * math.sin(math.pi / 6) - z * unit,
    );
    final grid = Paint()
      ..strokeWidth = s * 0.004
      ..color = palette.text.withValues(alpha: 0.14);
    for (var i = -3; i <= 3; i++) {
      final t = i.toDouble();
      canvas
        ..drawLine(iso(t, -3, 0), iso(t, 3, 0), grid)
        ..drawLine(iso(-3, t, 0), iso(3, t, 0), grid);
    }
    Path face(List<Offset> points) => Path()..addPolygon(points, true);
    void box(double x, double y, double h, Color color) {
      const w = 1.2;
      canvas
        ..drawPath(
          face([
            iso(x, y, h),
            iso(x + w, y, h),
            iso(x + w, y + w, h),
            iso(x, y + w, h),
          ]),
          Paint()..color = _shade(color, 0.12),
        )
        ..drawPath(
          face([
            iso(x, y + w, h),
            iso(x + w, y + w, h),
            iso(x + w, y + w, 0),
            iso(x, y + w, 0),
          ]),
          Paint()..color = color,
        )
        ..drawPath(
          face([
            iso(x + w, y, h),
            iso(x + w, y + w, h),
            iso(x + w, y + w, 0),
            iso(x + w, y, 0),
          ]),
          Paint()..color = _shade(color, -0.14),
        );
    }

    // De atrás hacia adelante, para que lo de adelante tape.
    const heights = [2.2, 1.4, 2.8, 1.0];
    const spots = [(-2.0, -1.0), (0.4, -2.2), (-0.6, 0.2), (1.2, 0.8)];
    for (var i = 0; i < spots.length; i++) {
      final (x, y) = spots[i];
      box(x, y, heights[(seed + i) % 4], colors[(seed + i) % 3]);
    }
  }

  void _comic(
    Canvas canvas,
    Size size,
    List<Color> colors,
    double Function(double, double) r,
  ) {
    final s = size.shortestSide;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _shade(colors[(seed + 2) % 3], 0.22),
    );
    // La trama de puntos, más grandes hacia una esquina.
    final dot = Paint()..color = Colors.black.withValues(alpha: 0.16);
    final step = s * 0.06;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        final t = (x / size.width + y / size.height) / 2;
        canvas.drawCircle(Offset(x, y), step * (0.08 + 0.22 * t), dot);
      }
    }
    // Las líneas de velocidad.
    final center = Offset(
      size.width * r(0.4, 0.6),
      size.height * r(0.42, 0.58),
    );
    final speed = Paint()
      ..strokeWidth = s * 0.01
      ..color = Colors.black.withValues(alpha: 0.5);
    for (var i = 0; i < 18; i++) {
      final angle = i * math.pi * 2 / 18 + r(-0.08, 0.08);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * s * 0.42,
        center + direction * s * 0.7,
        speed,
      );
    }
    // La explosión: una estrella de puntas desparejas, con su borde negro y
    // una sombra corrida.
    const points = 12;
    final burst = Path()
      ..addPolygon([
        for (var i = 0; i < points * 2; i++)
          center +
              Offset(
                    math.cos(i * math.pi / points - math.pi / 2),
                    math.sin(i * math.pi / points - math.pi / 2),
                  ) *
                  (s * (i.isEven ? r(0.34, 0.4) : r(0.2, 0.25))),
      ], true);
    canvas
      ..drawPath(
        burst.shift(Offset(s * 0.025, s * 0.03)),
        Paint()..color = Colors.black,
      )
      ..drawPath(burst, Paint()..color = colors[seed % 3])
      ..drawPath(
        burst,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.018
          ..color = Colors.black,
      );
  }

  void _photo(
    Canvas canvas,
    Size size,
    List<Color> colors,
    double Function(double, double) r,
  ) {
    final s = size.shortestSide;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _shade(colors[(seed + 1) % 3], -0.12),
            _shade(colors[seed % 3], 0.1),
          ],
        ).createShader(rect),
    );
    // Las luces desenfocadas del fondo.
    for (var i = 0; i < 9; i++) {
      CreationTextures.glow(
        canvas,
        Offset(size.width * r(0, 1), size.height * r(0, 0.6)),
        s * r(0.06, 0.16),
        Colors.white.withValues(alpha: r(0.25, 0.55)),
      );
    }
    // Dos lomas en capas, la de adelante más oscura.
    for (var layer = 0; layer < 2; layer++) {
      final base = size.height * (0.66 + layer * 0.12);
      canvas.drawPath(
        Path()..addPolygon([
          Offset(0, size.height),
          for (var i = 0; i <= 24; i++)
            Offset(
              size.width * i / 24,
              base -
                  math.sin(i / 24 * math.pi * (1.4 + layer) + seed + layer) *
                      s *
                      0.06,
            ),
          Offset(size.width, size.height),
        ], true),
        Paint()..color = _shade(colors[(seed + 2) % 3], -0.12 - layer * 0.12),
      );
    }
    // El viñeteado de la lente.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.85,
          colors: [Color(0x00000000), Color(0x52000000)],
          stops: [0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CreationArtPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.palette != palette ||
      oldDelegate.seed != seed;
}
