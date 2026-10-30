import 'dart:typed_data';

import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Cuántas palabras por minuto dice una voz del teléfono a 1× (F47, paso 2):
/// el ritmo habitual de una voz que narra en español, unas 150. Es una
/// estimación, no una medición —la voz sintetizada no tiene una línea de
/// tiempo que se pueda preguntar—, y alcanza para lo que se usa: el tiempo
/// del reproductor y adónde caen ±10 s.
const phoneVoiceWordsPerMinute = 150.0;

/// La línea de tiempo de lo que lee una voz del teléfono (F47, paso 2): el
/// tiempo transcurrido, el total y adónde salta ±10 s, **estimados por las
/// palabras y la velocidad** —a [phoneVoiceWordsPerMinute] por la velocidad
/// elegida—.
///
/// Las posiciones son caracteres de `spoken` contados desde el comienzo del
/// primer pedazo, como las cuenta el lector: el final de un pedazo es el
/// comienzo del siguiente, y [length] es el final de todo. El tiempo de una
/// posición son las palabras que empiezan antes de ella, así que una palabra
/// empieza a contar apenas se la empieza a decir. Los tiempos están a la
/// velocidad que se pide: el mismo texto a 2× dura la mitad.
///
/// ±10 s **salta a la oración más cercana** a ese tiempo, no a una palabra
/// suelta: retomar a mitad de una oración no se entiende. Una oración empieza
/// al comienzo de cada pedazo —una línea, o una oración de una línea larga,
/// ver `buildReadableSegments`— y después de cada `.`, `!`, `?` o `…`
/// seguido de un espacio.
///
/// Se arma una vez por lista de pedazos —ver [ReadingTimeline.of]—, en un
/// solo recorrido, y guarda solo lo que hace falta para responder sin volver
/// a recorrer: dónde empieza cada pedazo y cada oración y cuántas palabras
/// hay antes de cada uno. Lo de adentro de un pedazo —unos cientos de
/// caracteres a lo sumo— se cuenta cuando se pregunta. No cambia después de
/// armarse.
class ReadingTimeline {
  ReadingTimeline._(
    this._spoken,
    this._segmentStarts,
    this._wordsBefore,
    this._sentenceStarts,
    this._sentenceWords,
  );

  /// La línea de tiempo de [segments]. Es la misma mientras sea la misma
  /// lista: se arma la primera vez que se pide y queda guardada con ella.
  factory ReadingTimeline.of(List<ReadableSegment> segments) =>
      _timelines[segments] ??= ReadingTimeline._build(segments);

  factory ReadingTimeline._build(List<ReadableSegment> segments) {
    final count = segments.length;
    final spoken = [for (final segment in segments) segment.spoken];
    final segmentStarts = Int32List(count + 1);
    final wordsBefore = Int32List(count + 1);
    final sentenceStarts = <int>[];
    final sentenceWords = <int>[];

    var chars = 0;
    var words = 0;
    for (var i = 0; i < count; i++) {
      segmentStarts[i] = chars;
      wordsBefore[i] = words;
      final text = spoken[i];
      // El comienzo del pedazo abre una oración, y también lo que sigue a
      // un punto con su espacio.
      var opensSentence = true;
      var at = 0;
      while (at < text.length) {
        if (_isSpace(text.codeUnitAt(at))) {
          at++;
          continue;
        }
        final start = at;
        var pronounced = false;
        while (at < text.length && !_isSpace(text.codeUnitAt(at))) {
          pronounced = pronounced || _isWordUnit(text.codeUnitAt(at));
          at++;
        }
        if (!pronounced) {
          // Un "—" o un "*" suelto no se dice: no es una palabra ni abre la
          // oración, que empieza en lo que sí se dice.
          if (_endsSentence(text.codeUnitAt(at - 1))) opensSentence = true;
          continue;
        }
        if (opensSentence) {
          sentenceStarts.add(chars + start);
          sentenceWords.add(words);
          opensSentence = false;
        }
        words++;
        if (_endsSentence(text.codeUnitAt(at - 1))) opensSentence = true;
      }
      chars += text.length;
    }
    segmentStarts[count] = chars;
    wordsBefore[count] = words;

    return ReadingTimeline._(
      spoken,
      segmentStarts,
      wordsBefore,
      Int32List.fromList(sentenceStarts),
      Int32List.fromList(sentenceWords),
    );
  }

  final List<String> _spoken;

  /// Dónde empieza cada pedazo, y al final el largo de todo.
  final Int32List _segmentStarts;

  /// Cuántas palabras hay antes de cada pedazo, y al final todas.
  final Int32List _wordsBefore;

  /// Dónde empieza cada oración, en orden.
  final Int32List _sentenceStarts;

  /// Cuántas palabras hay antes de cada oración de [_sentenceStarts].
  final Int32List _sentenceWords;

  /// Cuántos caracteres de `spoken` hay en todo: la posición del final.
  int get length => _segmentStarts.last;

  /// Cuántas palabras se dicen en todo.
  int get words => _wordsBefore.last;

  /// Dónde empieza el pedazo [segment].
  int startOf(int segment) => _segmentStarts[segment];

  /// El pedazo y el carácter de su `spoken` de la posición [position]. El
  /// final de un pedazo es el comienzo del siguiente; el final de todo, el
  /// final del último.
  (int, int) locate(int position) {
    if (_spoken.isEmpty) return (0, 0);
    final segment = _lastAtOrBefore(_segmentStarts, position, _spoken.length);
    return (segment, position - _segmentStarts[segment]);
  }

  /// Cuánto dura todo, a [speed].
  Duration durationAt(double speed) => _timeOf(words, speed);

  /// Cuánto se lleva dicho en [position], a [speed].
  Duration elapsedAt(int position, double speed) =>
      _timeOf(_wordsBeforePosition(position), speed);

  /// La posición de [time] a [speed]: el comienzo de la palabra que se está
  /// diciendo en ese momento. Antes del principio, el principio; pasado el
  /// final, [length].
  int positionAt(Duration time, double speed) {
    if (time <= Duration.zero) return _positionOfWord(0);
    final word = (time.inMicroseconds / _microsPerWord(speed)).floor();
    return _positionOfWord(word);
  }

  /// Adónde lleva saltar [delta] desde [from], a [speed]: el comienzo de la
  /// oración más cercana a ese tiempo, o [length] si cae pasado el final.
  ///
  /// Un salto siempre mueve: si la oración más cercana no queda para el lado
  /// pedido —una oración larga—, va a la de al lado. Para atrás desde
  /// adentro de una oración, la más cercana puede ser el comienzo de esa
  /// misma: es volver a empezarla, como en un audiolibro. Para atrás desde
  /// el principio, el principio.
  int skip(int from, Duration delta, double speed) {
    if (_sentenceStarts.isEmpty) return delta.isNegative ? 0 : length;
    final target = elapsedAt(from, speed) + delta;
    if (target >= durationAt(speed)) return length;

    final words = target.inMicroseconds / _microsPerWord(speed);
    var sentence = _nearestSentence(words);
    if (!delta.isNegative && _sentenceStarts[sentence] <= from) {
      sentence = _countAtOrBefore(_sentenceStarts, from);
      if (sentence >= _sentenceStarts.length) return length;
    } else if (delta.isNegative && _sentenceStarts[sentence] >= from) {
      sentence = _countAtOrBefore(_sentenceStarts, from - 1) - 1;
      if (sentence < 0) return 0;
    }
    return _sentenceStarts[sentence];
  }

  /// La oración que empieza más cerca de haber dicho [words] palabras; entre
  /// dos a la misma distancia, la primera.
  int _nearestSentence(double words) {
    var low = 0;
    var high = _sentenceWords.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_sentenceWords[middle] <= words) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    if (low + 1 < _sentenceWords.length &&
        _sentenceWords[low + 1] - words < words - _sentenceWords[low]) {
      return low + 1;
    }
    return low;
  }

  int _wordsBeforePosition(int position) {
    if (_spoken.isEmpty || position <= 0) return 0;
    if (position >= length) return words;
    final (segment, char) = locate(position);
    final text = _spoken[segment];
    var count = 0;
    var at = 0;
    while (at < char && at < text.length) {
      if (_isSpace(text.codeUnitAt(at))) {
        at++;
        continue;
      }
      final start = at;
      var pronounced = false;
      while (at < text.length && !_isSpace(text.codeUnitAt(at))) {
        pronounced = pronounced || _isWordUnit(text.codeUnitAt(at));
        at++;
      }
      if (pronounced && start < char) count++;
    }
    return _wordsBefore[segment] + count;
  }

  /// Dónde empieza la palabra número [word] —desde 0—; pasada la última,
  /// [length].
  int _positionOfWord(int word) {
    if (word >= words) return length;
    // Un pedazo sin palabras tiene las mismas antes que el que sigue: la
    // palabra está en el último que no tiene más de [word] antes.
    final segment = _lastAtOrBefore(_wordsBefore, word, _spoken.length);
    final text = _spoken[segment];
    var remaining = word - _wordsBefore[segment];
    var at = 0;
    while (at < text.length) {
      if (_isSpace(text.codeUnitAt(at))) {
        at++;
        continue;
      }
      final start = at;
      var pronounced = false;
      while (at < text.length && !_isSpace(text.codeUnitAt(at))) {
        pronounced = pronounced || _isWordUnit(text.codeUnitAt(at));
        at++;
      }
      if (!pronounced) continue;
      if (remaining == 0) return _segmentStarts[segment] + start;
      remaining--;
    }
    return _segmentStarts[segment + 1];
  }

  static double _microsPerWord(double speed) =>
      Duration.microsecondsPerMinute / (phoneVoiceWordsPerMinute * speed);

  static Duration _timeOf(int words, double speed) =>
      Duration(microseconds: (words * _microsPerWord(speed)).round());
}

final _timelines = Expando<ReadingTimeline>('la línea de tiempo de la lista');

/// El último índice de [values] —ordenados, entre los primeros [count]— con
/// un valor que no pasa de [value]; 0 si ninguno.
int _lastAtOrBefore(Int32List values, num value, int count) {
  var low = 0;
  var high = count - 1;
  while (low < high) {
    final middle = (low + high + 1) >> 1;
    if (values[middle] <= value) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low;
}

/// Cuántos valores de [values] —ordenados— no pasan de [value]: el índice
/// del primero que lo pasa.
int _countAtOrBefore(Int32List values, int value) {
  var low = 0;
  var high = values.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (values[middle] <= value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// `spoken` viene con los espacios juntados en uno, pero un documento armado
/// a mano puede traer tabuladores o saltos.
bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// Lo que cierra una oración: `.`, `!`, `?` y `…`.
bool _endsSentence(int unit) =>
    unit == 0x2E || unit == 0x21 || unit == 0x3F || unit == 0x2026;

/// Si [unit] es parte de algo que se dice: una letra o un número. Sin
/// expresiones regulares —se pregunta por cada carácter de un libro
/// entero—: lo ASCII que no es letra ni número, y la puntuación tipográfica
/// de siempre, no se dicen; el resto de lo que no es ASCII son letras.
bool _isWordUnit(int unit) {
  if (unit < 0x80) {
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A);
  }
  return !_typographic.contains(unit);
}

/// La puntuación que no es ASCII y no se dice: guiones largos, comillas,
/// `¿`, `¡`, `…`, `·` y el espacio duro.
const _typographic = {
  0x00A0, 0x00A1, 0x00AB, 0x00B7, 0x00BB, 0x00BF, //
  0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026,
};
