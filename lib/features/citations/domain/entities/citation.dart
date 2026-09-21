import 'package:meta/meta.dart';

/// Un dato que una cita necesita y la fuente no tiene (F15): lo que un hueco
/// visible —«[falta: año]»— avisa que hay que completar.
enum CitationGap {
  /// Quién escribió la obra.
  author,

  /// El título.
  title,

  /// El año de publicación.
  year,

  /// La editorial —o la universidad de una tesis—.
  publisher,

  /// El libro, la revista o el sitio que contiene la obra.
  container,

  /// El volumen de una revista.
  volume,

  /// El enlace de una fuente que está en la web.
  link,

  /// Qué clase de obra es: sin eso no se sabe qué forma darle a la cita.
  type,

  /// La fecha en que se consultó una obra en la web, en el estilo que la pide.
  accessed,
}

/// Un pedazo de una cita con un solo formato (F15).
///
/// Una cita no es un `String` porque los estilos piden cursivas —el título de
/// un libro— y quien la usa quiere mostrarlas: la interfaz, un `.docx` y un
/// Markdown las respetan; el portapapeles de texto plano no, y para eso está
/// [Citation.toPlainText]. Con un `String` habría que elegir entre perder las
/// cursivas o llevar marcas en el texto que alguien tiene que volver a quitar.
@immutable
sealed class CitationRun {
  const CitationRun();

  /// El texto del pedazo, tal como se lee.
  String get text;
}

/// Texto sin formato.
final class PlainRun extends CitationRun {
  const PlainRun(this.text);

  @override
  final String text;

  @override
  bool operator ==(Object other) => other is PlainRun && other.text == text;

  @override
  int get hashCode => Object.hash('plain', text);

  @override
  String toString() => 'PlainRun($text)';
}

/// Texto en cursiva: el título de una obra, el de una revista.
final class ItalicRun extends CitationRun {
  const ItalicRun(this.text);

  @override
  final String text;

  @override
  bool operator ==(Object other) => other is ItalicRun && other.text == text;

  @override
  int get hashCode => Object.hash('italic', text);

  @override
  String toString() => 'ItalicRun($text)';
}

/// Un dato que falta, dicho a la vista en lugar de inventarlo u omitirlo.
///
/// [text] es lo que se escribe —«[falta: año]»—, ya en el idioma de la cita;
/// [field] es qué falta, para que quien la muestra lo resalte y lleve a
/// completarlo.
final class GapRun extends CitationRun {
  const GapRun({required this.field, required this.text});

  final CitationGap field;

  @override
  final String text;

  @override
  bool operator ==(Object other) =>
      other is GapRun && other.field == field && other.text == text;

  @override
  int get hashCode => Object.hash('gap', field, text);

  @override
  String toString() => 'GapRun($text)';
}

/// Una cita ya armada: las corridas de texto, cursiva y huecos que un estilo
/// produjo para una fuente.
///
/// Es un valor: sale igual del mismo estilo para la misma fuente, y se compara
/// por lo que dice. Puede salir como texto plano, como Markdown o —más
/// adelante— como `.docx`, sin que el estilo sepa nada de eso.
@immutable
class Citation {
  /// Una cita con estas [runs]. Junta las contiguas del mismo formato y quita
  /// las vacías: quien la arma no tiene que cuidar cómo las parte.
  Citation(Iterable<CitationRun> runs)
    : runs = List.unmodifiable(_merged(runs));

  /// La cita vacía.
  const Citation.empty() : runs = const [];

  final List<CitationRun> runs;

  bool get isEmpty => runs.isEmpty;

  /// Los datos que le faltan, en el orden en que aparecen.
  List<CitationGap> get gaps => [
    for (final run in runs)
      if (run is GapRun) run.field,
  ];

  /// Si le falta algún dato.
  bool get hasGaps => runs.any((run) => run is GapRun);

  /// La cita como texto plano: sin cursivas —el portapapeles de Flutter no las
  /// lleva—, con los huecos escritos tal cual.
  String toPlainText() => runs.map((run) => run.text).join();

  /// La cita como Markdown: cursivas con `*`, y los huecos escritos entre
  /// corchetes escapados, para que no se lean como un enlace. El texto que el
  /// usuario escribió también se escapa: un título con un guion bajo no debe
  /// volverse una cursiva.
  String toMarkdown() {
    final out = StringBuffer();
    for (final run in runs) {
      switch (run) {
        case PlainRun():
          out.write(_escapeMarkdown(run.text));
        case ItalicRun():
          out.write('*${_escapeMarkdown(run.text)}*');
        case GapRun():
          out.write(_escapeMarkdown(run.text));
      }
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is Citation && _sameRuns(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'Citation(${toPlainText()})';
}

/// Junta las corridas contiguas del mismo formato y descarta las vacías.
List<CitationRun> _merged(Iterable<CitationRun> runs) {
  final out = <CitationRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) continue;
    final last = out.isEmpty ? null : out.last;
    if (last is PlainRun && run is PlainRun) {
      out[out.length - 1] = PlainRun(last.text + run.text);
    } else if (last is ItalicRun && run is ItalicRun) {
      out[out.length - 1] = ItalicRun(last.text + run.text);
    } else {
      out.add(run);
    }
  }
  return out;
}

bool _sameRuns(List<CitationRun> a, List<CitationRun> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _markdownSpecials = RegExp(r'([\\*_\[\]`])');

String _escapeMarkdown(String text) =>
    text.replaceAllMapped(_markdownSpecials, (match) => '\\${match[1]}');
