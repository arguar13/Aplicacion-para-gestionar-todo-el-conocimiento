import 'dart:ui';

/// Un escritor mínimo de SVG (F14, D7): lo justo para exportar el esquema y el
/// grafo del mapa sin sumar una dependencia. Cada método agrega un elemento, y
/// el texto que llega de los datos —títulos, nombres de temas— se escapa.
///
/// Es puro: no dibuja nada, solo arma el texto del documento.
class SvgWriter {
  /// Un lienzo de [width] × [height], con [background] de fondo si se da.
  SvgWriter({required this.width, required this.height, Color? background}) {
    if (background != null) {
      _body.writeln(
        '<rect width="100%" height="100%" fill="${_hex(background)}"/>',
      );
    }
  }

  final double width;
  final double height;
  final _body = StringBuffer();

  /// Una línea de [from] a [to].
  void line(
    Offset from,
    Offset to, {
    required Color color,
    double strokeWidth = 1,
  }) {
    _body.writeln(
      '<line x1="${_n(from.dx)}" y1="${_n(from.dy)}" x2="${_n(to.dx)}" '
      'y2="${_n(to.dy)}" stroke="${_hex(color)}"${_opacity('stroke', color)} '
      'stroke-width="${_n(strokeWidth)}"/>',
    );
  }

  /// Un círculo.
  void circle(
    Offset center,
    double radius, {
    required Color fill,
    Color? stroke,
    double strokeWidth = 1,
  }) {
    _body.writeln(
      '<circle cx="${_n(center.dx)}" cy="${_n(center.dy)}" r="${_n(radius)}" '
      'fill="${_hex(fill)}"${_opacity('fill', fill)}'
      '${_strokeAttributes(stroke, strokeWidth)}/>',
    );
  }

  /// Un rectángulo con las esquinas redondeadas con [radius].
  void rect(
    Rect rect, {
    required Color fill,
    Color? stroke,
    double strokeWidth = 1,
    double radius = 0,
  }) {
    _body.writeln(
      '<rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
      'width="${_n(rect.width)}" height="${_n(rect.height)}" '
      'rx="${_n(radius)}" fill="${_hex(fill)}"${_opacity('fill', fill)}'
      '${_strokeAttributes(stroke, strokeWidth)}/>',
    );
  }

  /// Un triángulo relleno, para las puntas de flecha.
  void triangle(Offset a, Offset b, Offset c, {required Color fill}) {
    _body.writeln(
      '<polygon points="${_n(a.dx)},${_n(a.dy)} ${_n(b.dx)},${_n(b.dy)} '
      '${_n(c.dx)},${_n(c.dy)}" fill="${_hex(fill)}"${_opacity('fill', fill)}/>',
    );
  }

  /// Un texto de una línea. [at] es el punto de anclaje: con `middle`, el
  /// centro del texto; con `start`, su comienzo; su altura es la línea de base.
  void text(
    String content,
    Offset at, {
    required Color color,
    double size = 12,
    String anchor = 'middle',
    bool bold = false,
  }) {
    _body.writeln(
      '<text x="${_n(at.dx)}" y="${_n(at.dy)}" font-size="${_n(size)}" '
      'font-family="sans-serif" text-anchor="$anchor" fill="${_hex(color)}"'
      '${bold ? ' font-weight="bold"' : ''}>${escape(content)}</text>',
    );
  }

  /// El documento completo.
  String build() =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(width)}" '
      'height="${_n(height)}" viewBox="0 0 ${_n(width)} ${_n(height)}">\n'
      '$_body</svg>\n';

  /// [text] recortado a [maxChars] caracteres, con «…» si se pasaba: lo que
  /// entra en una tarjeta del dibujo.
  static String ellipsize(String text, int maxChars) =>
      text.length <= maxChars ? text : '${text.substring(0, maxChars - 1)}…';

  /// El texto sin lo que XML no admite suelto: `&`, `<`, `>` y las comillas.
  static String escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _strokeAttributes(Color? stroke, double strokeWidth) => stroke == null
      ? ''
      : ' stroke="${_hex(stroke)}"${_opacity('stroke', stroke)} '
            'stroke-width="${_n(strokeWidth)}"';

  /// Un número con hasta dos decimales y sin ceros de más.
  static String _n(double value) {
    final text = value.toStringAsFixed(2);
    return text.contains('.')
        ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : text;
  }

  /// `#rrggbb`, sin el canal alfa —que va aparte, como opacidad—.
  static String _hex(Color color) {
    int channel(double value) => (value * 255).round().clamp(0, 255);
    String two(int value) => value.toRadixString(16).padLeft(2, '0');
    return '#${two(channel(color.r))}${two(channel(color.g))}'
        '${two(channel(color.b))}';
  }

  /// La opacidad de [color] como atributo, si no es total.
  static String _opacity(String attribute, Color color) =>
      color.a >= 0.999 ? '' : ' $attribute-opacity="${_n(color.a)}"';
}
