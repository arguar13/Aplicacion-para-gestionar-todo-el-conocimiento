import 'dart:convert';

/// Lee con tolerancia el JSON que contestó un modelo (F43, punto 6 del plan):
/// los modelos chicos —y a veces los grandes— lo envuelven en un bloque de
/// código, le ponen una frase antes («¡Claro! Acá va:») o después, o dejan una
/// coma de más antes de cerrar.
///
/// En orden:
///
/// 1. si hay un bloque de código (```` ``` ````, con o sin `json`), lo de
///    adentro del primero que se lea;
/// 2. si no, desde cada `{` o `[` —en orden, hasta que uno sirva—, lo que va
///    hasta el corchete o la llave que lo cierra, sin contar los que están
///    dentro de un texto entre comillas: el objeto o la lista **más de
///    afuera**. Así un «[1]» de una cita en la frase de antes no confunde;
/// 3. sin comas colgantes antes de `}` o `]` (fuera de los textos).
///
/// Lanza [FormatException] con un motivo corto —que se le devuelve al modelo
/// al pedirle que lo corrija— si no hay ningún JSON que leer, o si se cortó
/// antes de cerrarse (la respuesta llegó a su tope).
Object? extractJsonValue(String reply) {
  final text = reply.trim();
  if (text.isEmpty) throw const FormatException('La respuesta vino vacía.');

  for (final fenced in _fencedBlocks(text)) {
    final value = _tryDecode(fenced);
    if (value case (final Object? decoded,)) return decoded;
  }

  // Cada candidato desde un `{` o un `[`, hasta su cierre; lo que va dentro
  // de uno que se leyó no se vuelve a probar, y gana el más largo —el más de
  // afuera—: un «[1]» de una cita en la frase de antes pierde contra el JSON.
  (Object?,)? best;
  var bestLength = 0;
  // Dónde empieza uno que se cortó antes de cerrarse; `null` si ninguno.
  int? truncatedAt;
  var tries = 0;
  for (var i = 0; i < text.length && tries < 32; i++) {
    final c = text.codeUnitAt(i);
    if (c != _openBrace && c != _openBracket) continue;
    tries++;
    final end = _closingOf(text, i);
    if (end == null) {
      // Sin cierre: si parece el JSON —una llave, o un corchete que abre
      // algo—, se cortó, y lo que sigue es parte de él, no otro candidato.
      if (_looksLikeJson(text, i)) {
        truncatedAt = i;
        break;
      }
      continue;
    }
    final value = _tryDecode(text.substring(i, end + 1));
    if (value != null) {
      if (end + 1 - i > bestLength) {
        best = value;
        bestLength = end + 1 - i;
      }
      i = end;
    }
  }
  // Uno cortado más largo que lo que se leyó era el JSON de verdad: se dice
  // que se cortó, para pedir que lo complete, en vez de dar un pedazo.
  if (truncatedAt != null && text.length - truncatedAt > bestLength) {
    throw const FormatException('El JSON se cortó antes de cerrarse.');
  }
  if (best != null) return best.$1;
  throw const FormatException('No hay ningún JSON que leer en la respuesta.');
}

/// Si lo que abre en [start] parece el principio de un JSON: una llave, o un
/// corchete seguido de algo que abre un valor.
bool _looksLikeJson(String text, int start) {
  if (text.codeUnitAt(start) == _openBrace) return true;
  var j = start + 1;
  while (j < text.length && _isSpace(text.codeUnitAt(j))) {
    j++;
  }
  if (j >= text.length) return true;
  final next = text.codeUnitAt(j);
  return next == _openBrace || next == _openBracket || next == _quote;
}

const _openBrace = 0x7B; // {
const _closeBrace = 0x7D; // }
const _openBracket = 0x5B; // [
const _closeBracket = 0x5D; // ]
const _quote = 0x22; // "
const _backslash = 0x5C; // \

/// Lo de adentro de cada bloque de código de [text], en orden.
Iterable<String> _fencedBlocks(String text) sync* {
  var from = 0;
  while (true) {
    final open = text.indexOf('```', from);
    if (open < 0) return;
    final lineEnd = text.indexOf('\n', open);
    if (lineEnd < 0) return;
    final close = text.indexOf('```', lineEnd);
    if (close < 0) {
      // Sin cerrar: lo que sigue, por si es el JSON entero.
      yield text.substring(lineEnd + 1);
      return;
    }
    yield text.substring(lineEnd + 1, close);
    from = close + 3;
  }
}

/// Dónde se cierra lo que abre [text] en [start]; `null` si no se cierra.
int? _closingOf(String text, int start) {
  final stack = <int>[];
  var inString = false;
  for (var i = start; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (c == _backslash) {
        i++;
      } else if (c == _quote) {
        inString = false;
      }
      continue;
    }
    if (c == _quote) {
      inString = true;
    } else if (c == _openBrace || c == _openBracket) {
      stack.add(c);
    } else if (c == _closeBrace || c == _closeBracket) {
      if (stack.isEmpty) return null;
      final open = stack.removeLast();
      final matches =
          (open == _openBrace && c == _closeBrace) ||
          (open == _openBracket && c == _closeBracket);
      if (!matches) return null;
      if (stack.isEmpty) return i;
    }
  }
  return null;
}

/// El valor de [candidate] como un registro de un elemento —así un JSON
/// `null` se distingue de «no se pudo»—, o `null` si no se puede leer ni sin
/// sus comas colgantes.
(Object?,)? _tryDecode(String candidate) {
  final trimmed = candidate.trim();
  if (trimmed.isEmpty) return null;
  for (final attempt in [trimmed, withoutTrailingCommas(trimmed)]) {
    try {
      return (jsonDecode(attempt),);
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// [json] sin las comas que quedan colgando antes de `}` o `]`, fuera de los
/// textos entre comillas: `{"a": 1,}` → `{"a": 1}`.
String withoutTrailingCommas(String json) {
  final out = StringBuffer();
  var inString = false;
  for (var i = 0; i < json.length; i++) {
    final c = json.codeUnitAt(i);
    if (inString) {
      out.writeCharCode(c);
      if (c == _backslash && i + 1 < json.length) {
        out.writeCharCode(json.codeUnitAt(++i));
      } else if (c == _quote) {
        inString = false;
      }
      continue;
    }
    if (c == _quote) inString = true;
    if (c == 0x2C) {
      // Una coma: se saltea si lo próximo que no es espacio cierra algo.
      var j = i + 1;
      while (j < json.length && _isSpace(json.codeUnitAt(j))) {
        j++;
      }
      if (j < json.length &&
          (json.codeUnitAt(j) == _closeBrace ||
              json.codeUnitAt(j) == _closeBracket)) {
        continue;
      }
    }
    out.writeCharCode(c);
  }
  return out.toString();
}

bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;
