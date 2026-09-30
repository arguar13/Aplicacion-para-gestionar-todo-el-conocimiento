/// Dónde está [excerpt] dentro de [text]: `[inicio, fin)` en [text], o
/// `null` si no está (F22).
///
/// Es lo que reubica un subrayado, una tarjeta o un extracto cuando el
/// texto de un elemento se vuelve a extraer: lo que se guardó es el
/// fragmento copiado, y hay que encontrarlo en el texto nuevo. Primero se
/// busca tal cual. Si no aparece, se busca sin mirar cómo están cortados
/// los renglones: los espacios y saltos seguidos cuentan como uno solo, y un
/// guion de corte al final del renglón —común, suave o tipográfico— no
/// cuenta. Es justamente lo que cambia entre una extracción vieja y una
/// nueva de un PDF (antes se unían los renglones y las palabras cortadas;
/// ahora se guardan como en el libro), sin cambiar una letra de lo que dice.
///
/// Si aparece más de una vez, gana la más cercana a [near] —dónde estaba en
/// el texto viejo, llevado a la proporción del nuevo—.
({int start, int end})? locateExcerpt(
  String text,
  String excerpt, {
  int near = 0,
}) {
  if (excerpt.isEmpty) return null;

  final exact = _nearest(_allIndexes(text, excerpt), near);
  if (exact != null) return (start: exact, end: exact + excerpt.length);

  final haystack = _Normalized(text);
  final needle = _Normalized(excerpt).text.trim();
  if (needle.isEmpty) return null;
  final found = _nearest(
    _allIndexes(haystack.text, needle),
    haystack.normalizedIndexOf(near),
  );
  if (found == null) return null;
  return (
    start: haystack.rawStart(found),
    end: haystack.rawEnd(found + needle.length - 1),
  );
}

List<int> _allIndexes(String text, String pattern) {
  final indexes = <int>[];
  var from = 0;
  while (true) {
    final index = text.indexOf(pattern, from);
    if (index < 0) return indexes;
    indexes.add(index);
    from = index + 1;
  }
}

int? _nearest(List<int> indexes, int near) {
  int? best;
  for (final index in indexes) {
    if (best == null || (index - near).abs() < (best - near).abs()) {
      best = index;
    }
  }
  return best;
}

bool _isSpace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;

bool _isHyphen(int unit) => unit == 0x2D || unit == 0xAD || unit == 0x2010;

/// Un texto sin cortes de renglón: cada tramo de espacios o saltos pasa a un
/// solo espacio, y un guion seguido de un salto —el corte de una palabra al
/// final del renglón— desaparece, con su salto. El guion suave, en cualquier
/// lugar. Guarda, para cada carácter que queda, de qué posición del texto
/// original vino.
class _Normalized {
  _Normalized(String raw) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      final unit = raw.codeUnitAt(i);
      if (unit == 0xAD) {
        i++;
        continue;
      }
      if (_isHyphen(unit)) {
        var j = i + 1;
        while (j < raw.length &&
            (raw.codeUnitAt(j) == 0x20 || raw.codeUnitAt(j) == 0x09)) {
          j++;
        }
        if (j < raw.length &&
            (raw.codeUnitAt(j) == 0x0A || raw.codeUnitAt(j) == 0x0D)) {
          while (j < raw.length && _isSpace(raw.codeUnitAt(j))) {
            j++;
          }
          i = j;
          continue;
        }
      }
      if (_isSpace(unit)) {
        final start = i;
        while (i < raw.length && _isSpace(raw.codeUnitAt(i))) {
          i++;
        }
        buffer.write(' ');
        _starts.add(start);
        _ends.add(i);
        continue;
      }
      buffer.writeCharCode(unit);
      _starts.add(i);
      _ends.add(i + 1);
      i++;
    }
    text = buffer.toString();
  }

  late final String text;
  final _starts = <int>[];
  final _ends = <int>[];

  int rawStart(int normalized) => _starts[normalized];

  int rawEnd(int normalized) => _ends[normalized];

  /// La posición del texto normalizado más cercana a la posición [raw] del
  /// original.
  int normalizedIndexOf(int raw) {
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_starts[mid] < raw) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
