import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';

/// Qué es una parte del texto de un informe: de dónde sale lo que se lee.
enum ReportTextKind {
  /// El título del informe.
  title,

  /// La bajada, debajo del título.
  subtitle,

  /// El título de una sección, el que puso la IA.
  sectionTitle,

  /// Un bloque del texto de una sección: un párrafo, una viñeta, un
  /// subtítulo o una cita.
  block,

  /// El término de una entrada del glosario.
  term,

  /// La definición de una entrada del glosario.
  definition,

  /// Lo que pregunta una pregunta del interactivo.
  question,

  /// Una opción de una pregunta.
  option,
}

/// Dónde está una parte del texto de un informe (F45, paso 8c): qué es
/// ([kind]) y, según qué, su sección, su bloque, su entrada o su pregunta
/// ([index]) y su opción ([option]), por su lugar en el informe —una opción,
/// por su lugar en `ReportQuestion.options`, no por el orden mezclado en que
/// se muestra—. Lo que no aplica vale -1.
@immutable
class ReportTextPlace {
  const ReportTextPlace._(
    this.kind, {
    this.section = -1,
    this.index = -1,
    this.option = -1,
  });

  const ReportTextPlace.title() : this._(ReportTextKind.title);

  const ReportTextPlace.subtitle() : this._(ReportTextKind.subtitle);

  const ReportTextPlace.sectionTitle(int section)
    : this._(ReportTextKind.sectionTitle, section: section);

  const ReportTextPlace.block(int section, int block)
    : this._(ReportTextKind.block, section: section, index: block);

  const ReportTextPlace.term(int section, int entry)
    : this._(ReportTextKind.term, section: section, index: entry);

  const ReportTextPlace.definition(int section, int entry)
    : this._(ReportTextKind.definition, section: section, index: entry);

  const ReportTextPlace.question(int section, int question)
    : this._(ReportTextKind.question, section: section, index: question);

  const ReportTextPlace.option(int section, int question, int option)
    : this._(
        ReportTextKind.option,
        section: section,
        index: question,
        option: option,
      );

  final ReportTextKind kind;

  /// La sección (desde 0), o -1 en el título y la bajada.
  final int section;

  /// El bloque, la entrada o la pregunta dentro de la sección (desde 0).
  final int index;

  /// La opción dentro de su pregunta (desde 0).
  final int option;

  /// Si se ve solo en el formato interactivo: una pregunta o una opción.
  bool get interactiveOnly =>
      kind == ReportTextKind.question || kind == ReportTextKind.option;

  @override
  bool operator ==(Object other) =>
      other is ReportTextPlace &&
      other.kind == kind &&
      other.section == section &&
      other.index == index &&
      other.option == option;

  @override
  int get hashCode => Object.hash(kind, section, index, option);

  @override
  String toString() =>
      'ReportTextPlace(${kind.name}, $section, $index, $option)';
}

/// Una parte del texto de un informe: [text] —lo mismo que se ve, sin las
/// marcas de negrita ni de itálica— desde [start] del texto entero.
@immutable
class ReportTextPart {
  const ReportTextPart(this.place, this.start, this.text);

  final ReportTextPlace place;
  final int start;
  final String text;

  /// Dónde termina, sin incluir.
  int get end => start + text.length;

  @override
  bool operator ==(Object other) =>
      other is ReportTextPart &&
      other.place == place &&
      other.start == start &&
      other.text == text;

  @override
  int get hashCode => Object.hash(place, start, text);

  @override
  String toString() => 'ReportTextPart($place, $start, «$text»)';
}

/// **El texto de un informe** (F45, paso 8c): lo que se lee de él, de punta a
/// punta, como un solo texto —[content]— y dónde está cada parte ([parts]).
/// Sobre él se escriben las notas de un informe (`TextNoteTarget.creation`):
/// un informe no es un texto de corrido que se elige de una vez —son
/// secciones, entradas, preguntas y opciones, cada una en su tarjeta—, pero
/// cada pedazo elegido tiene así un lugar estable.
///
/// - Va en el orden del informe: el título y la bajada; de cada sección, su
///   título, los bloques de su texto (`parseReportBody`), su glosario —el
///   término y la definición— y sus preguntas con sus opciones, en el orden
///   en que están guardadas.
/// - Cada parte es exactamente lo que se ve —sin `**` ni `*`—: el visor la
///   dibuja con las mismas letras, así que una posición del visor es una del
///   texto. Las palabras clave en rosa no cambian ninguna letra.
/// - Las partes van separadas por un renglón en blanco ([separator]): un
///   pedazo que cruza de un bloque al otro se cita con ese salto, como en
///   cualquier texto.
/// - Lo vacío no es parte —un título de sección que la IA no puso, que se ve
///   como «Sección 3», no es texto del informe—.
/// - Las preguntas van siempre, también en el formato de lectura, que no las
///   muestra: así el texto —y el lugar de cada nota— no cambia con el
///   formato.
///
/// Se arma igual siempre que el informe sea el mismo: es la red sobre la que
/// `placeTextNotes` ubica las notas; si el informe se vuelve a generar, cada
/// nota se busca por su pedazo.
@immutable
class ReportText {
  ReportText._(this.content, this.parts)
    : _byPlace = {for (final part in parts) part.place: part};

  /// El texto del informe [report].
  factory ReportText.of(Report report) {
    final parts = <ReportTextPart>[];
    final content = StringBuffer();

    void add(ReportTextPlace place, String text) {
      if (text.isEmpty) return;
      if (content.isNotEmpty) content.write(separator);
      parts.add(ReportTextPart(place, content.length, text));
      content.write(text);
    }

    add(const ReportTextPlace.title(), report.title);
    add(const ReportTextPlace.subtitle(), report.subtitle);
    for (final (s, section) in report.sections.indexed) {
      add(ReportTextPlace.sectionTitle(s), section.title.trim());
      for (final (b, block) in parseReportBody(section.body).indexed) {
        add(ReportTextPlace.block(s, b), block.plainText);
      }
      for (final (e, entry) in section.entries.indexed) {
        add(ReportTextPlace.term(s, e), entry.term);
        add(
          ReportTextPlace.definition(s, e),
          reportInlinesText(parseReportInlines(entry.definition)),
        );
      }
      for (final (q, question) in section.questions.indexed) {
        add(
          ReportTextPlace.question(s, q),
          reportInlinesText(parseReportInlines(question.question)),
        );
        for (final (o, option) in question.options.indexed) {
          add(ReportTextPlace.option(s, q, o), option.text);
        }
      }
    }
    return ReportText._(content.toString(), List.unmodifiable(parts));
  }

  /// Lo que va entre una parte y la siguiente.
  static const separator = '\n\n';

  /// El texto entero.
  final String content;

  /// Las partes, en el orden del texto.
  final List<ReportTextPart> parts;

  final Map<ReportTextPlace, ReportTextPart> _byPlace;

  /// La parte de [place], o `null` si el informe no la tiene o está vacía.
  ReportTextPart? partAt(ReportTextPlace place) => _byPlace[place];

  /// La parte que tiene la posición [offset] —la que empieza ahí o antes y
  /// termina después—, o `null` si cae entre dos (en el separador) o fuera
  /// del texto.
  ReportTextPart? partContaining(int offset) {
    final index = _indexAtOrBefore(offset);
    if (index == null) return null;
    final part = parts[index];
    return offset < part.end ? part : null;
  }

  /// La primera parte que muestra algo de `[start, end)`: la de [start] o, si
  /// [start] cae en un separador, la siguiente. `null` si no toca ninguna.
  ReportTextPart? firstPartOf(int start, int end) {
    for (final part in partsTouching(start, end)) {
      return part;
    }
    return null;
  }

  /// Las partes que tocan `[start, end)`, en el orden del texto.
  Iterable<ReportTextPart> partsTouching(int start, int end) sync* {
    if (end <= start) return;
    var index = _indexAtOrBefore(start) ?? 0;
    for (; index < parts.length; index++) {
      final part = parts[index];
      if (part.start >= end) return;
      if (part.end > start) yield part;
    }
  }

  /// La última parte que empieza en [offset] o antes.
  int? _indexAtOrBefore(int offset) {
    var low = 0;
    var high = parts.length - 1;
    int? found;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (parts[middle].start <= offset) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }

  /// `[start, end)` del texto entero recortado a [part] y contado desde su
  /// comienzo, o `null` si no la toca.
  static (int, int)? clip(ReportTextPart part, int start, int end) {
    final from = math.max(start, part.start);
    final to = math.min(end, part.end);
    return to > from ? (from - part.start, to - part.start) : null;
  }
}

/// El texto de [inlines], sin estilos: lo que se ve.
String reportInlinesText(List<ReportInline> inlines) =>
    inlines.map((inline) => inline.text).join();
