import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Los tres puntos de una punta de flecha.
typedef ArrowHead = ({Offset tip, Offset left, Offset right});

/// La punta de una flecha que va de [from] a [to]: el vértice a [back] píxeles
/// de [to], y una base de [length] de largo y [half] de semiancho detrás de él.
/// `null` si los dos puntos coinciden. La usan el dibujo del mapa y su
/// exportación a SVG, para que las dos salgan igual.
ArrowHead? arrowHead(
  Offset from,
  Offset to, {
  required double back,
  required double length,
  required double half,
}) {
  final direction = to - from;
  if (direction.distance <= 1) return null;
  final unit = direction / direction.distance;
  final tip = to - unit * back;
  final side = Offset(-unit.dy, unit.dx) * half;
  final base = tip - unit * length;
  return (tip: tip, left: base + side, right: base - side);
}

/// Un [Path] con la punta [head].
Path arrowPath(ArrowHead head) => Path()
  ..moveTo(head.tip.dx, head.tip.dy)
  ..lineTo(head.left.dx, head.left.dy)
  ..lineTo(head.right.dx, head.right.dy)
  ..close();

/// El dibujo dentro de la caja de [boundaryKey] como PNG (F14, D7), o `null` si
/// todavía no hay nada dibujado. Se achica lo justo para que ningún lado pase
/// de [maxSide] píxeles: un mapa grande a doble resolución no cabe en memoria.
Future<Uint8List?> capturePng(
  GlobalKey boundaryKey, {
  double pixelRatio = 2,
  double maxSide = 4096,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null || !boundary.hasSize) return null;
  final longest = math.max(boundary.size.width, boundary.size.height);
  if (longest <= 0) return null;
  final ratio = math.min(pixelRatio, maxSide / longest);
  final image = await boundary.toImage(pixelRatio: ratio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
