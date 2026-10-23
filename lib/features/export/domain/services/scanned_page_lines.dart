import 'dart:math';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Cuánto de cada lado queda de margen en una página escaneada: lo que se
/// deja sin renglones en el cálculo de [scannedPageLines].
const _marginX = 0.08;
const _marginTop = 0.06;
const _marginBottom = 0.06;

/// Lo más alto que puede ser un renglón, como fracción del alto de la
/// página: con pocos renglones en la página no se reparten todo el alto.
const _maxLineHeight = 0.035;

/// Dónde, **aproximadamente**, caen en una página escaneada los renglones de
/// [from]…[to] de [pageText] (F38, decisión D).
///
/// Una página escaneada no tiene letras donde ubicar nada: su texto lo
/// reconoció un OCR sobre la foto y la aplicación **no guarda dónde está
/// cada palabra**, solo el texto. Lo que se puede hacer es repartir los
/// renglones del texto reconocido de arriba abajo, en la parte de la página
/// que no es margen, y poner cada marca en el lugar que le toca a su renglón:
/// la posición relativa del renglón en el texto es la posición relativa en la
/// página.
///
/// Es una aproximación, y se nota en tres cosas:
///
/// - Supone que el texto llena la página: una página con un título arriba y
///   el resto en blanco corre las marcas hacia abajo.
/// - Cada marca cubre el **ancho entero** del renglón entre márgenes, no la
///   palabra: no hay de dónde sacar cuánto mide.
/// - Los renglones en blanco del texto no cuentan, y un renglón largo que el
///   OCR partió en dos cuenta como dos.
///
/// A cambio nunca falla y el recuadro cae en la zona del texto, cerca del
/// renglón, que es lo que alcanza para ver dónde estaba lo marcado.
///
/// [from] y [to] son posiciones de [pageText] (`to` sin incluir). [width] y
/// [height] son el tamaño de la página **como se ve** —ya girada, como lo
/// da `PdfPage`—, que es sobre lo que reconoció el OCR; los rectángulos
/// salen en las coordenadas del PDF sin girar, que son las de las
/// anotaciones, con el origen abajo a la izquierda. Se supone que la página
/// empieza en el 0,0, como casi toda página escaneada.
///
/// Un rectángulo por renglón con algo marcado; vacío si lo marcado son solo
/// espacios.
List<PdfRect> scannedPageLines({
  required String pageText,
  required int from,
  required int to,
  required double width,
  required double height,
  PdfPageRotation rotation = PdfPageRotation.none,
}) {
  // Los renglones con texto, con dónde empieza y termina lo que no es
  // espacio. Los de relleno no ocupan lugar en el reparto.
  final lines = <({int start, int end})>[];
  var lineStart = 0;
  for (;;) {
    final newline = pageText.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? pageText.length : newline;
    var start = lineStart;
    var end = lineEnd;
    while (start < end && _isSpace(pageText.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(pageText.codeUnitAt(end - 1))) {
      end--;
    }
    if (end > start) lines.add((start: start, end: end));
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  if (lines.isEmpty) return const [];

  final usableTop = height * _marginTop;
  final usable = height * (1 - _marginTop - _marginBottom);
  final slot = usable / lines.length;
  final lineHeight = min(slot, height * _maxLineHeight) * 0.9;

  final rects = <PdfRect>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.end <= from || line.start >= to) continue;
    final centre = usableTop + (i + 0.5) * slot;
    rects.add(
      _toPdf(
        left: width * _marginX,
        top: centre - lineHeight / 2,
        right: width * (1 - _marginX),
        bottom: centre + lineHeight / 2,
        width: width,
        height: height,
        rotation: rotation,
      ),
    );
  }
  return rects;
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0D || unit == 0xA0;

/// Un rectángulo de la página como se ve —el origen arriba a la izquierda,
/// el eje de abajo hacia abajo— a las coordenadas del PDF sin girar: el
/// origen abajo a la izquierda y el eje hacia arriba.
PdfRect _toPdf({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required double width,
  required double height,
  required PdfPageRotation rotation,
}) {
  // El alto de la página sin girar: el de lo que se ve, o su ancho si la
  // página está girada un cuarto de vuelta.
  final quarter =
      rotation == PdfPageRotation.clockwise90 ||
      rotation == PdfPageRotation.clockwise270;
  final unrotatedHeight = quarter ? width : height;

  // Un punto (u, v) de lo que se ve, en x y en «y hacia abajo» de la página
  // sin girar.
  ({double x, double down}) corner(double u, double v) => switch (rotation) {
    PdfPageRotation.none => (x: u, down: v),
    PdfPageRotation.clockwise90 => (x: v, down: width - u),
    PdfPageRotation.clockwise180 => (x: width - u, down: height - v),
    PdfPageRotation.clockwise270 => (x: height - v, down: u),
  };

  final a = corner(left, top);
  final b = corner(right, bottom);
  return PdfRect(
    min(a.x, b.x),
    unrotatedHeight - min(a.down, b.down),
    max(a.x, b.x),
    unrotatedHeight - max(a.down, b.down),
  );
}
