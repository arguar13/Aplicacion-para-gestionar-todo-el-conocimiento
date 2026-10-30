import 'package:flutter/material.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_viewport.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El tamaño del minimapa en pantalla.
const kMinimapSize = Size(128, 88);

/// Un punto del minimapa: dónde está un nodo y de qué color.
typedef MinimapDot = ({Offset at, Color color});

/// El minimapa del lienzo (F44, paso 2): todo lo dibujado en chiquito y, con
/// un rectángulo, la parte que se ve. Tocarlo o arrastrarlo lleva ahí, sin
/// cambiar el zoom.
///
/// Quien lo usa lo muestra solo cuando hay algo fuera de la vista: con el
/// lienzo entero a la vista no tiene nada que decir.
class MapMinimap extends StatelessWidget {
  const MapMinimap({
    required this.content,
    required this.visible,
    required this.dots,
    required this.onGoTo,
    super.key,
  });

  /// Lo dibujado, en coordenadas del lienzo.
  final Rect content;

  /// Lo que se ve ahora, en coordenadas del lienzo.
  final Rect visible;

  final List<MinimapDot> dots;

  /// Se llama con el punto del lienzo que se tocó o bajo el dedo.
  final ValueChanged<Offset> onGoTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final geometry = MinimapGeometry(content, kMinimapSize);
    void goTo(Offset local) => onGoTo(geometry.toScene(local));

    return Semantics(
      container: true,
      label: l10n.f44S2Minimap,
      child: Material(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.94),
        elevation: 2,
        shadowColor: colors.shadow.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          key: const ValueKey('map-minimap'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => goTo(details.localPosition),
          onPanStart: (details) => goTo(details.localPosition),
          onPanUpdate: (details) => goTo(details.localPosition),
          child: CustomPaint(
            size: kMinimapSize,
            painter: MinimapPainter(
              geometry: geometry,
              visible: visible,
              dots: dots,
              windowColor: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dibuja los puntos y la ventana de lo visible.
class MinimapPainter extends CustomPainter {
  const MinimapPainter({
    required this.geometry,
    required this.visible,
    required this.dots,
    required this.windowColor,
  });

  final MinimapGeometry geometry;
  final Rect visible;
  final List<MinimapDot> dots;
  final Color windowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint();
    for (final (:at, :color) in dots) {
      dot.color = color;
      canvas.drawCircle(geometry.toMinimap(at), 2.2, dot);
    }
    final window = windowRect(size);
    canvas
      ..drawRect(window, Paint()..color = windowColor.withValues(alpha: 0.14))
      ..drawRect(
        window.deflate(0.75),
        Paint()
          ..color = windowColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  /// La ventana de lo visible, recortada al minimapa y nunca tan chica que no
  /// se vea.
  Rect windowRect(Size size) {
    final raw = geometry.rectToMinimap(visible);
    final clipped = raw.intersect(Offset.zero & size);
    if (clipped.isEmpty) {
      return Rect.fromCenter(center: raw.center, width: 6, height: 6);
    }
    if (clipped.width >= 6 && clipped.height >= 6) return clipped;
    return Rect.fromCenter(
      center: clipped.center,
      width: clipped.width < 6 ? 6 : clipped.width,
      height: clipped.height < 6 ? 6 : clipped.height,
    );
  }

  @override
  bool shouldRepaint(MinimapPainter old) =>
      old.visible != visible ||
      old.dots != dots ||
      old.geometry.content != geometry.content ||
      old.windowColor != windowColor;
}
