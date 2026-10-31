/// Dónde está, en el texto de una fuente, el pasaje que la IA copió de él: el
/// de una idea del mapa mental (F43) o el de una cita del podcast (F47). Es lo
/// que hace que «Ver en el documento» abra la lectura parada ahí, con el tramo
/// marcado, y lo que comprueba que una cita del podcast está de verdad en el
/// material.
library;

/// Un tramo de un texto: de `start` a `end`, sin incluir `end`.
typedef PassageRange = ({int start, int end});

/// El tramo de [text] donde aparece [quote], o `null` si no aparece.
///
/// La IA copia «tal cual», pero no siempre: cambia una mayúscula, se come una
/// tilde o una coma, junta dos espacios. Por eso se compara sin mayúsculas,
/// sin tildes y sin signos —solo letras y números, con los espacios de a
/// uno—. Si el pasaje entero no aparece, se busca su comienzo, cada vez más
/// corto, hasta cuatro palabras: con eso alcanza para llegar al lugar. Gana
/// la primera aparición.
PassageRange? findPassage(String text, String quote) {
  final needle = _Folded.of(quote);
  final words = needle.text.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || text.isEmpty) return null;
  final haystack = _Folded.of(text);

  final sizes = <int>{words.length};
  for (final size in const [10, 8, 6, 5, 4]) {
    if (size < words.length) sizes.add(size);
  }
  for (final size in sizes) {
    final probe = words.take(size).join(' ');
    // Cuatro palabras cortas («de la que se») están en cualquier lado: el
    // comienzo solo sirve si dice algo.
    if (size < words.length && probe.length < 16) continue;
    final at = _findWhole(haystack.text, probe);
    if (at < 0) continue;
    final end = at + probe.length;
    return (start: haystack.origin[at], end: haystack.origin[end - 1] + 1);
  }
  return null;
}

/// Un texto preparado para comprobar muchas citas contra él (F47): se lleva a
/// lo que se compara una sola vez, no una por cita.
///
/// A diferencia de [findPassage], que se conforma con el comienzo para llegar
/// al lugar, [containsWhole] pide la cita **entera**: una cita que empieza con
/// palabras del texto y sigue con otras que no están no es una cita del texto.
class PassageIndex {
  PassageIndex(String text) : _haystack = _Folded.of(text).text;

  final String _haystack;

  /// Si [quote] está entera en el texto, comparada como [findPassage] —sin
  /// mayúsculas, sin tildes y sin signos—. Una elipsis («…» o «...») marca lo
  /// que la IA salteó: cada pedazo tiene que estar, en el orden en que va.
  bool containsWhole(String quote) {
    final pieces = [
      for (final piece in quote.split(_ellipsis))
        if (_Folded.of(piece).text case final folded when folded.isNotEmpty)
          folded,
    ];
    if (pieces.isEmpty || _haystack.isEmpty) return false;
    var from = 0;
    for (final piece in pieces) {
      final at = _findWhole(_haystack, piece, from: from);
      if (at < 0) return false;
      from = at + piece.length;
    }
    return true;
  }

  static final _ellipsis = RegExp(r'…|\.\.\.+');
}

/// La primera vez que [probe] está en [text], desde [from], empezando y
/// terminando en un borde de palabra.
int _findWhole(String text, String probe, {int from = 0}) {
  var start = from;
  while (true) {
    final at = text.indexOf(probe, start);
    if (at < 0) return -1;
    final end = at + probe.length;
    final startsWord = at == 0 || text.codeUnitAt(at - 1) == 0x20;
    final endsWord = end == text.length || text.codeUnitAt(end) == 0x20;
    if (startsWord && endsWord) return at;
    start = at + 1;
  }
}

/// Un texto llevado a lo que se compara, con de dónde salió cada letra.
class _Folded {
  _Folded(this.text, this.origin);

  factory _Folded.of(String source) {
    final out = StringBuffer();
    final origin = <int>[];
    var pendingSpace = false;
    for (var i = 0; i < source.length; i++) {
      final folded = _fold(source.codeUnitAt(i));
      if (folded == null) {
        pendingSpace = out.isNotEmpty;
        continue;
      }
      if (pendingSpace) {
        out.writeCharCode(0x20);
        origin.add(i);
        pendingSpace = false;
      }
      out.writeCharCode(folded);
      origin.add(i);
    }
    return _Folded(out.toString(), origin);
  }

  final String text;

  /// La posición en el original de cada letra de [text].
  final List<int> origin;
}

/// [unit] en minúscula y sin tilde si es una letra o un número; `null` si es
/// un espacio o un signo.
int? _fold(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit;
  if (unit >= 0x61 && unit <= 0x7A) return unit;
  if (unit >= 0x41 && unit <= 0x5A) return unit + 0x20;
  if (unit < 0xC0) return null;
  final base = _bases[unit];
  if (base != null) return base;
  // Signos: la puntuación tipográfica (— « » “ ” …), las flechas y los
  // símbolos, la de los textos asiáticos y los emojis.
  if (unit == 0xD7 ||
      unit == 0xF7 ||
      (unit >= 0x2000 && unit <= 0x2BFF) ||
      (unit >= 0x3000 && unit <= 0x303F) ||
      (unit >= 0xD800 && unit <= 0xDFFF) ||
      (unit >= 0xFE30 && unit <= 0xFE4F) ||
      (unit >= 0xFF01 && unit <= 0xFF0F)) {
    return null;
  }
  // Otras letras (griego, cirílico, hebreo, chino…): en minúscula si la
  // tienen.
  final lower = String.fromCharCode(unit).toLowerCase();
  return lower.length == 1 ? lower.codeUnitAt(0) : unit;
}

/// Las letras con tilde de las lenguas latinas, a su base.
final Map<int, int> _bases = () {
  const groups = {
    'a': 'áàâäãåÁÀÂÄÃÅ',
    'e': 'éèêëÉÈÊË',
    'i': 'íìîïÍÌÎÏ',
    'o': 'óòôöõÓÒÔÖÕ',
    'u': 'úùûüÚÙÛÜ',
    'n': 'ñÑ',
    'c': 'çÇ',
    'y': 'ýÿÝ',
  };
  return {
    for (final entry in groups.entries)
      for (final unit in entry.value.codeUnits) unit: entry.key.codeUnitAt(0),
  };
}();
