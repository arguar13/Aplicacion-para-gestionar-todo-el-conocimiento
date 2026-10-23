import 'dart:math';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';

/// Un tramo `[start, end)` del texto extraído.
typedef TextSlice = ({int start, int end});

/// Un rectángulo de color sobre una página, en coordenadas del PDF, y cuál de
/// las capas lo pinta.
typedef PdfPaintBox = ({PdfRect rect, int paint});

/// Dónde cae cada una de las [pageCount] páginas de un PDF en su texto
/// extraído [content] (F36), sin leer ninguna página: el texto son las
/// páginas unidas por [pdfPageSeparator], así que con un separador menos que
/// páginas, el tramo N es la página N. Es una suposición que confirma el texto
/// de cada página al leerla (`PdfStudyPage.onLetters`). Si no da la cuenta
/// —una página con un `---` entre renglones en blanco, un texto que se
/// cambió—, `null`: hay que recorrerlas con [PdfPageWalker].
List<TextSlice>? pdfPageSlicesBySeparator(String content, int pageCount) {
  final slices = <TextSlice>[];
  var start = 0;
  for (;;) {
    final at = content.indexOf(pdfPageSeparator, start);
    if (at < 0) break;
    slices.add((start: start, end: at));
    start = at + pdfPageSeparator.length;
  }
  slices.add((start: start, end: content.length));
  return slices.length == pageCount ? slices : null;
}

/// Recorre las páginas de un PDF en orden, con el texto de cada una, y dice
/// dónde cae cada una en el texto extraído [content] (F36): lo exacto cuando
/// [pdfPageSlicesBySeparator] no alcanza.
///
/// Una página cuyo texto está tal cual ocupa ese tramo. Una que no —una
/// escaneada, con el texto que reconoció el OCR— ocupa hasta el próximo
/// separador.
class PdfPageWalker {
  PdfPageWalker(this.content);

  final String content;
  var _position = 0;

  /// El tramo de la página siguiente, con [clean] su texto
  /// (`cleanPdfPageText`); [last], si es la última del documento.
  TextSlice next(String clean, {required bool last}) {
    final start = _position;
    final end = start + clean.length;
    final exact =
        content.startsWith(clean, start) &&
        (last
            ? end == content.length
            : content.startsWith(pdfPageSeparator, min(end, content.length)));
    final TextSlice slice;
    if (exact) {
      slice = (start: start, end: end);
    } else {
      final separator = last ? -1 : content.indexOf(pdfPageSeparator, start);
      slice = (start: start, end: separator < 0 ? content.length : separator);
    }
    _position = min(slice.end + pdfPageSeparator.length, content.length);
    return slice;
  }
}

/// Una página del PDF ubicada en su texto extraído (F36): de cada posición
/// del texto, qué letra de la página es y dónde está.
class PdfStudyPage {
  PdfStudyPage({
    required this.slice,
    required String rawText,
    required List<PdfRect> charRects,
    required String content,
  }) : _rawText = rawText,
       _charRects = charRects,
       _content = content,
       _rawIndex = pdfCleanToRawIndices(rawText),
       onLetters =
           cleanPdfPageText(rawText) ==
           content.substring(slice.start, slice.end);

  /// El tramo del texto extraído que es esta página.
  final TextSlice slice;

  /// Si el tramo es el texto de la página tal cual, así que lo resaltado se
  /// puede pintar sobre sus letras. Una página escaneada no: su texto lo
  /// reconoció el OCR sobre una foto, y la página no tiene esas letras.
  final bool onLetters;

  /// Si la página tiene letras propias, coincidan o no con su tramo. Sin
  /// ninguna es una página escaneada.
  bool get hasOwnLetters => _rawIndex.isNotEmpty;

  final String _rawText;
  final List<PdfRect> _charRects;
  final List<int> _rawIndex;
  final String _content;

  /// Si alguno de [ranges] —en posiciones del texto extraído— cae en esta
  /// página.
  bool touches(List<TextSlice> ranges) =>
      ranges.any((range) => range.end > slice.start && range.start < slice.end);

  /// Los rectángulos que pintan [ranges] —en posiciones del texto
  /// extraído— sobre la página: uno por renglón y por color. Donde dos se
  /// pisan, pinta el que va más tarde en la lista, que es el de encima: una
  /// palabra clave sobre su oración.
  List<PdfPaintBox> boxes(List<TextSlice> ranges) {
    if (!onLetters) return const [];
    final length = slice.end - slice.start;
    final owner = List<int>.filled(length, -1);
    for (var paint = 0; paint < ranges.length; paint++) {
      final from = max(ranges[paint].start, slice.start) - slice.start;
      final to = min(ranges[paint].end, slice.end) - slice.start;
      for (var i = from; i < to; i++) {
        owner[i] = paint;
      }
    }

    final boxes = <PdfPaintBox>[];
    PdfRect? line;
    var lineOwner = -1;
    void close() {
      final open = line;
      if (open != null) boxes.add((rect: open, paint: lineOwner));
      line = null;
    }

    for (var i = 0; i < length; i++) {
      final paint = owner[i];
      final raw = _rawIndex[i];
      if (paint < 0 ||
          raw >= _charRects.length ||
          _isLineBreak(_rawText.codeUnitAt(raw))) {
        close();
        continue;
      }
      // Un espacio que PDFium agrega entre palabras no tiene lugar en la
      // página: no corta el renglón, y el que sigue lo cubre.
      final rect = _charRects[raw];
      if (rect.isEmpty) continue;
      final open = line;
      if (open != null && paint == lineOwner && _sameLine(open, rect)) {
        line = open.merge(rect);
      } else {
        close();
        line = rect;
        lineOwner = paint;
      }
    }
    close();
    return boxes;
  }

  /// El tramo del texto extraído que es la selección [start, end) de [text]
  /// (F38), o `null` si no se puede ubicar.
  ///
  /// [text] y [charRects] son los de `PdfPageText` —el texto con estructura
  /// que usa el visor para seleccionar—, no los del texto crudo con el que
  /// se armó el texto extraído: `pdfrx` reordena, junta espacios y agrega
  /// los que faltan entre palabras, así que las posiciones de uno no son las
  /// del otro. Lo que sí queda igual son las letras de cada renglón y su
  /// lugar de izquierda a derecha —cambia la altura, que pasa a ser la del
  /// renglón—: con eso se busca la primera y la última letra de la selección
  /// en el texto crudo, y de ahí sale el tramo.
  ///
  /// Se descartan los espacios de las puntas. Como el reordenamiento de
  /// `pdfrx` puede cambiar qué letras caen entre las dos puntas —columnas,
  /// renglones fuera de orden—, el tramo se da por bueno solo si tiene las
  /// mismas letras que la selección; si no, mejor no resaltar que resaltar
  /// otra cosa.
  TextSlice? sliceOfSelection({
    required String text,
    required List<PdfRect> charRects,
    required int start,
    required int end,
  }) {
    if (!onLetters) return null;
    var from = max(0, start);
    var to = min(end, min(text.length, charRects.length));
    bool blank(int i) => _isSpace(text.codeUnitAt(i)) || charRects[i].isEmpty;
    while (from < to && blank(from)) {
      from++;
    }
    while (to > from && blank(to - 1)) {
      to--;
    }
    if (from >= to) return null;

    final first = _cleanIndexOf(charRects[from], last: false);
    final last = _cleanIndexOf(charRects[to - 1], last: true);
    if (first == null || last == null || last < first) return null;

    final slice = (
      start: this.slice.start + first,
      end: this.slice.start + last + 1,
    );
    final selected = text.substring(from, to).replaceAll(_whitespace, '');
    final located = _content
        .substring(slice.start, slice.end)
        .replaceAll(_whitespace, '');
    return selected == located ? slice : null;
  }

  /// La letra del texto crudo que está donde [rect], la de `pdfrx`: la
  /// primera —o la última, con [last]— que coincide de lado a lado y cuyo
  /// centro cae a la altura del renglón (o, en un texto vertical, al revés).
  int? _cleanIndexOf(PdfRect rect, {required bool last}) {
    const eps = 0.05;
    bool near(double a, double b) => (a - b).abs() <= eps;
    int? found;
    for (var i = 0; i < _rawIndex.length; i++) {
      final raw = _rawIndex[i];
      if (raw >= _charRects.length || _isSpace(_rawText.codeUnitAt(raw))) {
        continue;
      }
      final r = _charRects[raw];
      if (r.isEmpty) continue;
      final center = r.center;
      final horizontal =
          near(r.left, rect.left) &&
          near(r.right, rect.right) &&
          center.y >= rect.bottom - eps &&
          center.y <= rect.top + eps;
      final vertical =
          near(r.top, rect.top) &&
          near(r.bottom, rect.bottom) &&
          center.x >= rect.left - eps &&
          center.x <= rect.right + eps;
      if (!horizontal && !vertical) continue;
      if (!last) return i;
      found = i;
    }
    return found;
  }

  /// La posición del texto extraído de la letra en [point] —en coordenadas
  /// del PDF—, o `null` si ahí no hay ninguna.
  int? offsetAt(PdfPoint point) {
    if (!onLetters) return null;
    for (var i = 0; i < _rawIndex.length; i++) {
      final raw = _rawIndex[i];
      if (raw < _charRects.length &&
          _charRects[raw].containsPoint(point, margin: 1)) {
        return slice.start + i;
      }
    }
    return null;
  }
}

bool _isLineBreak(int unit) => unit == 0x0A || unit == 0x0D;

/// Un espacio, un salto de línea, un tabulador o un espacio duro.
bool _isSpace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;

final _whitespace = RegExp(r'\s+');

/// Si [char] sigue el renglón de [line]: a su altura —se pisan al menos la
/// mitad— y a continuación, sin volver al principio ni saltar a otra columna.
bool _sameLine(PdfRect line, PdfRect char) {
  final overlap = min(line.top, char.top) - max(line.bottom, char.bottom);
  final height = min(line.height, char.height);
  if (overlap < height / 2) return false;
  final tallest = max(line.height, char.height);
  return char.left >= line.left - tallest &&
      char.left - line.right <= 2 * tallest;
}
