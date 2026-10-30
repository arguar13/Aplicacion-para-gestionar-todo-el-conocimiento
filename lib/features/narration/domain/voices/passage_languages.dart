import 'package:sinapsis/core/util/language_guess.dart';
import 'package:sinapsis/core/util/text_script.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Cuántas palabras de la lista de un idioma hacen falta para dar por
/// reconocida **una oración**: ver `guessLanguage`.
const _passageHits = 3;

/// De cuántos pedazos, repartidos por todo el texto, se saca su idioma: el
/// comienzo de un libro puede ser una portada o un prólogo en otro idioma.
const _documentSample = 40;

/// Hasta cuánto texto se mira para el idioma del documento.
const _documentLength = 4000;

/// El idioma en que está escrito [text] —un pasaje, una oración—, como código
/// de dos letras, o `null` si no se puede saber con seguridad (F47, paso 3).
///
/// Reúne lo que la app ya sabe reconocer (F22 y F45, paso 4): la escritura, si
/// sola lo dice —el ruso, el árabe, el hindi, el griego—, y las palabras más
/// frecuentes en letras latinas —el español, el inglés, el portugués, el
/// francés, el italiano y el alemán—. En ideogramas, el japonés si hay kana y
/// el chino si no. Con dos escrituras mezcladas, `null`.
String? languageOfPassage(String text, {int minimumHits = _passageHits}) {
  final script = scriptCensusOf(text).clearScript(minimumLetters: 4);
  return switch (script) {
    null => null,
    TextScript.latin => guessLanguage(
      text,
      maximumLength: _documentLength,
      minimumHits: minimumHits,
    ),
    TextScript.cjk => _kana.hasMatch(text) ? 'ja' : 'zh',
    final script => languageOfScript(script),
  };
}

/// Hiragana y katakana: solo el japonés los usa.
final _kana = RegExp('[぀-ヿ]');

/// El idioma de cada pedazo de lo que lee el lector en voz alta (F47, paso 3,
/// decisión L): **la voz sigue al idioma del texto**, y un texto con partes en
/// dos idiomas se lee con las dos.
///
/// - Un pedazo que se reconoce solo —una oración en inglés en medio de un
///   texto en español— es de su idioma.
/// - Uno que no se reconoce —un título, una oración corta— es del idioma de
///   los pedazos de los dos lados, si los dos dicen el mismo; si no, del
///   idioma del documento, que se saca de pedazos repartidos por todo el
///   texto.
/// - Si ni el documento se reconoce, `null`: lee la voz elegida de siempre.
///
/// Se calcula a medida que se pregunta —un libro son decenas de miles de
/// pedazos, y el lector pregunta de a uno— y se recuerda por lista de
/// pedazos ([PassageLanguages.of]).
class PassageLanguages {
  PassageLanguages._(this._segments);

  /// Los idiomas de [segments], uno por lista: el lector y la biblioteca
  /// preguntan por la misma lista y comparten lo calculado.
  factory PassageLanguages.of(List<ReadableSegment> segments) =>
      _bySegments[segments] ??= PassageLanguages._(segments);

  static final _bySegments = Expando<PassageLanguages>('idiomas por pedazo');

  final List<ReadableSegment> _segments;
  final _own = <int, String?>{};
  bool _documentKnown = false;
  String? _document;

  /// El idioma del documento entero, o `null` si no se reconoce.
  ///
  /// Por mayoría entre los pedazos de la muestra que se reconocen solos: un
  /// texto en español con una cita larga en inglés sigue siendo en español,
  /// aunque contadas todas sus palabras juntas el inglés no quede tan atrás
  /// —y `guessLanguage`, ante la duda, no diría ninguno—. Si ningún pedazo se
  /// reconoce solo —una lista de palabras clave, renglones cortos—, se mira
  /// la muestra entera junta.
  String? get document {
    if (_documentKnown) return _document;
    _documentKnown = true;
    final length = _segments.length;
    if (length == 0) return null;
    final step = length <= _documentSample ? 1 : length ~/ _documentSample;
    final votes = <String, int>{};
    final sample = StringBuffer();
    for (var i = 0; i < length && sample.length < _documentLength; i += step) {
      if (_ownAt(i) case final language?) {
        votes[language] = (votes[language] ?? 0) + 1;
      }
      sample
        ..write(_segments[i].spoken)
        ..write('\n');
    }
    final ranking = votes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranking.isNotEmpty) {
      final tied = ranking.length > 1 && ranking[1].value == ranking[0].value;
      return _document = tied ? null : ranking.first.key;
    }
    return _document = languageOfPassage(sample.toString(), minimumHits: 4);
  }

  /// El idioma del pedazo [index]: ver [PassageLanguages].
  String? at(int index) {
    if (index < 0 || index >= _segments.length) return document;
    final own = _ownAt(index);
    if (own != null) return own;
    final before = index > 0 ? _ownAt(index - 1) : null;
    if (before != null && before == _ownAt(index + 1)) return before;
    return document;
  }

  String? _ownAt(int index) {
    if (index < 0 || index >= _segments.length) return null;
    return _own.putIfAbsent(
      index,
      () => languageOfPassage(_segments[index].spoken),
    );
  }
}
