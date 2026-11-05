import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';

/// Los títulos de [text], un texto en Markdown —el que guarda la extracción
/// de una página web, un Word, un EPUB o un archivo `.md`—, en su orden y con
/// el nivel que traen (F46, paso 1). Sin correr los niveles: eso lo hace
/// quien los junta (`runningLevels`).
///
/// **Qué es un título**, como en CommonMark:
///
/// - un renglón que empieza con `#` a `######` y un espacio —con hasta tres
///   espacios antes—, sin los `#` que lo cierran;
/// - un párrafo subrayado con `===` (nivel 1) o `---` (nivel 2), sin un
///   renglón en blanco de por medio.
///
/// **Qué no**, aunque lo parezca:
///
/// - lo que está dentro de un bloque de código —entre ` ``` ` o `~~~`, o con
///   cuatro espacios—, de una cita (`>`), de una lista, de una tabla o de un
///   bloque de HTML;
/// - un renglón en negrita suelto (`**Capítulo 1**`): es un párrafo;
/// - `#etiqueta`, sin el espacio;
/// - un título vacío o que es solo marcas o puntuación (`# ***`);
/// - el encabezado de datos de un archivo `.md` (`---` arriba de todo, con
///   `título: …` adentro).
///
/// **Un título partido en renglones** —un salto adentro de un título de Word
/// o de una página web— la extracción lo escribe como varios renglones
/// seguidos del mismo nivel, cada uno con su `#` (F22). Esos renglones, sin
/// uno en blanco entre ellos, son un solo título. Dos títulos distintos
/// siempre van separados por un renglón en blanco: así une la extracción sus
/// bloques.
///
/// El tramo de cada uno es el de su texto, sin los `#` de las puntas; el de
/// uno subrayado, el de su párrafo. Lineal: se mira cada renglón una vez.
List<RawHeading> markdownHeadings(String text) {
  final headings = <RawHeading>[];
  final scan = _Scan(text, headings);
  var lineStart = 0;
  // El encabezado de datos solo puede estar arriba de todo.
  final frontMatterEnd = _frontMatterEnd(text);
  if (frontMatterEnd != null) lineStart = frontMatterEnd;
  while (lineStart <= text.length) {
    final newline = text.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? text.length : newline;
    // Un `\r\n` es el mismo salto: el `\r` no es parte del renglón.
    final contentEnd = lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 13
        ? lineEnd - 1
        : lineEnd;
    scan.line(lineStart, contentEnd);
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  return headings;
}

/// Dónde termina el encabezado de datos de un `.md` —el renglón que sigue al
/// `---` o `...` que lo cierra—, o `null` si [text] no empieza con uno: un
/// `---` arriba de todo seguido de un renglón `clave: valor`. Sin eso, el
/// `---` es una raya.
int? _frontMatterEnd(String text) {
  final opening = _frontMatterOpening.matchAsPrefix(text);
  if (opening == null) return null;
  final keyLine = text.indexOf('\n') + 1;
  return _frontMatterClosing.allMatches(text, keyLine).firstOrNull?.end;
}

/// En qué bloque está el renglón anterior: lo que decide qué es el siguiente.
enum _Block {
  /// Nada abierto: después de un renglón en blanco, o al comienzo.
  none,

  /// Un párrafo, que un subrayado convierte en título.
  paragraph,

  /// Un título con `#`, que el renglón siguiente puede continuar.
  heading,

  /// Una cita, una lista o una tabla: lo que sigue sin un renglón en blanco
  /// y sin empezar otro bloque es parte de ella.
  container,

  /// Un bloque de HTML: todo, hasta el próximo renglón en blanco, es HTML
  /// —un `#` adentro también—.
  html,
}

class _Scan {
  _Scan(this.text, this.headings);

  final String text;
  final List<RawHeading> headings;

  _Block _block = _Block.none;

  /// Del párrafo abierto: dónde empieza y dónde termina su último renglón.
  int _paragraphStart = 0;
  int _paragraphEnd = 0;

  /// Del bloque de código abierto entre cercas: su carácter y su largo.
  int? _fenceChar;
  int _fenceLength = 0;

  /// De una lista abierta: cuánta sangría tiene su contenido. Lo que tenga al
  /// menos esa sangría, aunque venga después de un renglón en blanco, sigue
  /// siendo de la lista.
  int? _listIndent;

  /// El nivel del título con `#` del renglón anterior.
  int _headingLevel = 0;

  void line(int start, int end) {
    if (_fenceChar case final fence?) {
      if (_closesFence(start, end, fence)) _fenceChar = null;
      return;
    }
    final indent = _indentOf(start, end);
    final first = start + indent.chars;
    if (first >= end) {
      _block = _Block.none;
      return;
    }
    if (_block == _Block.html) return;
    // Lo que tiene la sangría del contenido de una lista es de la lista.
    if (_listIndent case final listIndent?) {
      if (indent.columns >= listIndent) {
        _block = _Block.container;
        return;
      }
      if (_block == _Block.none && _listItem(first, end) == null) {
        _listIndent = null;
      }
    }
    if (indent.columns >= 4) {
      // Cuatro espacios: un renglón más del párrafo, o código.
      if (_block == _Block.paragraph) _paragraphEnd = _trimmedEnd(first, end);
      if (_block == _Block.heading) _block = _Block.none;
      return;
    }
    // Una cerca, un título y una raya cierran la lista que haya abierta.
    if (_opensFence(first, end)) {
      _block = _Block.none;
      _listIndent = null;
      return;
    }
    if (_atx(first, end)) {
      _listIndent = null;
      return;
    }
    if (_block == _Block.paragraph && _setext(first, end)) return;
    if (_thematicBreak(first, end)) {
      _block = _Block.none;
      _listIndent = null;
      return;
    }
    final unit = text.codeUnitAt(first);
    if (unit == 0x3E /* > */ || unit == 0x7C /* | */ ) {
      _block = _Block.container;
      return;
    }
    // Una etiqueta abre un bloque de HTML, salvo en medio de un párrafo, donde
    // es parte del texto.
    if (_block != _Block.paragraph &&
        _htmlStart.matchAsPrefix(text.substring(first, end)) != null) {
      _block = _Block.html;
      return;
    }
    if (_listItem(first, end) case final contentIndent?) {
      _listIndent = indent.columns + contentIndent;
      _block = _Block.container;
      return;
    }
    if (_block == _Block.container) return;
    if (_block == _Block.paragraph) {
      if (_tableDelimiter.hasMatch(text.substring(first, end))) {
        // El párrafo era la cabecera de una tabla.
        _block = _Block.container;
        return;
      }
      _paragraphEnd = _trimmedEnd(first, end);
      return;
    }
    _block = _Block.paragraph;
    _paragraphStart = first;
    _paragraphEnd = _trimmedEnd(first, end);
  }

  /// Un título con `#`: lo agrega —o lo une al del renglón anterior, si es
  /// del mismo nivel— y dice si lo era.
  bool _atx(int first, int end) {
    final match = _atxPattern.matchAsPrefix(text.substring(first, end));
    if (match == null) return false;
    final level = match[1]!.length;
    final body = match[2] ?? '';
    final continues = _block == _Block.heading && _headingLevel == level;
    _block = _Block.heading;
    _headingLevel = level;
    final content = body.replaceFirst(_closingHashes, '');
    final contentStart = first + match.start + (match[0]!.length - body.length);
    final title = plainHeadingText(content);
    if (!hasReadableText(title)) {
      // Vacío o solo marcas: no es un título, y no se le une el siguiente.
      _block = _Block.none;
      return true;
    }
    final contentEnd = contentStart + content.trimRight().length;
    if (continues && headings.isNotEmpty) {
      final previous = headings.removeLast();
      headings.add((
        level: level,
        title: '${previous.title} $title',
        start: previous.start,
        end: contentEnd,
      ));
    } else {
      headings.add((
        level: level,
        title: title,
        start: contentStart,
        end: contentEnd,
      ));
    }
    return true;
  }

  /// Un subrayado de `===` o `---` debajo del párrafo abierto: el párrafo es
  /// un título.
  bool _setext(int first, int end) {
    final match = _setextPattern.matchAsPrefix(text.substring(first, end));
    if (match == null) return false;
    _block = _Block.none;
    final title = plainHeadingText(
      text.substring(_paragraphStart, _paragraphEnd),
    );
    if (hasReadableText(title)) {
      headings.add((
        level: match[1]!.startsWith('=') ? 1 : 2,
        title: title,
        start: _paragraphStart,
        end: _paragraphEnd,
      ));
    }
    return true;
  }

  bool _thematicBreak(int first, int end) =>
      _thematicPattern.hasMatch(text.substring(first, end));

  /// Si el renglón abre un bloque de código entre cercas, y lo abre.
  bool _opensFence(int first, int end) {
    final match = _fenceOpening.matchAsPrefix(text.substring(first, end));
    if (match == null) return false;
    final fence = match[1]!;
    // La información de una cerca de comillas no puede tener comillas.
    if (fence.startsWith('`') && match[2]!.contains('`')) return false;
    _fenceChar = fence.codeUnitAt(0);
    _fenceLength = fence.length;
    return true;
  }

  bool _closesFence(int start, int end, int fence) {
    final indent = _indentOf(start, end);
    if (indent.columns >= 4) return false;
    final first = start + indent.chars;
    var run = 0;
    var i = first;
    while (i < end && text.codeUnitAt(i) == fence) {
      run++;
      i++;
    }
    if (run < _fenceLength) return false;
    return text.substring(i, end).trim().isEmpty;
  }

  /// Si el renglón empieza un ítem de una lista, cuánta sangría tiene su
  /// contenido desde la marca; si no, `null`.
  int? _listItem(int first, int end) {
    final match = _listMarker.matchAsPrefix(text.substring(first, end));
    return match?[0]!.length;
  }

  ({int chars, int columns}) _indentOf(int start, int end) {
    var chars = 0;
    var columns = 0;
    while (start + chars < end) {
      final unit = text.codeUnitAt(start + chars);
      if (unit == 0x20) {
        columns++;
      } else if (unit == 0x09) {
        columns += 4 - columns % 4;
      } else {
        break;
      }
      chars++;
    }
    return (chars: chars, columns: columns);
  }

  int _trimmedEnd(int first, int end) {
    var e = end;
    while (e > first && _isSpace(text.codeUnitAt(e - 1))) {
      e--;
    }
    return e;
  }
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

final _frontMatterOpening = RegExp(r'---[ \t]*\r?\n[\w-]+[ \t]*:');
final _frontMatterClosing = RegExp(
  r'^(?:---|\.\.\.)[ \t]*(?:\r?\n|$)',
  multiLine: true,
);
final _htmlStart = RegExp('<[A-Za-z/!?]');
final _atxPattern = RegExp(r'(#{1,6})(?:[ \t]+(.*))?$');
final _closingHashes = RegExp(r'(?:^|[ \t]+)#+[ \t]*$|[ \t]+$');
final _setextPattern = RegExp(r'(=+|-+)[ \t]*$');
final _thematicPattern = RegExp(r'^([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _fenceOpening = RegExp(r'(`{3,}|~{3,})(.*)$');
final _listMarker = RegExp(r'(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)');
final _tableDelimiter = RegExp(
  r'^\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$',
);
