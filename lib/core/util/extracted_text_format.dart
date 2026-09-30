import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Si el texto guardado de [source] es Markdown —y se muestra con formato:
/// títulos, listas, negrita— o texto tal cual (F22).
///
/// Markdown de verdad es lo que la app arma con esa forma: una nota, una
/// página web o un Word o un EPUB convertidos —con sus títulos y sus
/// listas—, y un archivo `.md`. Todo lo demás es el texto del original tal
/// cual: una transcripción, lo que se reconoció en una foto, el texto de un
/// PDF, un `.txt`, una publicación. Mostrarlo como Markdown lo alteraba en
/// pantalla —un "var_uno_dos" reconocido en una foto salía en cursiva y sin
/// guiones bajos, un "# 3" de una lista se volvía un título— aunque lo
/// guardado estuviera bien.
bool extractedTextIsMarkdown(Source source) => switch (source.kind) {
  SourceKind.manualNote || SourceKind.webPage => true,
  SourceKind.document => const {
    '.docx',
    '.epub',
    '.md',
    '.markdown',
  }.contains(p.extension(source.originalFilePath ?? '').toLowerCase()),
  _ => false,
};

/// Si el texto de [source] es una transcripción, con una marca de tiempo por
/// línea: lo único a lo que tiene sentido ofrecerle "Quitar marcas de
/// tiempo" (F22). Antes se ofrecía en cualquier texto con una línea que
/// empezara como "[12:30]", un PDF o un Word incluidos.
bool isTranscriptSource(Source source) => const {
  SourceKind.youtube,
  SourceKind.audio,
  SourceKind.video,
}.contains(source.kind);
