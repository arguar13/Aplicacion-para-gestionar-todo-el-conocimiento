import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/design/creation_textures.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';

/// El fondo de cada plantilla (F43): el color, la textura y los ornamentos de
/// los bordes, todo dibujado.
///
/// Las diapositivas «de presentación» —la portada, las secciones y el
/// cierre— llevan el fondo con todo; las de contenido, una versión más
/// callada, para que el texto mande. Los ornamentos van en los márgenes, donde
/// no hay texto, y cambian un poco con [index] para que dos diapositivas
/// seguidas no sean iguales.
///
/// Con el fondo liso o en degradé (F45, `DeckBackground`) se va todo lo que
/// adorna, pero queda la estructura: lo que un diseño necesita debajo de su
/// texto, como la banda oscura de Ejecutiva, donde va el título en claro.
class DeckBackgroundPainter extends CustomPainter {
  const DeckBackgroundPainter({
    required this.style,
    required this.layout,
    required this.index,
  });

  final DeckStyle style;
  final SlideLayout layout;
  final int index;

  CreationPalette get p => style.palette;

  /// La portada, las secciones y el cierre: el fondo con todo lo que no
  /// ocupa lugar (las estrellas, las manchas, los resplandores). El cierre con
  /// preguntas (F45) no: sus paneles llegan arriba a la derecha, donde
  /// algunas plantillas ponen un adorno.
  bool get grand => hero || layout == SlideLayout.closing;

  /// La portada y las secciones: además, lo que ocupa lugar (el círculo
  /// suizo, el piso de neón, las capas de papel), que en el cierre taparía
  /// las ideas para llevarse.
  bool get hero => layout == SlideLayout.cover || layout == SlideLayout.section;

  static Color _a(Color color, double alpha) =>
      color.withValues(alpha: color.a * alpha);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = p.background);
    switch (style.background) {
      case DeckBackground.plain:
        _structure(canvas, size);
      case DeckBackground.gradient:
        _gradient(canvas, size);
        _structure(canvas, size);
      case DeckBackground.texture:
        _texture(canvas, size);
    }
  }

  /// Un degradé suave del fondo hacia el primario, con dos resplandores
  /// tenues del secundario y del acento en las esquinas: el mismo de las
  /// infografías, así una lámina y un mazo combinan.
  void _gradient(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strength = p.isDark ? 0.2 : 0.1;
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
      Offset(size.width * 0.94, size.height * 0.04),
      size.height * (grand ? 0.8 : 0.62),
      _a(p.secondary, p.isDark ? 0.2 : 0.14),
    );
    CreationTextures.glow(
      canvas,
      Offset(size.width * 0.03, size.height * 0.98),
      size.height * (grand ? 0.7 : 0.5),
      _a(p.accent, p.isDark ? 0.16 : 0.12),
    );
  }

  /// Lo que no es adorno: sin esto, un diseño se queda sin el fondo de su
  /// texto.
  void _structure(Canvas canvas, Size size) {
    if (style.design.template == DeckTemplateId.executive) {
      _executive(canvas, size);
    }
  }

  void _texture(Canvas canvas, Size size) {
    switch (style.design.template) {
      case DeckTemplateId.editorial:
        _editorial(canvas, size);
      case DeckTemplateId.parchment:
        _parchment(canvas, size);
      case DeckTemplateId.academic:
        _academic(canvas, size);
      case DeckTemplateId.newspaper:
        _newspaper(canvas, size);
      case DeckTemplateId.ink:
        _ink(canvas, size);
      case DeckTemplateId.swiss:
        _swiss(canvas, size);
      case DeckTemplateId.bento:
        _bento(canvas, size);
      case DeckTemplateId.aurora:
        _aurora(canvas, size);
      case DeckTemplateId.glass:
        _glass(canvas, size);
      case DeckTemplateId.magazine:
        _magazine(canvas, size);
      case DeckTemplateId.bauhaus:
        _bauhaus(canvas, size);
      case DeckTemplateId.brutalist:
        _brutalist(canvas, size);
      case DeckTemplateId.midnight:
        _midnight(canvas, size);
      case DeckTemplateId.neon:
        _neon(canvas, size);
      case DeckTemplateId.chalkboard:
        _chalkboard(canvas, size);
      case DeckTemplateId.darkMinimal:
        _darkMinimal(canvas, size);
      case DeckTemplateId.terminal:
        _terminal(canvas, size);
      case DeckTemplateId.artDeco:
        _artDeco(canvas, size);
      case DeckTemplateId.watercolor:
        _watercolor(canvas, size);
      case DeckTemplateId.pastel:
        _pastel(canvas, size);
      case DeckTemplateId.paperCut:
        _paperCut(canvas, size);
      case DeckTemplateId.retro:
        _retro(canvas, size);
      case DeckTemplateId.manuscript:
        _manuscript(canvas, size);
      case DeckTemplateId.whiteboard:
        _whiteboard(canvas, size);
      case DeckTemplateId.corporate:
        _corporate(canvas, size);
      case DeckTemplateId.data:
        _data(canvas, size);
      case DeckTemplateId.executive:
        _executive(canvas, size);
      case DeckTemplateId.blueprint:
        _blueprint(canvas, size);
    }
  }

  void _editorial(Canvas canvas, Size size) {
    CreationTextures.grain(canvas, size, color: _a(p.text, 0.05), seed: 11);
    final m = style.marginX;
    final line = Paint()
      ..color = _a(p.text, 0.85)
      ..strokeWidth = 2;
    // El filete de arriba, de margen a margen, y uno más fino debajo.
    canvas
      ..drawLine(Offset(m, 54), Offset(size.width - m, 54), line)
      ..drawLine(
        Offset(m, 62),
        Offset(size.width - m, 62),
        line..strokeWidth = 0.8,
      );
    if (grand) {
      canvas.drawRect(
        Rect.fromLTWH(size.width - m - 18, 92, 18, 140),
        Paint()..color = p.primary,
      );
    }
  }

  void _parchment(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    CreationTextures.grain(
      canvas,
      size,
      color: _a(p.text, 0.07),
      seed: 21,
      density: 0.0024,
    );
    // Dos manchas de tiempo, muy tenues.
    CreationTextures.watercolor(
      canvas,
      Offset(size.width * (index.isEven ? 0.86 : 0.12), size.height * 0.82),
      size.height * 0.32,
      _a(p.secondary, 0.22),
      seed: 4 + index,
    );
    // El viñeteado: los bordes un poco más oscuros, como un papel viejo.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.width * 0.62,
          [_a(p.text, 0), _a(p.text, 0.16)],
          const [0.62, 1],
        ),
    );
    // El doble filete del marco.
    final outer = rect.deflate(34);
    canvas
      ..drawRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _a(p.primary, 0.55),
      )
      ..drawRect(
        outer.deflate(12),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _a(p.primary, 0.45),
      );
    // Un rombo en cada esquina del marco.
    for (final corner in [
      outer.topLeft,
      outer.topRight,
      outer.bottomLeft,
      outer.bottomRight,
    ]) {
      canvas
        ..save()
        ..translate(corner.dx, corner.dy)
        ..rotate(math.pi / 4)
        ..drawRect(
          Rect.fromCenter(center: Offset.zero, width: 18, height: 18),
          Paint()..color = p.primary,
        )
        ..restore();
    }
  }

  void _academic(Canvas canvas, Size size) {
    // La barra vertical del margen izquierdo y un filete abajo.
    canvas
      ..drawRect(
        Rect.fromLTWH(0, 0, 18, size.height),
        Paint()..color = p.primary,
      )
      ..drawRect(
        Rect.fromLTWH(18, 0, 6, size.height),
        Paint()..color = p.accent,
      )
      ..drawLine(
        Offset(style.marginX, size.height - 104),
        Offset(size.width - style.marginX, size.height - 104),
        Paint()
          ..color = _a(p.text, 0.25)
          ..strokeWidth = 1.5,
      );
    // Un sello de anillos concéntricos, apenas visible, arriba a la derecha.
    final center = Offset(size.width - 120, 120);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        center,
        150.0 + i * 26,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _a(p.primary, 0.06),
      );
    }
  }

  void _swiss(Canvas canvas, Size size) {
    // La grilla de doce columnas, casi invisible.
    final columns = style.isNarrow ? 9 : 12;
    final gutter = (size.width - style.marginX * 2) / columns;
    final grid = Paint()
      ..color = _a(p.text, 0.045)
      ..strokeWidth = 1.5;
    for (var i = 0; i <= columns; i++) {
      final x = style.marginX + i * gutter;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final shape = Paint()..color = p.primary;
    if (layout == SlideLayout.cover) {
      canvas.drawCircle(
        Offset(size.width * 0.84, size.height * 0.3),
        size.height * 0.24,
        shape,
      );
    } else if (layout == SlideLayout.section) {
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - size.height * 0.36,
          0,
          size.height * 0.36,
          size.height * 0.36,
        ),
        shape,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(size.width - style.marginX + 24, 60, 28, 28),
        shape,
      );
    }
  }

  void _bento(Canvas canvas, Size size) {
    CreationTextures.dotGrid(
      canvas,
      Offset.zero & size,
      color: _a(p.text, 0.06),
      spacing: 44,
      radius: 2,
    );
  }

  void _aurora(Canvas canvas, Size size) {
    final random = math.Random(41 + index);
    final colors = [p.primary, p.secondary, p.accent, p.primary];
    for (var i = 0; i < colors.length; i++) {
      final center = Offset(
        size.width *
            (i.isEven
                ? random.nextDouble() * 0.4
                : 0.6 + random.nextDouble() * 0.4),
        size.height *
            (i < 2
                ? random.nextDouble() * 0.4
                : 0.6 + random.nextDouble() * 0.4),
      );
      CreationTextures.glow(
        canvas,
        center,
        size.height * (grand ? 0.85 : 0.65),
        _a(colors[i], p.isDark ? 0.5 : 0.42),
      );
    }
    CreationTextures.grain(canvas, size, color: _a(p.text, 0.035), seed: 43);
  }

  void _glass(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final deep = Color.lerp(p.background, const Color(0xFF000000), 0.35)!;
    final lift = Color.lerp(p.background, p.primary, p.isDark ? 0.16 : 0.1)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [lift, p.background, if (p.isDark) deep else p.background],
          const [0, 0.55, 1],
        ),
    );
    final orbs = [
      (Offset(size.width * 0.18, size.height * 0.22), p.secondary),
      (Offset(size.width * 0.85, size.height * 0.75), p.primary),
      (Offset(size.width * 0.62, size.height * 0.1), p.accent),
    ];
    for (final (center, color) in orbs) {
      final shift = Offset((index % 3 - 1) * 60, (index % 2) * 40);
      CreationTextures.glow(
        canvas,
        center + shift,
        size.height * 0.42,
        _a(color, p.isDark ? 0.42 : 0.38),
      );
    }
    // Un brillo diagonal, como el reflejo de un vidrio.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.2, 0),
          Offset(size.width * 0.5, size.height),
          [
            const Color(0x00FFFFFF),
            const Color(0x0FFFFFFF),
            const Color(0x00FFFFFF),
          ],
          const [0.3, 0.5, 0.7],
        ),
    );
  }

  void _midnight(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          Color.lerp(p.background, p.secondary, 0.08)!,
          p.background,
        ]),
    );
    CreationTextures.starfield(
      canvas,
      size,
      color: _a(p.text, 0.55),
      seed: 51 + index % 3,
      count: grand ? 170 : 70,
    );
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = _a(p.primary, 0.5);
    if (grand) {
      // Una órbita fina que cruza la esquina.
      canvas
        ..drawCircle(
          Offset(size.width * 0.92, size.height * 0.12),
          size.height * 0.5,
          gold,
        )
        ..drawCircle(
          Offset(size.width * 0.92, size.height * 0.12),
          size.height * 0.56,
          gold..strokeWidth = 0.8,
        );
    }
    // Los filetes de oro de las esquinas.
    const inset = 40.0;
    const arm = 90.0;
    final corner = Paint()
      ..strokeWidth = 2
      ..color = _a(p.primary, 0.7);
    for (final (x, y, dx, dy) in [
      (inset, inset, 1.0, 1.0),
      (size.width - inset, inset, -1.0, 1.0),
      (inset, size.height - inset, 1.0, -1.0),
      (size.width - inset, size.height - inset, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(Offset(x, y), Offset(x + arm * dx, y), corner)
        ..drawLine(Offset(x, y), Offset(x, y + arm * dy), corner);
    }
  }

  void _neon(Canvas canvas, Size size) {
    final horizon = size.height * (hero ? 0.62 : 0.8);
    CreationTextures.glow(
      canvas,
      Offset(size.width / 2, horizon),
      size.width * 0.45,
      _a(p.primary, hero ? 0.32 : 0.18),
    );
    CreationTextures.perspectiveGrid(
      canvas,
      Rect.fromLTRB(-size.width * 0.2, horizon, size.width * 1.2, size.height),
      color: _a(p.secondary, hero ? 0.35 : 0.16),
    );
    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..color = _a(p.primary, 0.8)
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Las líneas de barrido de una pantalla vieja.
    final scan = Paint()..color = _a(p.text, 0.025);
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), scan);
    }
  }

  void _chalkboard(Canvas canvas, Size size) {
    CreationTextures.chalkDust(
      canvas,
      size,
      color: p.text,
      seed: 61 + index % 4,
    );
    // El borde gastado del pizarrón y la repisa de abajo.
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..color = Color.lerp(p.background, const Color(0xFF000000), 0.35)!;
    canvas.drawRect((Offset.zero & size).deflate(11), frame);
    final chalk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = _a(p.primary, 0.5);
    // La marca de tiza de la repisa, debajo del número de la diapositiva.
    CreationTextures.handLine(
      canvas,
      Offset(size.width - 380, size.height - 34),
      Offset(size.width - 110, size.height - 38),
      chalk,
      seed: index,
    );
    if (grand) {
      CreationTextures.handLine(
        canvas,
        const Offset(110, 120),
        const Offset(300, 112),
        chalk..color = _a(p.secondary, 0.5),
        seed: index + 3,
      );
    }
  }

  void _watercolor(Canvas canvas, Size size) {
    CreationTextures.grain(canvas, size, color: _a(p.text, 0.04), seed: 71);
    final spots = grand
        ? [
            (Offset(size.width * 0.06, size.height * 0.1), 0.42, p.primary),
            (Offset(size.width * 0.95, size.height * 0.92), 0.48, p.secondary),
            (Offset(size.width * 0.9, size.height * 0.08), 0.22, p.accent),
          ]
        // En las de contenido, lejos del pie: una arriba a la derecha y otra
        // asomando del borde izquierdo.
        : [
            (Offset(size.width * 0.99, size.height * 0.02), 0.24, p.primary),
            (
              Offset(
                -size.height * 0.08,
                size.height * (0.45 + (index % 3) * 0.08),
              ),
              0.24,
              index.isEven ? p.secondary : p.accent,
            ),
          ];
    var seed = index * 5;
    for (final (center, radius, color) in spots) {
      CreationTextures.watercolor(
        canvas,
        center,
        size.height * radius,
        _a(color, 0.85),
        seed: seed++,
      );
    }
  }

  void _pastel(Canvas canvas, Size size) {
    final h = size.height;
    canvas
      ..drawCircle(
        Offset(size.width - h * 0.06, h * 0.08),
        h * (grand ? 0.26 : 0.16),
        Paint()..color = _a(p.accent, 0.35),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(h * 0.02, h * 0.98),
            width: h * (grand ? 0.5 : 0.32),
            height: h * (grand ? 0.5 : 0.32),
          ),
          Radius.circular(h * 0.08),
        ),
        Paint()..color = _a(p.secondary, 0.3),
      );
    if (layout == SlideLayout.cover) {
      // Una ondita y unos puntos, como de cuaderno: solo en la portada, que
      // no lleva número (en las demás quedaría debajo de él).
      final wave = Path()..moveTo(size.width - h * 0.5, h * 0.9);
      for (var i = 1; i <= 6; i++) {
        wave.relativeQuadraticBezierTo(
          h * 0.025,
          (i.isEven ? 1 : -1) * h * 0.04,
          h * 0.05,
          0,
        );
      }
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = _a(p.primary, 0.45),
      );
      CreationTextures.dotGrid(
        canvas,
        Rect.fromLTWH(h * 0.12, h * 0.1, h * 0.3, h * 0.18),
        color: _a(p.primary, 0.35),
        spacing: 30,
        radius: 4,
      );
    }
  }

  void _paperCut(Canvas canvas, Size size) {
    final h = size.height;
    final colors = [p.secondary, p.accent, p.primary];
    if (!hero) {
      // En las de contenido, tres recortes en la esquina de arriba a la
      // derecha: abajo estorbarían el pie.
      for (var layer = 0; layer < 3; layer++) {
        final blob = CreationTextures.blob(
          Offset(size.width + h * 0.03, -h * 0.03),
          h * (0.17 - layer * 0.04),
          seed: 9 + layer + index,
          wobble: 0.08,
          lobes: 5,
        );
        canvas
          ..drawShadow(blob, const Color(0xFF000000), 8, false)
          ..drawPath(blob, Paint()..color = colors[layer]);
      }
      CreationTextures.grain(canvas, size, color: _a(p.text, 0.035), seed: 81);
      return;
    }
    const bottom = 0.26;
    for (var layer = 0; layer < 3; layer++) {
      final top = h * (1 - bottom + layer * bottom * 0.28);
      final path = Path()
        ..moveTo(0, h)
        ..lineTo(0, top);
      const waves = 5;
      for (var i = 0; i < waves; i++) {
        final x0 = size.width * i / waves;
        final x1 = size.width * (i + 1) / waves;
        path.quadraticBezierTo(
          (x0 + x1) / 2,
          top + ((i + layer + index).isEven ? -1 : 1) * h * 0.035,
          x1,
          top,
        );
      }
      path
        ..lineTo(size.width, h)
        ..close();
      canvas
        ..drawShadow(path, const Color(0xFF000000), 10, false)
        ..drawPath(path, Paint()..color = colors[layer]);
    }
    {
      final blob = CreationTextures.blob(
        Offset(size.width * 0.9, h * 0.14),
        h * 0.13,
        seed: 3 + index,
        wobble: 0.1,
        lobes: 5,
      );
      canvas
        ..drawShadow(blob, const Color(0xFF000000), 8, false)
        ..drawPath(blob, Paint()..color = _a(p.accent, 0.9));
    }
    CreationTextures.grain(canvas, size, color: _a(p.text, 0.035), seed: 81);
  }

  void _corporate(Canvas canvas, Size size) {
    final h = size.height;
    // Dos triángulos de la marca en la esquina de abajo a la derecha.
    final big = Path()
      ..moveTo(size.width, h - h * (hero ? 0.42 : 0.16))
      ..lineTo(size.width, h)
      ..lineTo(size.width - h * (hero ? 0.42 : 0.16), h)
      ..close();
    final small = Path()
      ..moveTo(size.width, h - h * (hero ? 0.24 : 0.09))
      ..lineTo(size.width, h)
      ..lineTo(size.width - h * (hero ? 0.62 : 0.24), h)
      ..close();
    canvas
      ..drawPath(big, Paint()..color = _a(p.accent, 0.85))
      ..drawPath(small, Paint()..color = p.primary);
  }

  void _data(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    CreationTextures.lineGrid(
      canvas,
      rect,
      color: _a(p.text, 0.045),
      majorColor: _a(p.text, 0.08),
    );
    // Una barrita de cifras en la esquina: el sello de la plantilla.
    final base = Offset(size.width - style.marginX - 120, 96);
    final heights = <double>[22, 40, 30, 54];
    for (var i = 0; i < heights.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(base.dx + i * 30, base.dy - heights[i], 20, heights[i]),
        Paint()..color = i == 3 ? p.primary : _a(p.primary, 0.35),
      );
    }
  }

  void _executive(Canvas canvas, Size size) {
    if (layout == SlideLayout.cover || layout == SlideLayout.closing) {
      // La banda oscura de la portada: el título va adentro.
      final band = size.width * 0.42;
      canvas
        ..drawRect(
          Rect.fromLTWH(0, 0, band, size.height),
          Paint()..color = p.primary,
        )
        ..drawRect(
          Rect.fromLTWH(band, 0, 10, size.height),
          Paint()..color = p.secondary,
        );
    } else if (layout == SlideLayout.section) {
      // La sección la dibuja su diseño (la banda con el número).
    } else {
      canvas
        ..drawRect(
          Rect.fromLTWH(0, 0, 22, size.height),
          Paint()..color = p.primary,
        )
        ..drawRect(
          Rect.fromLTWH(22, 0, 4, size.height),
          Paint()..color = p.secondary,
        );
    }
  }

  // ---------------------------------------------------------------------
  // Las doce de F45.

  void _newspaper(Canvas canvas, Size size) {
    CreationTextures.grain(
      canvas,
      size,
      color: _a(p.text, 0.07),
      seed: 101,
      density: 0.0022,
    );
    final m = style.marginX;
    if (layout != SlideLayout.cover) {
      // El filete grueso y el fino de arriba, como la línea de la fecha de un
      // diario. La portada trae los suyos, en la cabecera.
      final rule = Paint()
        ..color = _a(p.text, 0.9)
        ..strokeWidth = 3;
      canvas
        ..drawLine(Offset(m, 46), Offset(size.width - m, 46), rule)
        ..drawLine(
          Offset(m, 54),
          Offset(size.width - m, 54),
          rule..strokeWidth = 1,
        );
    }
    if (hero) {
      // La trama de una foto de imprenta, que se apaga hacia el texto.
      final dot = Paint()..color = _a(p.text, 0.1);
      const step = 22.0;
      final from = Offset(size.width * 0.72, size.height * 0.74);
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
    }
  }

  void _ink(Canvas canvas, Size size) {
    CreationTextures.grain(canvas, size, color: _a(p.text, 0.045), seed: 111);
    final h = size.height;
    // Las aguadas: la tinta diluida, gris, que se abre en el papel.
    if (grand) {
      CreationTextures.watercolor(
        canvas,
        Offset(size.width * 0.04, h * 0.96),
        h * 0.42,
        _a(p.text, 0.5),
        seed: 3 + index,
      );
      CreationTextures.watercolor(
        canvas,
        Offset(size.width * 0.97, h * 0.06),
        h * 0.2,
        _a(p.accent, 0.6),
        seed: 9 + index,
      );
    } else {
      CreationTextures.watercolor(
        canvas,
        Offset(size.width * 1.01, h * -0.02),
        h * 0.2,
        _a(p.text, 0.4),
        seed: 5 + index,
      );
    }
    if (hero) {
      // Una pincelada: el trazo grueso, de un solo gesto, abajo a la
      // izquierda.
      CreationTextures.handLine(
        canvas,
        Offset(size.width * 0.07, h * 0.9),
        Offset(size.width * 0.34, h * 0.88),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 22
          ..color = _a(p.primary, 0.8),
        seed: index,
        jitter: 5,
      );
    }
    // El sello rojo, chico, arriba a la derecha: un cuadrado con su marco
    // en blanco adentro.
    final seal = Rect.fromLTWH(size.width - style.marginX + 34, 62, 44, 44);
    canvas
      ..drawRect(seal, Paint()..color = p.secondary)
      ..drawRect(
        seal.deflate(7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = _a(p.onSecondary, 0.85),
      );
  }

  void _magazine(Canvas canvas, Size size) {
    if (layout == SlideLayout.cover) {
      // El bloque de color a sangre, detrás de la foto de la portada.
      canvas
        ..drawRect(
          Rect.fromLTWH(size.width * 0.62, 0, size.width * 0.38, size.height),
          Paint()..color = p.primary,
        )
        ..drawRect(
          Rect.fromLTWH(size.width * 0.62 - 18, size.height * 0.12, 18, 180),
          Paint()..color = p.accent,
        );
      return;
    }
    // En las demás, la pestaña de color de arriba, como la sección de una
    // revista.
    canvas
      ..drawRect(
        Rect.fromLTWH(style.marginX, 0, 220, 22),
        Paint()..color = p.primary,
      )
      ..drawRect(
        Rect.fromLTWH(style.marginX + 220, 0, 60, 22),
        Paint()..color = p.accent,
      );
  }

  void _bauhaus(Canvas canvas, Size size) {
    final h = size.height;
    if (hero) {
      // La composición: un círculo grande, medio círculo, un triángulo y una
      // barra, en la tercera parte de la derecha: el afiche deja su texto en
      // los dos tercios de la izquierda.
      final right = size.width;
      canvas
        ..drawCircle(
          Offset(right - h * 0.3, h * 0.32),
          h * 0.22,
          Paint()..color = p.primary,
        )
        ..drawArc(
          Rect.fromCircle(center: Offset(right - h * 0.1, h), radius: h * 0.26),
          math.pi,
          math.pi,
          true,
          Paint()..color = p.secondary,
        )
        ..drawPath(
          Path()
            ..moveTo(right - h * 0.5, h * 0.98)
            ..lineTo(right - h * 0.32, h * 0.64)
            ..lineTo(right - h * 0.14, h * 0.98)
            ..close(),
          Paint()..color = p.accent,
        )
        ..drawRect(
          Rect.fromLTWH(right - h * 0.56, h * 0.08, h * 0.04, h * 0.44),
          Paint()..color = p.text,
        );
      return;
    }
    // En las de contenido, el trío chico arriba a la derecha.
    final x = size.width - style.marginX + 18;
    canvas
      ..drawCircle(Offset(x, 66), 14, Paint()..color = p.primary)
      ..drawRect(
        Rect.fromLTWH(x - 14, 92, 28, 28),
        Paint()..color = p.secondary,
      )
      ..drawPath(
        Path()
          ..moveTo(x - 15, 160)
          ..lineTo(x, 134)
          ..lineTo(x + 15, 160)
          ..close(),
        Paint()..color = p.accent,
      );
  }

  void _brutalist(Canvas canvas, Size size) {
    // El marco grueso de todas, del color del texto.
    canvas.drawRect(
      (Offset.zero & size).deflate(30),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = p.text,
    );
    if (hero) {
      // Un bloque de acento en la esquina, como una etiqueta pegada.
      final block = Rect.fromLTWH(size.width - 330, 24, 306, 120);
      canvas
        ..drawRect(block.shift(const Offset(14, 14)), Paint()..color = p.text)
        ..drawRect(block, Paint()..color = p.accent)
        ..drawRect(
          block,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = p.text,
        );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(size.width - 96, 24, 72, 72),
        Paint()..color = p.accent,
      );
    }
  }

  void _retro(Canvas canvas, Size size) {
    final h = size.height;
    final colors = [p.primary, p.accent, p.secondary, p.primary, p.accent];
    final corner = Offset(size.width, 0);
    if (grand) {
      // Un sol de franjas que asoma de la esquina de arriba a la derecha.
      for (var i = 0; i < colors.length; i++) {
        canvas.drawCircle(
          corner,
          h * (0.55 - i * 0.09),
          Paint()..color = _a(colors[i], i.isEven ? 0.9 : 0.75),
        );
      }
      canvas.drawCircle(corner, h * 0.1, Paint()..color = p.background);
    } else {
      // Las tres franjas de arriba a la izquierda, sobre el título.
      for (var i = 0; i < 3; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(style.marginX, 30.0 + i * 16, 260.0 - i * 50, 10),
            const Radius.circular(5),
          ),
          Paint()..color = colors[i],
        );
      }
    }
    CreationTextures.grain(canvas, size, color: _a(p.text, 0.035), seed: 121);
  }

  void _manuscript(Canvas canvas, Size size) {
    // Los renglones azules del cuaderno, de margen a margen.
    final line = Paint()
      ..color = _a(p.primary, 0.16)
      ..strokeWidth = 2;
    for (var y = 150.0; y < size.height - 20; y += 62) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // El margen rojo.
    final margin = style.marginX - 36;
    canvas.drawLine(
      Offset(margin, 0),
      Offset(margin, size.height),
      Paint()
        ..color = _a(p.secondary, 0.5)
        ..strokeWidth = 3,
    );
    // Los agujeros de la carpeta, a la izquierda del margen.
    final hole = Paint()
      ..color = Color.lerp(p.background, p.text, p.isDark ? 0.5 : 0.14)!;
    for (final t in [0.2, 0.5, 0.8]) {
      canvas.drawCircle(Offset(margin / 2, size.height * t), 14, hole);
    }
  }

  void _whiteboard(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Lo que quedó de lo borrado: manchas apenas visibles.
    final random = math.Random(131 + index);
    for (var i = 0; i < 5; i++) {
      CreationTextures.glow(
        canvas,
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        size.height * (0.2 + random.nextDouble() * 0.2),
        _a(p.text, 0.035),
      );
    }
    // El marco de aluminio.
    canvas.drawRect(
      rect.deflate(8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          Color.lerp(p.background, p.text, 0.18)!,
          Color.lerp(p.background, p.text, 0.32)!,
        ]),
    );
    final marker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7;
    if (grand) {
      // Un círculo y una flecha a marcador, en la esquina.
      final center = Offset(size.width - 150, 150);
      final path = Path();
      for (var i = 0; i <= 28; i++) {
        final t = i / 28 * math.pi * 2.1;
        final r = 70 + math.sin(t * 3) * 3;
        final point = center + Offset(math.cos(t) * r, math.sin(t) * r * 0.82);
        i == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, marker..color = _a(p.secondary, 0.75));
      CreationTextures.handLine(
        canvas,
        Offset(size.width - 330, 236),
        Offset(size.width - 226, 170),
        marker..color = _a(p.primary, 0.75),
        seed: index,
      );
    } else {
      // Un tilde a marcador arriba a la derecha.
      final x = size.width - style.marginX + 12;
      final check = Path()
        ..moveTo(x, 78)
        ..lineTo(x + 14, 94)
        ..lineTo(x + 44, 56);
      canvas.drawPath(check, marker..color = _a(p.accent, 0.8));
    }
  }

  void _darkMinimal(Canvas canvas, Size size) {
    if (grand) {
      // Una luz muy tenue arriba, como un escenario.
      CreationTextures.glow(
        canvas,
        Offset(size.width * 0.3, -size.height * 0.2),
        size.height * 0.9,
        _a(p.primary, 0.08),
      );
      // El punto de acento, arriba a la derecha: abajo estaría el número.
      canvas.drawCircle(
        Offset(size.width - style.marginX, style.marginY * 0.6),
        9,
        Paint()..color = p.primary,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(style.marginX, 52, 64, 5),
        Paint()..color = p.primary,
      );
    }
  }

  void _terminal(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // El resplandor del tubo y las líneas de barrido.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(rect.center, size.width * 0.7, [
          _a(p.primary, 0.07),
          _a(p.primary, 0),
        ]),
    );
    final scan = Paint()..color = _a(p.text, 0.035);
    for (var y = 0.0; y < size.height; y += 5) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), scan);
    }
    // La barra de la ventana, con sus tres botones.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 44),
      Paint()..color = Color.lerp(p.background, p.text, 0.07)!,
    );
    for (final (i, color) in [p.secondary, p.accent, p.primary].indexed) {
      canvas.drawCircle(
        Offset(34.0 + i * 30, 22),
        8,
        Paint()..color = _a(color, 0.9),
      );
    }
    if (hero) {
      // El cursor que espera, abajo a la derecha.
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - style.marginX - 28,
          size.height - 150,
          28,
          48,
        ),
        Paint()..color = _a(p.primary, 0.85),
      );
    }
  }

  void _artDeco(Canvas canvas, Size size) {
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = _a(p.primary, 0.8);
    // Los escalonados de las cuatro esquinas.
    const inset = 34.0;
    const step = 22.0;
    for (final (x, y, dx, dy) in [
      (inset, inset, 1.0, 1.0),
      (size.width - inset, inset, -1.0, 1.0),
      (inset, size.height - inset, 1.0, -1.0),
      (size.width - inset, size.height - inset, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(x + dx * 150, y)
        ..lineTo(x + dx * step * 2, y)
        ..lineTo(x + dx * step * 2, y + dy * step)
        ..lineTo(x + dx * step, y + dy * step)
        ..lineTo(x + dx * step, y + dy * step * 2)
        ..lineTo(x, y + dy * step * 2)
        ..lineTo(x, y + dy * 150);
      canvas.drawPath(path, gold);
    }
    if (grand) {
      // El abanico de rayos, abajo al centro.
      final center = Offset(size.width / 2, size.height + 24);
      final radius = size.height * 0.3;
      const rays = 15;
      for (var i = 0; i < rays; i++) {
        final angle = math.pi + math.pi * (i + 0.5) / rays;
        canvas.drawLine(
          center,
          center + Offset(math.cos(angle), math.sin(angle)) * radius,
          Paint()
            ..strokeWidth = 2
            ..color = _a(p.primary, i.isEven ? 0.3 : 0.14),
        );
      }
      // Tenues: la bajada de una portada larga puede pasar por encima.
      for (final r in [radius * 0.45, radius * 0.7, radius]) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          math.pi,
          math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _a(p.primary, 0.3),
        );
      }
    }
  }

  void _blueprint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    CreationTextures.lineGrid(
      canvas,
      rect,
      color: _a(p.text, 0.07),
      majorColor: _a(p.text, 0.13),
    );
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _a(p.text, 0.55);
    // Las marcas de registro de las esquinas.
    for (final corner in [
      const Offset(48, 48),
      Offset(size.width - 48, 48),
      Offset(48, size.height - 48),
      Offset(size.width - 48, size.height - 48),
    ]) {
      canvas
        ..drawLine(
          corner - const Offset(16, 0),
          corner + const Offset(16, 0),
          ink,
        )
        ..drawLine(
          corner - const Offset(0, 16),
          corner + const Offset(0, 16),
          ink,
        )
        ..drawCircle(corner, 8, ink);
    }
    if (hero) {
      // La cota de arriba: una línea con sus dos topes, de margen a margen.
      final y = style.marginY * 0.55;
      final left = style.marginX;
      final right = size.width - style.marginX;
      canvas
        ..drawLine(Offset(left, y), Offset(right, y), ink)
        ..drawLine(Offset(left, y - 12), Offset(left, y + 12), ink)
        ..drawLine(Offset(right, y - 12), Offset(right, y + 12), ink);
    }
    if (layout == SlideLayout.cover) {
      // El rótulo del dibujo, abajo a la izquierda, debajo del texto.
      final box = Rect.fromLTWH(style.marginX, size.height - 78, 360, 52);
      canvas
        ..drawRect(box, ink)
        ..drawLine(
          Offset(box.left + 120, box.top),
          Offset(box.left + 120, box.bottom),
          ink,
        )
        ..drawLine(
          Offset(box.left + 120, box.center.dy),
          Offset(box.right, box.center.dy),
          ink,
        );
    }
  }

  @override
  bool shouldRepaint(DeckBackgroundPainter oldDelegate) =>
      oldDelegate.style.palette != style.palette ||
      oldDelegate.style.design != style.design ||
      oldDelegate.layout != layout ||
      oldDelegate.index != index;
}
