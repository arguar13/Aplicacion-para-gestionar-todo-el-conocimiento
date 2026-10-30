/// Cómo se ven las capas del lienzo del Mapa (F44, paso 5), en la pantalla y en
/// el SVG, con el mismo dibujo en los dos: el rayo de una contradicción, la
/// línea punteada de un parecido, el tinte del estudio de cada documento y el
/// pulso de lo que se fue a buscar.
///
/// Ninguna se lee solo por el color: la contradicción lleva su rayo, el
/// parecido es punteado y lleva «≈», y el estudio, una insignia —un anillo
/// vacío, la cuenta de lo que toca hoy o una ✓— además del tinte.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/services/canvas_layers.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_edges_painter.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El radio del círculo donde va el rayo de una contradicción.
const kMapTensionMarkRadius = 9.0;

/// Lo menos que tiene que medir una unión para llevar su rayo: más corta, el
/// rayo taparía los dos nodos.
const kMapTensionMarkMinLength = 36.0;

/// El lado del botón «≈» de un parecido.
const kMapSimilarMarkerSize = 30.0;

/// Cómo se corta la línea de un parecido: tanto trazo, tanto hueco.
const _kSimilarDash = 6.0;
const _kSimilarGap = 5.0;

/// Los vértices de un rayo de alto [size] centrado en [center]: el mismo en la
/// pantalla y en el SVG.
List<Offset> boltPoints(Offset center, double size) => [
  for (final (x, y) in const [
    (0.15, -0.5),
    (-0.25, 0.05),
    (0.0, 0.05),
    (-0.15, 0.5),
    (0.25, -0.1),
    (0.0, -0.1),
  ])
    center + Offset(x * size, y * size),
];

/// Dónde va el rayo de una unión en tensión de [a] a [b]: en el medio, si la
/// unión es lo bastante larga para que se vea sin tapar los nodos.
Offset? tensionMarkAt(Offset a, Offset b) =>
    (b - a).distance < kMapTensionMarkMinLength ? null : (a + b) / 2;

/// Dibuja en [canvas] los rayos de las uniones en tensión de [scene] —las que
/// la capa «Contradicciones» deja marcadas (`layeredScene`)—: un círculo del
/// color de la pantalla con el rayo adentro, del color de la unión. [colorOf]
/// dice ese color, ya apagado si queda fuera del foco. Todos los del mismo
/// color, en un solo trazo.
void paintTensionMarks(
  Canvas canvas,
  GraphScene scene,
  Map<String, Offset> positions,
  ColorScheme colors, {
  required Color Function(SceneEdge edge) colorOf,
}) {
  final discs = <Color, Path>{};
  final bolts = <Color, Path>{};
  for (final edge in scene.edges) {
    if (!edge.tension) continue;
    final a = positions[scene.nodes[edge.a].key];
    final b = positions[scene.nodes[edge.b].key];
    if (a == null || b == null) continue;
    final at = tensionMarkAt(a, b);
    if (at == null) continue;
    final color = colorOf(edge);
    (discs[color] ??= Path()).addOval(
      Rect.fromCircle(center: at, radius: kMapTensionMarkRadius),
    );
    (bolts[color] ??= Path()).addPolygon(
      boltPoints(at, kMapTensionMarkRadius * 1.4),
      true,
    );
  }
  for (final MapEntry(key: color, value: path) in discs.entries) {
    canvas
      ..drawPath(
        path,
        Paint()..color = colors.surface.withValues(alpha: color.a),
      )
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }
  for (final MapEntry(key: color, value: path) in bolts.entries) {
    canvas.drawPath(path, Paint()..color = color);
  }
}

/// Escribe en [svg] el rayo de una unión en tensión de [a] a [b], como lo
/// dibuja [paintTensionMarks].
void writeTensionMarkSvg(
  SvgWriter svg,
  Offset a,
  Offset b, {
  required Color color,
  required ColorScheme colors,
}) {
  final at = tensionMarkAt(a, b);
  if (at == null) return;
  svg
    ..circle(
      at,
      kMapTensionMarkRadius,
      fill: colors.surface.withValues(alpha: color.a),
      stroke: color,
      strokeWidth: 1.5,
    )
    ..polygon(boltPoints(at, kMapTensionMarkRadius * 1.4), fill: color);
}

/// El color de la línea de un parecido: el secundario, que no es el de
/// ningún tipo de vínculo entre documentos ni el de una contradicción.
Color mapSimilarColor(ColorScheme colors) =>
    colors.secondary.withValues(alpha: 0.9);

/// Las líneas punteadas de «Parecidos»: un trazo por propuesta, entre los dos
/// documentos, cortado en tramos. Con un foco, las que salen de su vecindario
/// [lit] van apagadas, como las uniones. Todas en dos trazos: las encendidas y
/// las apagadas.
class MapSimilarPainter extends CustomPainter {
  const MapSimilarPainter({
    required this.scene,
    required this.lines,
    required this.positions,
    required this.color,
    this.lit,
  });

  final GraphScene scene;
  final List<MapSimilarLine> lines;
  final Map<String, Offset> positions;
  final Color color;
  final Set<int>? lit;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = Path();
    final dimmed = Path();
    for (final line in lines) {
      final a = positions[scene.nodes[line.a].key];
      final b = positions[scene.nodes[line.b].key];
      if (a == null || b == null) continue;
      _addDashes(mapEdgeLit(lit, line.a, line.b) ? shown : dimmed, a, b);
    }
    for (final (path, color) in [(shown, color), (dimmed, mapDimmed(color))]) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  static void _addDashes(Path path, Offset a, Offset b) {
    final length = (b - a).distance;
    if (length <= 0) return;
    final unit = (b - a) / length;
    for (
      var start = 0.0;
      start < length;
      start += _kSimilarDash + _kSimilarGap
    ) {
      final end = math.min(start + _kSimilarDash, length);
      final from = a + unit * start;
      final to = a + unit * end;
      path
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
    }
  }

  @override
  bool shouldRepaint(MapSimilarPainter old) =>
      old.scene != scene ||
      old.lines != lines ||
      old.positions != positions ||
      old.color != color ||
      old.lit != lit;
}

/// El botón «≈» en el medio de un parecido: tocarlo ofrece vincularlos (F44,
/// paso 5, decisión C: propone, y la persona confirma).
class MapSimilarMarker extends StatelessWidget {
  const MapSimilarMarker({
    required this.semanticsLabel,
    required this.onTap,
    super.key,
  });

  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = mapSimilarColor(colors);
    return Semantics(
      label: semanticsLabel,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '≈',
              style: TextStyle(
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Escribe en [svg] un parecido de [a] a [b], como se ve: la línea punteada y
/// su «≈» en el medio; con [dimmed], apagado como lo que queda fuera del foco.
void writeSimilarSvg(
  SvgWriter svg,
  Offset a,
  Offset b, {
  required ColorScheme colors,
  bool dimmed = false,
}) {
  final base = mapSimilarColor(colors);
  final color = dimmed ? mapDimmed(base) : base;
  final middle = (a + b) / 2;
  svg
    ..line(
      a,
      b,
      color: color,
      strokeWidth: 2,
      dash: const [_kSimilarDash, _kSimilarGap],
    )
    ..circle(
      middle,
      kMapSimilarMarkerSize / 2,
      fill: dimmed ? mapDimmed(colors.surface) : colors.surface,
      stroke: color,
      strokeWidth: 2,
    )
    ..text(
      '≈',
      middle + const Offset(0, 5),
      color: color,
      size: 16,
      bold: true,
    );
}

/// Lo que dice el lector de pantalla del «≈» de un parecido entre [a] y [b].
String similarSemantics(
  AppLocalizations l10n,
  SimilarPair pair, {
  required String a,
  required String b,
}) => l10n.f44S5SimilarPair(a, b, similarPercent(pair));

/// Cuánto se parecen dos documentos, en porcentaje: lo que se muestra.
int similarPercent(SimilarPair pair) => (pair.score.clamp(0, 1) * 100).round();

/// Los colores de un documento con la capa «Estudio»: el fondo teñido, el de
/// la insignia y el de lo que va sobre ella.
typedef MapStudyColors = ({Color fill, Color accent, Color onAccent});

MapStudyColors mapStudyColors(MapStudyState state, ColorScheme colors) =>
    switch (state) {
      MapStudyState.none => (
        fill: colors.surfaceContainerHighest,
        accent: colors.outline,
        onAccent: colors.surface,
      ),
      MapStudyState.due => (
        fill: colors.tertiaryContainer,
        accent: colors.tertiary,
        onAccent: colors.onTertiary,
      ),
      MapStudyState.upToDate => (
        fill: colors.primaryContainer,
        accent: colors.primary,
        onAccent: colors.onPrimary,
      ),
    };

/// Cómo se dice el estudio de un documento: «sin tarjetas», «3 tarjetas para
/// hoy» o «al día».
String mapStudyLabel(AppLocalizations l10n, MapStudyMark mark) =>
    switch (mark.state) {
      MapStudyState.none => l10n.f44S5StudyNone,
      MapStudyState.due => l10n.f44S5StudyDue(mark.due),
      MapStudyState.upToDate => l10n.f44S5StudyUpToDate,
    };

/// El lado de la insignia del estudio.
const kMapStudyBadgeSize = 16.0;

/// La insignia del estudio de un documento: un anillo vacío sin tarjetas, la
/// cuenta de lo que toca hoy, o una ✓ al día. Se distinguen por la forma, no
/// solo por el color.
class MapStudyBadge extends StatelessWidget {
  const MapStudyBadge({required this.mark, super.key});

  final MapStudyMark mark;

  @override
  Widget build(BuildContext context) {
    final study = mapStudyColors(mark.state, Theme.of(context).colorScheme);
    final empty = mark.state == MapStudyState.none;
    return Container(
      key: ValueKey('map-study-${mark.state.name}'),
      width: kMapStudyBadgeSize,
      height: kMapStudyBadgeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: empty ? null : study.accent,
        border: empty ? Border.all(color: study.accent, width: 1.5) : null,
      ),
      child: switch (mark.state) {
        MapStudyState.none => null,
        MapStudyState.due => Text(
          mark.due > 99 ? '99+' : '${mark.due}',
          style: TextStyle(
            fontSize: mark.due > 9 ? 7 : 9,
            height: 1,
            fontWeight: FontWeight.w700,
            color: study.onAccent,
          ),
        ),
        MapStudyState.upToDate => Icon(
          Icons.check,
          size: 11,
          color: study.onAccent,
        ),
      },
    );
  }
}

/// Escribe en [svg] la insignia del estudio centrada en [at], como la dibuja
/// [MapStudyBadge]; con [dimmed], apagada como lo que queda fuera del foco.
void writeStudyBadgeSvg(
  SvgWriter svg,
  Offset at,
  MapStudyMark mark, {
  required ColorScheme colors,
  bool dimmed = false,
}) {
  final study = mapStudyColors(mark.state, colors);
  Color shown(Color color) => dimmed ? mapDimmed(color) : color;
  const radius = kMapStudyBadgeSize / 2;
  switch (mark.state) {
    case MapStudyState.none:
      svg.circle(
        at,
        radius - 0.75,
        fill: colors.surface.withValues(alpha: 0),
        stroke: shown(study.accent),
        strokeWidth: 1.5,
      );
    case MapStudyState.due:
      svg
        ..circle(at, radius, fill: shown(study.accent))
        ..text(
          mark.due > 99 ? '99+' : '${mark.due}',
          at + const Offset(0, 3),
          color: shown(study.onAccent),
          size: 9,
          bold: true,
        );
    case MapStudyState.upToDate:
      svg
        ..circle(at, radius, fill: shown(study.accent))
        ..text(
          '✓',
          at + const Offset(0, 4),
          color: shown(study.onAccent),
          size: 11,
        );
  }
}

/// Un pulso alrededor de lo que el lienzo acaba de ir a buscar (F44, paso 5,
/// «⚲ Buscar» y los demás pedidos): un anillo que crece y se apaga, tres
/// veces. Con «sin animaciones» no está: el anillo fijo del resaltado ya lo
/// marca.
class MapPulse extends StatefulWidget {
  const MapPulse({required this.color, super.key});

  final Color color;

  @override
  State<MapPulse> createState() => _MapPulseState();
}

class _MapPulseState extends State<MapPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Al terminar, el controlador queda en 1: el anillo, apagado.
          final t = Curves.easeOut.transform(_controller.value);
          return CustomPaint(
            painter: _PulsePainter(
              color: widget.color.withValues(alpha: (1 - t) * 0.8),
              grow: t,
            ),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.color, required this.grow});

  final Color color;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0) return;
    final radius = size.shortestSide / 2 * (0.6 + 0.4 * grow);
    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.color != color || old.grow != grow;
}
