import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Qué es un bloque de una respuesta del chat (F42).
enum ChatBlockKind { paragraph, heading, listItem, quote, code, rule, table }

/// Un tramo `[start, end)` del texto de la respuesta.
typedef ChatTextRange = ({int start, int end});

/// Un bloque de una respuesta del chat, con sus posiciones en el texto tal
/// cual lo escribió el modelo (F42): un párrafo, un título, un renglón de
/// una lista, de una cita, un bloque de código, un separador o una tabla.
///
/// Las posiciones son las del texto crudo, las mismas que usa el lector en
/// voz alta para pintar lo que suena (F25): así el amarillo y el fundido de
/// las palabras que llegan caen en su lugar aunque la pantalla no muestre los
/// `#`, los `-` ni las cercas del código.
@immutable
class ChatBlock {
  const ChatBlock({
    required this.kind,
    required this.start,
    required this.end,
    required this.content,
    this.level = 0,
    this.depth = 0,
    this.ordinal,
    this.language,
    this.rows = const [],
  });

  final ChatBlockKind kind;

  /// El bloque entero, de su primer renglón al último, sin el salto final.
  final int start;
  final int end;

  /// Lo que se ve con formato: el texto de un título sin sus `#`, el de un
  /// renglón de lista sin su viñeta, el código sin sus cercas. Vacío en un
  /// separador y en una tabla —la tabla tiene sus celdas en [rows]—.
  final ChatTextRange content;

  /// El nivel de un título: 1 a 6.
  final int level;

  /// Cuánto está metido un renglón de lista: 0 el de afuera.
  final int depth;

  /// El número de un renglón de una lista numerada, tal cual («3.» o «3)»);
  /// `null` en una lista con viñetas.
  final String? ordinal;

  /// El lenguaje que dice la cerca de un bloque de código («dart»), si dice.
  final String? language;

  /// Las filas de una tabla, la primera es la de los títulos.
  final List<List<ChatTextRange>> rows;

  @override
  bool operator ==(Object other) =>
      other is ChatBlock &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.content == content &&
      other.level == level &&
      other.depth == depth &&
      other.ordinal == ordinal &&
      other.language == language &&
      other.rows.length == rows.length &&
      [for (var i = 0; i < rows.length; i++) listEquals(other.rows[i], rows[i])]
          .every((same) => same);

  @override
  int get hashCode =>
      Object.hash(kind, start, end, content, level, depth, ordinal, language);

  @override
  String toString() =>
      'ChatBlock($kind, $start–$end, contenido ${content.start}–'
      '${content.end})';
}

/// Parte [raw] —una respuesta del modelo, en Markdown— en bloques (F42).
///
/// No es CommonMark entero: es lo que escriben los modelos al contestar
/// —títulos, párrafos con saltos de renglón, listas con viñetas o números y
/// anidadas, citas, código entre cercas, separadores y tablas simples—. Lo de
/// adentro de cada bloque (negritas, cursivas, código en línea) lo lee
/// `RenderedMarkdown`, el mismo de toda la app.
List<ChatBlock> parseChatBlocks(String raw) => _parseFrom(raw, 0);

/// [parseChatBlocks] de a pedazos, para una respuesta que se está escribiendo
/// (F42): cada evento del modelo es todo el texto hasta ahí —ver
/// `ChatReplyStream`—, y volver a leerlo entero con cada palabra haría que una
/// respuesta larga cueste lo que su largo al cuadrado.
///
/// Un bloque con otros dos después no cambia más: lo que sigue no puede
/// volverlo otra cosa. Esos quedan como
/// están —los mismos objetos, para que la pantalla no los vuelva a armar— y
/// se lee de nuevo solo desde el comienzo del anteúltimo: el último puede
/// crecer, y el renglón que todavía se escribe puede cambiar de qué es el
/// anterior (un `|---|` que convierte en tabla el renglón de arriba).
class ChatBlockStream {
  String _raw = '';
  final _settled = <ChatBlock>[];
  var _pending = const <ChatBlock>[];

  /// Desde dónde se vuelve a leer: el comienzo del primer bloque que todavía
  /// puede cambiar, siempre al principio de un renglón.
  var _resume = 0;

  List<ChatBlock> get blocks => [..._settled, ..._pending];

  /// Los bloques que ya no cambian, en orden.
  int get settledCount => _settled.length;

  /// Lee [raw], el texto entero hasta ahora.
  ///
  /// Confía en el contrato del modelo —cada texto empieza con el anterior— y
  /// lo mira solo en el borde: si [raw] es más corto que lo ya asentado, o no
  /// coincide justo antes de donde se retoma, se lee todo de nuevo. La
  /// respuesta guardada al terminar se lee entera de todos modos.
  List<ChatBlock> update(String raw) {
    // [_resume] es siempre un comienzo de renglón: justo antes hay un salto.
    final continues =
        raw.length >= _raw.length &&
        (_resume == 0 || raw.codeUnitAt(_resume - 1) == 0x0A);
    if (!continues) {
      _settled.clear();
      _resume = 0;
    }
    _raw = raw;

    final fresh = _parseFrom(raw, _resume);
    // El último y el anteúltimo nunca se asientan; los de antes, sí. El
    // renglón que se escribe, si dice algo, es parte del último —un renglón
    // en blanco no es de nadie—, así que lo que queda antes del anteúltimo
    // ya terminó en un renglón entero.
    final settle = math.max(0, fresh.length - 2);
    _settled.addAll(fresh.take(settle));
    _pending = fresh.sublist(settle);
    if (_pending.isNotEmpty) _resume = _pending.first.start;
    return blocks;
  }
}

// --- La lectura -------------------------------------------------------------

final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([^`\s]*)');
final _heading = RegExp(r'^ {0,3}(#{1,6})[ \t]+');
final _headingEmpty = RegExp(r'^ {0,3}(#{1,6})$');
final _rule = RegExp(
  r'^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$',
);
final _listItem = RegExp(r'^([ \t]*)([-*+]|\d{1,9}[.)])[ \t]+');
final _quote = RegExp(r'^ {0,3}>[ \t]?');
final _tableSeparator = RegExp(
  r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$',
);

/// Un renglón del texto: dónde empieza y dónde termina, sin el salto.
typedef _Line = ({int start, int end});

List<ChatBlock> _parseFrom(String raw, int from) {
  final lines = <_Line>[];
  var cursor = from;
  while (cursor <= raw.length) {
    final newline = raw.indexOf('\n', cursor);
    final end = newline == -1 ? raw.length : newline;
    // Un `\r` de Windows no es parte del renglón.
    final trimmed = end > cursor && raw.codeUnitAt(end - 1) == 0x0D
        ? end - 1
        : end;
    lines.add((start: cursor, end: trimmed));
    if (newline == -1) break;
    cursor = newline + 1;
  }

  String text(_Line line) => raw.substring(line.start, line.end);
  bool blank(_Line line) => text(line).trim().isEmpty;

  final blocks = <ChatBlock>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final body = text(line);
    if (body.trim().isEmpty) {
      i++;
      continue;
    }

    // Código entre cercas: hasta la cerca que lo cierra, o hasta el final
    // mientras se escribe.
    final fence = _fence.firstMatch(body);
    if (fence != null) {
      final mark = fence.group(1)!;
      final language = fence.group(2)!;
      var j = i + 1;
      while (j < lines.length) {
        final candidate = text(lines[j]).trimLeft();
        if (candidate.startsWith(mark[0] * mark.length) &&
            candidate.replaceAll(mark[0], '').trim().isEmpty) {
          break;
        }
        j++;
      }
      final closed = j < lines.length;
      final bodyStart = i + 1 < lines.length ? lines[i + 1].start : line.end;
      final bodyEnd = j - 1 > i ? lines[j - 1].end : bodyStart;
      blocks.add(
        ChatBlock(
          kind: ChatBlockKind.code,
          start: line.start,
          end: closed ? lines[j].end : lines.last.end,
          content: (
            start: bodyStart,
            end: bodyEnd < bodyStart ? bodyStart : bodyEnd,
          ),
          language: language.isEmpty ? null : language,
        ),
      );
      i = closed ? j + 1 : lines.length;
      continue;
    }

    if (_rule.hasMatch(body)) {
      blocks.add(
        ChatBlock(
          kind: ChatBlockKind.rule,
          start: line.start,
          end: line.end,
          content: (start: line.end, end: line.end),
        ),
      );
      i++;
      continue;
    }

    final heading = _heading.firstMatch(body) ?? _headingEmpty.firstMatch(body);
    if (heading != null) {
      final contentStart = line.start + heading.end;
      blocks.add(
        ChatBlock(
          kind: ChatBlockKind.heading,
          start: line.start,
          end: line.end,
          content: (
            start: contentStart,
            end: _trimEnd(raw, contentStart, line.end),
          ),
          level: heading.group(1)!.length,
        ),
      );
      i++;
      continue;
    }

    // Una tabla: un renglón con `|` y, debajo, el separador `|---|---|`.
    if (body.contains('|') &&
        i + 1 < lines.length &&
        _tableSeparator.hasMatch(text(lines[i + 1]))) {
      final rows = [_cells(raw, line)];
      var j = i + 2;
      while (j < lines.length &&
          !blank(lines[j]) &&
          text(lines[j]).contains('|')) {
        rows.add(_cells(raw, lines[j]));
        j++;
      }
      blocks.add(
        ChatBlock(
          kind: ChatBlockKind.table,
          start: line.start,
          end: lines[j - 1].end,
          content: (start: line.start, end: line.start),
          rows: rows,
        ),
      );
      i = j;
      continue;
    }

    final item = _listItem.firstMatch(body);
    if (item != null) {
      final indent = item.group(1)!.replaceAll('\t', '    ').length;
      final marker = item.group(2)!;
      final contentStart = line.start + item.end;
      // Lo que sigue más metido y sin viñeta es parte del mismo renglón: el
      // modelo partió el texto del ítem en dos.
      var j = i + 1;
      while (j < lines.length &&
          !blank(lines[j]) &&
          _continuesItem(text(lines[j]), indent)) {
        j++;
      }
      blocks.add(
        ChatBlock(
          kind: ChatBlockKind.listItem,
          start: line.start,
          end: lines[j - 1].end,
          content: (
            start: contentStart,
            end: _trimEnd(raw, contentStart, lines[j - 1].end),
          ),
          depth: (indent / 2).floor().clamp(0, 3),
          ordinal: RegExp(r'^\d').hasMatch(marker) ? marker : null,
        ),
      );
      i = j;
      continue;
    }

    final quote = _quote.firstMatch(body);
    if (quote != null) {
      final contentStart = line.start + quote.end;
      blocks.add(
        ChatBlock(
          kind: ChatBlockKind.quote,
          start: line.start,
          end: line.end,
          content: (
            start: contentStart,
            end: _trimEnd(raw, contentStart, line.end),
          ),
        ),
      );
      i++;
      continue;
    }

    // Un párrafo: los renglones seguidos que no son otra cosa. Un salto de
    // renglón adentro se respeta —el modelo lo puso a propósito—.
    var j = i + 1;
    while (j < lines.length &&
        !blank(lines[j]) &&
        !_startsBlock(raw, lines, j)) {
      j++;
    }
    final start = line.start + body.length - body.trimLeft().length;
    blocks.add(
      ChatBlock(
        kind: ChatBlockKind.paragraph,
        start: line.start,
        end: lines[j - 1].end,
        content: (start: start, end: _trimEnd(raw, start, lines[j - 1].end)),
      ),
    );
    i = j;
  }
  return blocks;
}

/// Si el renglón [index] empieza un bloque nuevo en vez de seguir el párrafo
/// de arriba.
bool _startsBlock(String raw, List<_Line> lines, int index) {
  final body = raw.substring(lines[index].start, lines[index].end);
  return _fence.hasMatch(body) ||
      _rule.hasMatch(body) ||
      _heading.hasMatch(body) ||
      _listItem.hasMatch(body) ||
      _quote.hasMatch(body) ||
      (body.contains('|') &&
          index + 1 < lines.length &&
          _tableSeparator.hasMatch(
            raw.substring(lines[index + 1].start, lines[index + 1].end),
          ));
}

/// Si [body] sigue al renglón de lista con sangría [indent]: más metido, y
/// sin ser otro renglón de lista ni otro bloque.
bool _continuesItem(String body, int indent) {
  final lead = body.length - body.trimLeft().length;
  return lead > indent &&
      !_listItem.hasMatch(body) &&
      !_fence.hasMatch(body) &&
      !_heading.hasMatch(body) &&
      !_quote.hasMatch(body);
}

/// Las celdas de un renglón de tabla, sin los `|` ni los espacios de los
/// costados.
List<ChatTextRange> _cells(String raw, _Line line) {
  final cells = <ChatTextRange>[];
  var start = line.start;
  var end = line.end;
  // Los `|` de las puntas no abren ni cierran ninguna celda.
  while (start < end && raw.codeUnitAt(start) == 0x20) {
    start++;
  }
  if (start < end && raw.codeUnitAt(start) == 0x7C) start++;
  end = _trimEnd(raw, start, end);
  if (end > start && raw.codeUnitAt(end - 1) == 0x7C) end--;

  var cellStart = start;
  for (var k = start; k <= end; k++) {
    if (k == end || raw.codeUnitAt(k) == 0x7C) {
      var a = cellStart;
      while (a < k && raw.codeUnitAt(a) == 0x20) {
        a++;
      }
      cells.add((start: a, end: _trimEnd(raw, a, k)));
      cellStart = k + 1;
    }
  }
  return cells;
}

/// [end] sin los espacios del final, sin pasar de [start].
int _trimEnd(String raw, int start, int end) {
  var e = end;
  while (e > start) {
    final c = raw.codeUnitAt(e - 1);
    if (c != 0x20 && c != 0x09 && c != 0x0D) break;
    e--;
  }
  return e;
}
