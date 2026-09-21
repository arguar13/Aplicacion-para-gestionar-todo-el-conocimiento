import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/services/citation_terms.dart';

/// Arma una [Citation] pieza por pieza, cuidando la puntuación que todos los
/// estilos comparten (F15): el punto que cierra cada elemento, el espacio que
/// los separa y el hueco de lo que falta.
///
/// Los estilos escriben lo que pasa —«el título en cursiva, punto, la
/// editorial»— y no cuentan letras: un título que ya termina en «?» no lleva
/// otro punto, una cursiva no arrastra los espacios de al lado.
class CitationBuilder {
  CitationBuilder(this.terms);

  /// Las palabras del idioma pedido.
  final CitationTerms terms;

  final List<CitationRun> _runs = [];

  /// Si todavía no se escribió nada.
  bool get isEmpty => _runs.isEmpty;

  /// La última letra escrita, o `null` si no hay nada.
  String? get _last {
    for (final run in _runs.reversed) {
      if (run.text.isNotEmpty) return run.text[run.text.length - 1];
    }
    return null;
  }

  /// Agrega texto sin formato.
  void plain(String text) {
    if (text.isNotEmpty) _runs.add(PlainRun(text));
  }

  /// Agrega texto en cursiva. Los espacios de los bordes quedan afuera: una
  /// cursiva que empieza o termina en un espacio no se lee bien en Markdown.
  void italic(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final start = text.indexOf(trimmed);
    plain(text.substring(0, start));
    _runs.add(ItalicRun(trimmed));
    plain(text.substring(start + trimmed.length));
  }

  /// Agrega [text] entre comillas, con la [punctuation] que le sigue: adentro
  /// de las comillas en inglés —«“Title.”»— y afuera en español —«Título».—,
  /// según los términos del idioma. Si el texto ya termina en «.», «?» o «!» no
  /// se le suma otro signo.
  void quoted(String text, {String punctuation = ''}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final last = trimmed[trimmed.length - 1];
    final mark = last == '.' || last == '?' || last == '!' ? '' : punctuation;
    if (terms.quotePunctuationInside) {
      plain('${terms.quoteOpen}$trimmed$mark${terms.quoteClose}');
    } else {
      plain('${terms.quoteOpen}$trimmed${terms.quoteClose}$mark');
    }
  }

  /// Agrega el título de una obra —o el hueco del título, si no hay— entre
  /// comillas si [inQuotes] y en cursiva si no, con la [punctuation] que le
  /// sigue. [markType] pone el hueco del tipo de obra después del título: lo
  /// que se escribe de una obra que no dice qué es. Un título que ya termina
  /// en «.», «?» o «!» no lleva otro signo.
  void title(
    String text, {
    required bool inQuotes,
    String punctuation = '',
    bool markType = false,
  }) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty && inQuotes) {
      quoted(trimmed, punctuation: punctuation);
      return;
    }
    if (trimmed.isEmpty) {
      gap(CitationGap.title);
    } else {
      italic(trimmed);
    }
    if (markType) {
      plain(' ');
      gap(CitationGap.type);
    }
    final last = _last;
    if (punctuation.isEmpty || last == '.' || last == '?' || last == '!') {
      return;
    }
    plain(punctuation);
  }

  /// Agrega el hueco de [gap], en el idioma de la cita.
  void gap(CitationGap gap) {
    _runs.add(terms.gap(gap));
  }

  /// Agrega otra cita ya armada.
  void append(Citation other) {
    _runs.addAll(other.runs);
  }

  /// Agrega un espacio, si hay algo escrito y no termina ya en uno.
  void space() {
    final last = _last;
    if (last != null && last != ' ') plain(' ');
  }

  /// Cierra el elemento con un punto, salvo que ya termine en «.», «?» o «!»:
  /// «M.» + «.» no es «M..», ni «¿Quién?» + «.» es «¿Quién?.».
  void period() {
    final last = _last;
    if (last == null) return;
    if (last != '.' && last != '?' && last != '!') plain('.');
  }

  /// Agrega una coma, salvo que ya termine en una.
  void comma() {
    final last = _last;
    if (last == null || last == ',') return;
    plain(',');
  }

  /// La cita armada.
  Citation build() => Citation(_runs);
}
