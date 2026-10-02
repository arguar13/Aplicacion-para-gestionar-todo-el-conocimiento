import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';

/// Un pedazo del texto —una palabra, o un renglón entero— y el momento del
/// audio en que empieza a decirse.
@immutable
class SyncSpan {
  const SyncSpan(this.start, this.end, this.startMs);

  /// `[start, end)` en el texto tal cual se guarda.
  final int start;
  final int end;
  final int startMs;

  @override
  bool operator ==(Object other) =>
      other is SyncSpan &&
      other.start == start &&
      other.end == end &&
      other.startMs == startMs;

  @override
  int get hashCode => Object.hash(start, end, startMs);

  @override
  String toString() => 'SyncSpan($start, $end, $startMs)';
}

/// Qué parte de una transcripción se está diciendo en cada momento del
/// audio (F23): lo que resalta en amarillo la palabra que suena, y lo que
/// lleva el audio a la palabra que se toca.
///
/// Con los tiempos medidos de cada palabra, palabra por palabra: cada una
/// se busca en el texto **por sí misma** —sin mirar mayúsculas ni
/// puntuación—, saltando las marcas "[3:15]" de cada renglón; así siguen
/// sirviendo después de "Quitar marcas de tiempo" o de corregir alguna
/// palabra a mano, que no encuentra pareja y queda sin resaltar. Sin
/// tiempos —una transcripción de antes de F23—, renglón por renglón, con su
/// marca: es lo que se sabe con certeza, y no se inventa más.
class TranscriptSync {
  TranscriptSync._(this.spans, {required this.isWordLevel});

  factory TranscriptSync.build(String content, List<TimedWord> timings) {
    final words = timings.where((w) => w.startMs != null).toList();
    if (words.isNotEmpty) {
      final spans = _alignWords(content, words);
      if (spans.isNotEmpty) {
        return TranscriptSync._(spans, isWordLevel: true);
      }
    }
    return TranscriptSync._(_lines(content), isWordLevel: false);
  }

  /// En orden de texto y de tiempo.
  final List<SyncSpan> spans;

  /// Palabra por palabra (con tiempos medidos), o renglón por renglón.
  final bool isWordLevel;

  bool get isEmpty => spans.isEmpty;

  /// Lo que se está diciendo en [position]: el último pedazo que ya empezó.
  /// `null` antes del primero.
  SyncSpan? at(Duration position) {
    final ms = position.inMilliseconds;
    var low = 0;
    var high = spans.length - 1;
    SyncSpan? found;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (spans[mid].startMs <= ms) {
        found = spans[mid];
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  /// El pedazo en la posición [offset] del texto —lo que se tocó—, o el
  /// siguiente si se tocó entre palabras. `null` después del último.
  SyncSpan? atOffset(int offset) {
    for (final span in spans) {
      if (offset < span.end) return span;
    }
    return null;
  }

  static final _word = RegExp(r'\S+');
  static final _label = RegExp(r'^\[(?:\d+:)?\d{1,2}:\d{2}\]$');
  static final _lineLabel = RegExp(r'^\[((?:\d+:)?\d{1,2}:\d{2})\] ?');
  static final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

  static String _normalized(String word) =>
      word.toLowerCase().replaceAll(_notLetterOrDigit, '');

  /// Cuántas palabras hacia adelante se busca la pareja de una que no
  /// coincide —una corregida a mano, una agregada—, antes de dejarla sin
  /// tiempo.
  static const _lookahead = 8;

  static List<SyncSpan> _alignWords(String content, List<TimedWord> words) {
    final tokens = [
      for (final m in _word.allMatches(content))
        if (!_label.hasMatch(m[0]!)) (m.start, m.end, _normalized(m[0]!)),
    ];
    final timed = [for (final w in words) _normalized(w.text)];
    final spans = <SyncSpan>[];
    var i = 0;
    var j = 0;
    var lastMs = 0;
    while (i < tokens.length && j < words.length) {
      if (tokens[i].$3 == timed[j]) {
        // Los momentos van siempre hacia adelante: el texto se lee en orden.
        lastMs = words[j].startMs! < lastMs ? lastMs : words[j].startMs!;
        spans.add(SyncSpan(tokens[i].$1, tokens[i].$2, lastMs));
        i++;
        j++;
        continue;
      }
      // Sin pareja: ¿la palabra del texto aparece un poco más adelante en
      // los tiempos (alguien borró una), o al revés (alguien agregó una)?
      final skipTimed = _find(timed, j + 1, tokens[i].$3);
      final skipText = _find([for (final t in tokens) t.$3], i + 1, timed[j]);
      if (skipTimed != null &&
          (skipText == null || skipTimed - j <= skipText - i)) {
        j = skipTimed;
      } else if (skipText != null) {
        i = skipText;
      } else {
        i++;
        j++;
      }
    }
    return spans;
  }

  static int? _find(List<String> list, int from, String value) {
    final end = (from + _lookahead).clamp(0, list.length);
    for (var k = from; k < end; k++) {
      if (list[k] == value) return k;
    }
    return null;
  }

  static List<SyncSpan> _lines(String content) {
    final spans = <SyncSpan>[];
    var lineStart = 0;
    while (lineStart <= content.length) {
      var lineEnd = content.indexOf('\n', lineStart);
      if (lineEnd == -1) lineEnd = content.length;
      final line = content.substring(lineStart, lineEnd);
      final label = _lineLabel.firstMatch(line);
      if (label != null && lineEnd > lineStart + label.end) {
        spans.add(
          SyncSpan(lineStart + label.end, lineEnd, _parseMs(label[1]!)),
        );
      }
      lineStart = lineEnd + 1;
    }
    return spans;
  }

  static int _parseMs(String label) {
    final parts = label.split(':').map(int.parse).toList();
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part;
    }
    return seconds * 1000;
  }
}
