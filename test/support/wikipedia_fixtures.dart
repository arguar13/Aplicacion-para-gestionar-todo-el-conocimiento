import 'dart:io';

import 'package:sinapsis/features/transform/data/clients/reader_mode_article_extractor.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';

/// El Markdown de un recorte real de Wikipedia
/// (`test/fixtures/web/wikipedia_<name>_recorte.html`), como lo guarda la
/// app de una página web: el artículo que deja el modo lectura, pasado a
/// Markdown. [page] es lo que va después de `/wiki/` en su dirección.
String wikipediaMarkdown(String name, String page) => htmlToMarkdown(
  const ReaderModeArticleExtractor()
      .extract(
        File(
          'test/fixtures/web/wikipedia_${name}_recorte.html',
        ).readAsStringSync(),
        baseUri: Uri.parse('https://es.wikipedia.org/wiki/$page'),
      )!
      .contentHtml,
);

/// El recorte de Fotosíntesis ([wikipediaMarkdown]).
String wikipediaFotosintesis() =>
    wikipediaMarkdown('fotosintesis', 'Fotos%C3%ADntesis');
