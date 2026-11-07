/// **Dónde empieza la prosa** de un texto en Markdown (F46, paso 5j, decisión
/// 5b del dueño): después de la ficha con que abre un artículo de Wikipedia.
///
/// En la Bandeja, la tarjeta de «República romana» empezaba «República romana
/// / Res Publica Romana / Estado de la antigüedad / 509-27 a. C. / Escudo»: las
/// filas del recuadro de la derecha y el texto del escudo, no el primer
/// párrafo. La página guarda la ficha como la ve —es parte del artículo, y el
/// texto guardado no se toca—, pero la vista previa es para saber de qué se
/// trata, y eso lo dice el primer párrafo.
///
/// **Cómo se la reconoce en el texto guardado.** Al pasar la página a
/// Markdown, la ficha —una tabla con celdas de varios renglones— se aplana:
/// queda un bloque por celda, sin ninguna marca. Lo que la distingue, medido
/// en las páginas reales (Platón, Imperio romano, Sócrates, Tomás de Aquino,
/// Revolución francesa, Primer concilio de Nicea…), es su forma: una seguidilla
/// de **renglones cortos que no son oraciones** —«Nacimiento», «427 a. C.»,
/// «Causa de muerte», «Muerte natural»—, y recién después el primer párrafo,
/// largo y terminado en un punto, seguido de otro igual o de un título.
///
/// - **Una oración** ([_isProse]): un bloque de al menos [kLeadMinWords]
///   palabras como se leen ([markdownPlainBlocks], sin enlaces ni llamadas a
///   notas) que termina en «.», «!», «?» o «…» —aunque los sigan comillas o
///   un paréntesis—. Un renglón de la ficha no lo es: es corto o no termina
///   en un punto («Busto de Platón … (Museo Fitzwilliam)»).
/// - **El primer párrafo** es la primera oración que no sigue con un renglón
///   de esos: el pie de la foto de la ficha («Retrato más antiguo conocido de
///   san Agustín. Fresco del siglo VI…») es una oración, pero lo sigue la
///   ficha. Lo que no se lee —una foto sin texto, una raya— no cuenta.
/// - **Hay ficha** si antes del primer párrafo hay al menos [kLeadMinRows]
///   renglones de esos. Si no, el texto empieza donde empieza: un artículo
///   que abre con una línea corta («Por Ana Pérez») o con fotos y sus pies
///   queda igual. Las listas, las tablas de Markdown y los títulos no cuentan
///   como renglones de ficha: son contenido.
///
/// Solo se mira el principio —los primeros [kLeadScanBlocks] bloques, en las
/// primeras [kLeadScanChars] letras—: la ficha más larga medida (Imperio
/// romano) tiene unos ochenta bloques y termina antes de la letra 7.300; un
/// libro no se recorre entero. Si ahí no aparece el primer párrafo, el texto
/// empieza donde empieza.
library;

import 'package:sinapsis/core/util/markdown_plain_text.dart';

/// Cuántas palabras tiene que tener, como mínimo, un bloque para ser una
/// oración de un párrafo y no un renglón de la ficha. El valor más largo de
/// una ficha que termina en un punto, medido, tiene diez («Padre de la Iglesia
/// Occidental; "Doctor de la Gracia".», en la de san Agustín).
const kLeadMinWords = 12;

/// Cuántos renglones cortos tiene que haber antes del primer párrafo para que
/// sean una ficha: con menos —una firma, una fecha— el texto queda igual.
const kLeadMinRows = 3;

/// Hasta cuántos bloques del principio se miran.
const kLeadScanBlocks = 150;

/// Hasta cuántas letras del principio se miran.
const kLeadScanChars = 30000;

/// Dónde empieza el primer párrafo de [markdown], pasada la ficha del
/// principio; `0` si no tiene ficha. Ver la explicación de la biblioteca.
int markdownLeadStart(String markdown) {
  final head = markdown.length > kLeadScanChars
      ? markdown.substring(0, kLeadScanChars)
      : markdown;
  var rows = 0;
  final blocks = _blocks(head).take(kLeadScanBlocks).toList();
  for (var i = 0; i < blocks.length; i++) {
    final kind = blocks[i].kind;
    if (kind == _Kind.row) {
      rows++;
      continue;
    }
    if (kind != _Kind.prose) continue;
    final next = blocks
        .skip(i + 1)
        .map((block) => block.kind)
        .firstWhere((kind) => kind != _Kind.none, orElse: () => _Kind.none);
    if (next == _Kind.row) continue;
    return rows >= kLeadMinRows ? blocks[i].start : 0;
  }
  return 0;
}

/// Qué es un bloque para encontrar el primer párrafo.
enum _Kind {
  /// Una oración de un párrafo: ver [_isProse].
  prose,

  /// Un renglón corto o que no termina en un punto: una fila de la ficha.
  row,

  /// Un título, una lista o una tabla: contenido, no ficha.
  other,

  /// Nada que leer: una foto sin texto, una raya.
  none,
}

/// Los bloques de [markdown] —lo que va entre dos renglones en blanco—, de a
/// uno y recién cuando se piden.
Iterable<({int start, _Kind kind})> _blocks(String markdown) sync* {
  var lineStart = 0;
  int? blockStart;
  while (lineStart <= markdown.length) {
    var lineEnd = markdown.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = markdown.length;
    final blank = markdown.substring(lineStart, lineEnd).trim().isEmpty;
    if (!blank) {
      blockStart ??= lineStart;
    } else if (blockStart != null) {
      yield (
        start: blockStart,
        kind: _kindOf(markdown.substring(blockStart, lineStart)),
      );
      blockStart = null;
    }
    if (lineEnd == markdown.length) break;
    lineStart = lineEnd + 1;
  }
  if (blockStart != null) {
    yield (start: blockStart, kind: _kindOf(markdown.substring(blockStart)));
  }
}

_Kind _kindOf(String block) {
  final read = markdownPlainBlocks(block).join(' ').trim();
  if (read.isEmpty) return _Kind.none;
  final first = block.trimLeft();
  if (_heading.hasMatch(first) ||
      first.startsWith('|') ||
      _listItem.hasMatch(first)) {
    return _Kind.other;
  }
  return _isProse(read) ? _Kind.prose : _Kind.row;
}

/// Si [read] —un bloque como se lee— es una oración de un párrafo.
bool _isProse(String read) =>
    read.split(_spaces).length >= kLeadMinWords && _sentenceEnd.hasMatch(read);

// Las marcas de bloque de Markdown, como las lee `markdownPlainBlocks`.
final _heading = RegExp(r'^#{1,6}[ \t]+');
final _listItem = RegExp(r'^(?:[-*+]|\d{1,9}[.)])[ \t]+');
final _spaces = RegExp(r'\s+');
final _sentenceEnd = RegExp('[.!?…][)\\]»"\'”’]*\$');
