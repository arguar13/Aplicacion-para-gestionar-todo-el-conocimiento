import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Arma la entrada BibTeX de un elemento, para llevar la bóveda a Zotero,
/// LaTeX o cualquier gestor de referencias que lea el formato estándar —en
/// vez de reimplementar citas, que es un trabajo enorme y ya resuelto en
/// otro lado, esto le entrega los datos a quien sí sabe hacerlo.
///
/// `@online` cuando hay un enlace al que volver, `@misc` cuando no —una
/// nota propia, un documento sin URL—: son los dos tipos de entrada que
/// BibTeX define justamente para eso, y ningún gestor de referencias
/// se sorprende con ninguno de los dos.
String formatBibtex(KnowledgeItem item) {
  final source = item.source;
  final entryType = source.url != null ? 'online' : 'misc';
  final key = _citeKey(item);

  final fields = <String, String>{
    'title': item.title,
    if (source.authorName != null) 'author': source.authorName!,
    if (source.publishedAt != null) 'year': '${source.publishedAt!.year}',
    if (source.url != null) 'url': source.url!,
    'urldate': _isoDate(item.updatedAt),
    'note': _noteFor(source.kind),
  };

  final buffer = StringBuffer('@$entryType{$key,\n');
  final entries = fields.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final isLast = i == entries.length - 1;
    buffer.writeln(
      '  ${entries[i].key} = {${_escapeBraces(entries[i].value)}}'
      '${isLast ? '' : ','}',
    );
  }
  buffer.writeln('}');

  return buffer.toString();
}

/// Una clave corta y sin ambigüedad: apellido (o la primera palabra del
/// título si no hay autor) más el año, todo en minúsculas y sin espacios —
/// el formato que espera cualquier motor de BibTeX para citar `\cite{...}`
/// sin tener que escribir el identificador a mano.
String _citeKey(KnowledgeItem item) {
  final source = item.source;
  final authorWord = source.authorName?.split(RegExp(r'\s+')).first;
  final titleWord = item.title.split(RegExp(r'\s+')).firstOrNull;
  final base = _asciiSlug(authorWord ?? titleWord ?? 'sinapsis');
  final year = source.publishedAt?.year ?? source.capturedAt.year;

  return '$base$year';
}

/// Solo letras y números ASCII: una clave BibTeX con acentos o símbolos
/// rompe en la mayoría de los motores de LaTeX, que todavía asumen texto
/// puro en los identificadores aunque el contenido del documento sea
/// UTF-8.
String _asciiSlug(String raw) {
  const withAccents = 'áéíóúñÁÉÍÓÚÑüÜ';
  const withoutAccents = 'aeiounAEIOUNuU';

  var result = raw;
  for (var i = 0; i < withAccents.length; i++) {
    result = result.replaceAll(withAccents[i], withoutAccents[i]);
  }

  final ascii = result.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  return ascii.isEmpty ? 'sinapsis' : ascii;
}

String _noteFor(SourceKind kind) => switch (kind) {
  SourceKind.youtube => 'Video de YouTube',
  SourceKind.webPage => 'Página web',
  SourceKind.socialPost => 'Publicación en red social',
  SourceKind.document => 'Documento',
  SourceKind.image => 'Imagen',
  SourceKind.audio => 'Audio',
  SourceKind.video => 'Video',
  SourceKind.manualNote => 'Nota propia',
  SourceKind.reference => 'Referencia',
};

String _isoDate(DateTime date) => date.toIso8601String().substring(0, 10);

/// Las llaves `{` y `}` delimitan campos en BibTeX: una que venga dentro
/// del propio valor —un título con una llave suelta, poco común pero
/// posible— tiene que escaparse, o corta el campo antes de tiempo.
String _escapeBraces(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('{', r'\{').replaceAll('}', r'\}');
