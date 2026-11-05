import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';

/// Los títulos de [text], el texto de un PDF sin marcadores, **tal como los
/// deja la IA al ordenarlo al triar** (F45, decisión B): cada título solo en
/// su renglón, con un renglón en blanco antes y otro después. La IA no los
/// marca de otra forma —no escribe Markdown, para no cambiar el texto, que se
/// comprueba palabra por palabra—, así que acá se reconocen por esa forma y
/// por lo que los distingue de un párrafo.
///
/// Un bloque —lo que va entre dos renglones en blanco— es un título si:
///
/// - es **un solo renglón**, corto: hasta [kIsolatedTitleMaxWords] palabras y
///   [kIsolatedTitleMaxChars] caracteres, con alguna letra;
/// - **empieza** con mayúscula, un número, `¿`, `¡` o comillas, y **no
///   termina** como termina o se corta una oración —punto, coma, punto y
///   coma, dos puntos, puntos suspensivos o un guion de corte—;
/// - **lo de antes cerró**: es el comienzo del texto, otro título o un
///   párrafo que termina una oración. Un renglón que sigue a un párrafo
///   cortado a la mitad es la continuación de ese párrafo, no un título;
/// - **lo de después lo sigue**: hay algo más, y no empieza en minúscula,
///   como empezaría la continuación de una oración partida;
/// - no es un número de página, una viñeta ni la raya que separa las
///   páginas, y no es un encabezado o un pie que se repite en el borde de
///   las páginas (`TidyMargins`) que la IA no haya sacado.
///
/// El nivel sale de su numeración —«1.2.3 El origen» es de nivel 3—; sin
/// numeración, todos son de nivel 1: la IA no dice más, y el Índice no lo
/// inventa.
///
/// **Si la forma no es la de un texto ordenado, ninguno**: un texto en el que
/// más de la mitad de los bloques serían títulos —un PDF extraído con un
/// renglón en blanco entre renglón y renglón— no tiene títulos que se puedan
/// reconocer así, y el documento queda como «Texto completo» antes que con
/// capítulos inventados.
///
/// Lineal: se mira cada renglón una vez, más una pasada para los márgenes.
List<RawHeading> isolatedTitles(String text) {
  final blocks = _blocksOf(text);
  final margins = TidyMargins.of(text);
  final titles = <RawHeading>[];
  var contentBlocks = 0;
  _Block? previous;
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (block.separator) continue;
    contentBlocks++;
    final next = _nextContent(blocks, i);
    final line = text.substring(block.start, block.end);
    final isTitle =
        block.lines == 1 &&
        _looksLikeTitle(line) &&
        (previous == null || previous.title || _endsSentence(text, previous)) &&
        next != null &&
        !_startsLowercase(text.codeUnitAt(next.start)) &&
        !(_atPageEdge(blocks, i) && margins.contains(line));
    block.title = isTitle;
    if (isTitle) {
      titles.add((
        level: _numberingDepth(line),
        title: line.replaceAll(_whitespace, ' '),
        start: block.start,
        end: block.end,
      ));
    }
    previous = block;
  }
  if (titles.length > _minSuspicious && titles.length * 2 > contentBlocks) {
    return const [];
  }
  return titles;
}

/// Cuántas palabras tiene, como mucho, un título reconocido por su forma.
const kIsolatedTitleMaxWords = 15;

/// Cuántos caracteres tiene, como mucho, un título reconocido por su forma.
const kIsolatedTitleMaxChars = 120;

/// Desde cuántos títulos se desconfía de un texto en el que son más de la
/// mitad de los bloques: uno corto —un título y su párrafo, dos o tres
/// veces— puede tenerlos de verdad.
const _minSuspicious = 8;

/// Un bloque del texto: renglones seguidos, sin uno en blanco entre ellos.
class _Block {
  _Block(this.start, this.end, this.lines, {required this.separator});

  /// Su tramo, sin los espacios de las puntas.
  final int start;
  final int end;

  /// Cuántos renglones tiene.
  final int lines;

  /// Si es la raya que separa una página del PDF de la siguiente (`---`).
  final bool separator;

  /// Si quedó como título.
  bool title = false;
}

List<_Block> _blocksOf(String text) {
  final blocks = <_Block>[];
  int? blockStart;
  var blockEnd = 0;
  var lines = 0;
  void close() {
    final start = blockStart;
    if (start == null) return;
    blocks.add(
      _Block(
        start,
        blockEnd,
        lines,
        separator:
            lines == 1 && text.substring(start, blockEnd) == _pageSeparator,
      ),
    );
    blockStart = null;
    lines = 0;
  }

  var lineStart = 0;
  while (lineStart <= text.length) {
    final newline = text.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? text.length : newline;
    var first = lineStart;
    var last = lineEnd;
    while (first < last && _isBlank(text.codeUnitAt(first))) {
      first++;
    }
    while (last > first && _isBlank(text.codeUnitAt(last - 1))) {
      last--;
    }
    if (first == last) {
      close();
    } else {
      blockStart ??= first;
      blockEnd = last;
      lines++;
    }
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  close();
  return blocks;
}

/// El primer bloque con texto después del [index], salteando las rayas de
/// página: lo que sigue a una página es el comienzo de la siguiente.
_Block? _nextContent(List<_Block> blocks, int index) {
  for (var i = index + 1; i < blocks.length; i++) {
    if (!blocks[i].separator) return blocks[i];
  }
  return null;
}

/// Si el bloque [index] es el primero o el último de su página: donde van
/// los encabezados y los pies.
bool _atPageEdge(List<_Block> blocks, int index) =>
    index == 0 ||
    index == blocks.length - 1 ||
    blocks[index - 1].separator ||
    blocks[index + 1].separator;

bool _looksLikeTitle(String line) {
  if (line.length > kIsolatedTitleMaxChars) return false;
  final words = _word.allMatches(line).length;
  if (words == 0 || words > kIsolatedTitleMaxWords) return false;
  if (!_letter.hasMatch(line)) return false;
  if (isPageNumberLine(line) || _bullet.hasMatch(line)) return false;
  if (_timestamp.hasMatch(line)) return false;
  if (!_titleStart.hasMatch(line)) return false;
  return !_openEnding.hasMatch(line);
}

/// Si el bloque [block] termina una oración: lo que deja que lo siguiente
/// sea un título.
bool _endsSentence(String text, _Block block) =>
    _sentenceEnd.hasMatch(text.substring(block.end - 1, block.end));

bool _startsLowercase(int unit) {
  final char = String.fromCharCode(unit);
  return char != char.toUpperCase() && char == char.toLowerCase();
}

/// Cuántos números tiene la numeración con que empieza [line]: «1.2.3 El
/// origen» tiene 3; «El origen», ninguna, y queda en el nivel 1.
int _numberingDepth(String line) {
  final numbering = _numbering.matchAsPrefix(line);
  if (numbering == null) return 1;
  return '.'.allMatches(numbering[1]!).length + 1;
}

bool _isBlank(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0D || unit == 0xA0;

const _pageSeparator = '---';

final _whitespace = RegExp(r'\s+');
final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);

/// Cómo empieza un título: con una mayúscula, un número, los signos que abren
/// una pregunta o una exclamación, o comillas.
final _titleStart = RegExp(r'^(?:\p{Lu}|\p{Lt}|\p{N}|[¿¡«"“‘])', unicode: true);

/// Cómo termina lo que no es un título: una oración, o un renglón cortado.
final _openEnding = RegExp(r'[.,;:…\-‐‑–—]$');

/// Cómo termina un párrafo que cierra una oración.
final _sentenceEnd = RegExp(r'[.!?…»”"’)\]]');

/// Una viñeta: lo que empieza un ítem de una lista y no un título.
final _bullet = RegExp(r'^(?:[-*•·–—▪◦]\s|\(?[a-z]\)\s|\d{1,3}\)\s)');

/// Un renglón de una transcripción: empieza con su marca de tiempo.
final _timestamp = RegExp(r'^\[\d+:\d{2}(?::\d{2})?\]');

/// La numeración de un título: «1», «1.2», «1.2.3», con o sin punto al final,
/// seguida de un espacio y del título.
final _numbering = RegExp(r'(\d{1,3}(?:\.\d{1,3})*)\.?\s+\S');
