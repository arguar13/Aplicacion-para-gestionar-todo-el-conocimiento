import 'package:meta/meta.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Una fuente que entra en una bibliografía (F15): cuál es y lo que hace falta
/// para citarla.
@immutable
class BibliographySource {
  const BibliographySource({required this.itemId, required this.source});

  /// El elemento de la biblioteca de donde sale.
  final String itemId;

  /// Su título, sus datos bibliográficos y de dónde salió.
  final CitationSource source;
}

/// Una entrada ya armada de una [Bibliography].
@immutable
class BibliographyEntry {
  const BibliographyEntry({
    required this.itemId,
    required this.citation,
    this.number,
    this.yearSuffix,
  });

  /// El elemento de la biblioteca que cita.
  final String itemId;

  /// La entrada, con sus cursivas y sus huecos.
  final Citation citation;

  /// Su número, en un estilo que numera —IEEE—; `null` en los demás.
  final int? number;

  /// La letra que la distingue de otra obra del mismo autor y del mismo año en
  /// un estilo autor-fecha —«a» en «2019a»—; `null` si no hace falta. La
  /// cita en el texto de esta obra lleva la misma.
  final String? yearSuffix;
}

/// La lista de obras de un conjunto de fuentes, ordenada como la pide el estilo
/// y lista para mostrar, copiar o llevar a un documento (F15).
///
/// Es un valor: no sabe de dónde salieron sus fuentes ni cómo se muestra.
/// Quien la pide elige el formato —texto plano, Markdown o `.docx`—; las
/// entradas conservan sus cursivas y sus huecos, y el texto plano las pierde
/// porque no las lleva.
@immutable
class Bibliography {
  Bibliography({
    required this.styleId,
    required this.title,
    required this.language,
    required Iterable<BibliographyEntry> entries,
  }) : entries = List.unmodifiable(entries);

  /// El estilo con que se armó: `apa7`, `mla9`…
  final String styleId;

  /// Cómo se titula la lista en ese estilo y ese idioma: «Referencias»,
  /// «Obras citadas».
  final String title;

  /// El idioma de los términos de la lista.
  final CitationLanguage language;

  /// Las entradas, en el orden en que se muestran.
  final List<BibliographyEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// Cuántas entradas hay.
  int get length => entries.length;

  /// Cuántas entradas tienen algún dato que falta.
  int get entriesWithGaps =>
      entries.where((entry) => entry.citation.hasGaps).length;

  /// Si alguna entrada tiene un dato que falta.
  bool get hasGaps => entriesWithGaps > 0;

  /// Una entrada por línea, sin formato: el texto plano no lleva cursivas.
  String toPlainText() =>
      entries.map((entry) => entry.citation.toPlainText()).join('\n');

  /// Una entrada por párrafo, con las cursivas entre asteriscos y lo que el
  /// usuario escribió escapado, para pegar en un documento de Markdown.
  String toMarkdown() =>
      entries.map((entry) => entry.citation.toMarkdown()).join('\n\n');
}
