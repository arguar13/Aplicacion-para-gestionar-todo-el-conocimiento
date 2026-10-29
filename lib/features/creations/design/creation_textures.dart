import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Las texturas y los fondos dibujados de lo creado (F43): sin una sola
/// imagen, todo con el lienzo, así pesan cero en la app y se ven nítidos a
/// cualquier tamaño, también en el PDF.
///
/// Es determinista: la misma semilla (`seed`) dibuja siempre lo mismo, así la
/// miniatura de la galería y la diapositiva grande coinciden punto por punto
/// y una prueba puede medir un píxel.
abstract final class CreationTextures {
  /// Puntos al azar —siempre los mismos para [seed]— repartidos en [size].
  static List<Offset> scatter(int seed, int count, Size size) {
    final random = math.Random(seed);
    return [
      for (var i = 0; i < count; i++)
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
    ];
  }

  /// El grano del papel: miles de puntitos apenas visibles.
  static void grain(
    Canvas canvas,
    Size size, {
    required Color color,
    int seed = 7,
    double density = 0.0016,
    double dotSize = 1.6,
  }) {
    final count = (size.width * size.height * density).round();
    final points = scatter(seed, count, size);
    final half = points.length ~/ 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = dotSize
      ..color = color;
    canvas.drawPoints(ui.PointMode.points, points.sublist(0, half), paint);
    paint
      ..strokeWidth = dotSize * 1.8
      ..color = color.withValues(alpha: color.a * 0.55);
    canvas.drawPoints(ui.PointMode.points, points.sublist(half), paint);
  }

  /// Una grilla de puntos, como la de un cuaderno punteado.
  static void dotGrid(
    Canvas canvas,
    Rect rect, {
    required Color color,
    double spacing = 48,
    double radius = 2.4,
  }) {
    final paint = Paint()..color = color;
    for (var y = rect.top + spacing / 2; y < rect.bottom; y += spacing) {
      for (var x = rect.left + spacing / 2; x < rect.right; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  /// Una grilla de líneas, con una más marcada cada [majorEvery].
  static void lineGrid(
    Canvas canvas,
    Rect rect, {
    required Color color,
    double spacing = 40,
    double strokeWidth = 1,
    int majorEvery = 5,
    Color? majorColor,
  }) {
    final minor = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    final major = Paint()
      ..color = majorColor ?? color
      ..strokeWidth = strokeWidth * 1.6;
    var i = 0;
    for (var x = rect.left; x <= rect.right; x += spacing, i++) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        i % majorEvery == 0 ? major : minor,
      );
    }
    i = 0;
    for (var y = rect.top; y <= rect.bottom; y += spacing, i++) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        i % majorEvery == 0 ? major : minor,
      );
    }
  }

  /// Un resplandor suave: un degradé radial que se apaga en el borde.
  static void glow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    double intensity = 1,
  }) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            color.withValues(alpha: color.a * intensity),
            color.withValues(alpha: color.a * intensity * 0.45),
            color.withValues(alpha: 0),
          ],
          const [0, 0.45, 1],
        ),
    );
  }

  /// Una mancha orgánica: un círculo con el borde ondulado, como una gota de
  /// acuarela o un recorte de papel.
  static Path blob(
    Offset center,
    double radius, {
    int seed = 1,
    double wobble = 0.18,
    int lobes = 7,
  }) {
    final random = math.Random(seed);
    final phases = [for (var i = 0; i < 3; i++) random.nextDouble() * math.pi];
    final path = Path();
    const steps = 72;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final r =
          radius *
          (1 +
              wobble *
                  (0.55 * math.sin(lobes * t + phases[0]) +
                      0.3 * math.sin((lobes + 3) * t + phases[1]) +
                      0.15 * math.sin(2 * t + phases[2])));
      final point = center + Offset(math.cos(t) * r, math.sin(t) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  /// Una mancha de acuarela: varias capas translúcidas de [blob], corridas,
  /// con el borde un poco más oscuro, como cuando el agua se seca.
  static void watercolor(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    int seed = 1,
  }) {
    for (var layer = 0; layer < 4; layer++) {
      final shift = Offset(
        math.cos(layer * 1.7 + seed) * radius * 0.06,
        math.sin(layer * 2.3 + seed) * radius * 0.06,
      );
      final path = blob(
        center + shift,
        radius * (1 - layer * 0.09),
        seed: seed * 13 + layer,
        wobble: 0.12 + layer * 0.03,
      );
      canvas
        ..drawPath(
          path,
          Paint()..color = color.withValues(alpha: color.a * 0.2),
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.012
            ..color = color.withValues(alpha: color.a * 0.18),
        );
    }
  }

  /// Un cielo de estrellas: puntos de brillo y tamaño variables.
  static void starfield(
    Canvas canvas,
    Size size, {
    required Color color,
    int seed = 3,
    int count = 140,
  }) {
    final random = math.Random(seed);
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final big = random.nextDouble() > 0.92;
      paint.color = color.withValues(
        alpha: color.a * (0.25 + random.nextDouble() * 0.6),
      );
      canvas.drawCircle(point, big ? 2.6 : 1.2 + random.nextDouble(), paint);
    }
  }

  /// El piso de grilla en perspectiva de una pantalla de neón.
  static void perspectiveGrid(
    Canvas canvas,
    Rect rect, {
    required Color color,
    int columns = 18,
    int rows = 9,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    final horizon = rect.top;
    final center = rect.center.dx;
    for (var i = -columns; i <= columns; i++) {
      final bottomX = center + i * rect.width / columns;
      canvas.drawLine(
        Offset(center + i * rect.width / (columns * 6), horizon),
        Offset(bottomX, rect.bottom),
        paint,
      );
    }
    for (var j = 1; j <= rows; j++) {
      final t = math.pow(j / rows, 2).toDouble();
      final y = horizon + t * rect.height;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  /// Polvo de tiza: manchas grandes muy tenues y un grano fino.
  static void chalkDust(
    Canvas canvas,
    Size size, {
    required Color color,
    int seed = 5,
  }) {
    final random = math.Random(seed);
    for (var i = 0; i < 9; i++) {
      glow(
        canvas,
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        size.shortestSide * (0.25 + random.nextDouble() * 0.35),
        color.withValues(alpha: color.a * 0.08),
      );
    }
    grain(
      canvas,
      size,
      color: color.withValues(alpha: color.a * 0.12),
      seed: seed,
      density: 0.0022,
      dotSize: 1.3,
    );
  }

  /// Un trazo «a mano»: la línea de [from] a [to] con un temblor leve, como
  /// la tiza o el lápiz.
  static void handLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    int seed = 1,
    double jitter = 3,
  }) {
    final random = math.Random(seed);
    final path = Path()..moveTo(from.dx, from.dy);
    const segments = 12;
    final normal = Offset(-(to - from).dy, (to - from).dx);
    final unit = normal.distance == 0 ? Offset.zero : normal / normal.distance;
    for (var i = 1; i <= segments; i++) {
      final point =
          Offset.lerp(from, to, i / segments)! +
          unit * ((random.nextDouble() - 0.5) * 2 * jitter);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}
