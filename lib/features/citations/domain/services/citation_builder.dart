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
