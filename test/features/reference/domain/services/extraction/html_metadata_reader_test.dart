import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/html_metadata_reader.dart';

void main() {
  group('etiquetas citation_*', () {
    test('titulo, autores, revista y fecha de un articulo academico', () {
      final metadata = readHtmlMetadata('''
<html><head>
<meta name="citation_title" content="Un articulo de prueba">
<meta name="citation_author" content="Garcia, Ana">
<meta name="citation_author" content="Lopez, Juan">
<meta name="citation_journal_title" content="Revista de Prueba">
<meta name="citation_volume" content="12">
<meta name="citation_issue" content="3">
<meta name="citation_firstpage" content="45">
<meta name="citation_lastpage" content="67">
<meta name="citation_publication_date" content="2021/03/14">
<meta name="citation_doi" content="10.1000/xyz123">
</head><body></body></html>
''');

      expect(metadata.title, 'Un articulo de prueba');
      expect(metadata.reference.contributors.map((c) => c.name.label), [
        'Garcia, Ana',
        'Lopez, Juan',
      ]);
      expect(metadata.reference.containerTitle, 'Revista de Prueba');
      expect(metadata.reference.volume, '12');
      expect(metadata.reference.issue, '3');
      expect(metadata.reference.pages, '45-67');
      expect(metadata.publishedAt, DateTime(2021, 3, 14));
      expect(metadata.publicationPrecision, PublicationPrecision.day);
      expect(metadata.reference.doi, '10.1000/xyz123');
    });

    test('un DOI que no tiene la forma de uno se descarta', () {
      final metadata = readHtmlMetadata('''
<html><head>
<meta name="citation_doi" content="no es un doi">
</head></html>
''');

      expect(metadata.reference.doi, isNull);
    });
  });

  group('Dublin Core', () {
    test('titulo, autor y fecha, sin importar las mayusculas', () {
      final metadata = readHtmlMetadata('''
<html><head>
<meta name="DC.title" content="Titulo Dublin Core">
<meta name="DC.creator" content="Autora, Ana">
<meta name="DC.date" content="2019-06">
<meta name="DC.publisher" content="Editorial Prueba">
</head></html>
''');

      expect(metadata.title, 'Titulo Dublin Core');
      expect(metadata.reference.contributors.single.name.label, 'Autora, Ana');
      expect(metadata.publishedAt, DateTime(2019, 6));
      expect(metadata.publicationPrecision, PublicationPrecision.month);
      expect(metadata.reference.publisher, 'Editorial Prueba');
    });
  });

  group('JSON-LD', () {
    test('titulo, autor institucional y fecha de un Article', () {
      final metadata = readHtmlMetadata('''
<html><head>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "NewsArticle",
  "headline": "Un titular de prueba",
  "author": {"@type": "Organization", "name": "Diario de Prueba"},
  "datePublished": "2020-01-05"
}
</script>
</head></html>
''');

      expect(metadata.title, 'Un titular de prueba');
      final author = metadata.reference.contributors.single;
      expect(author.name.isInstitution, isTrue);
      expect(author.name.label, 'Diario de Prueba');
      expect(metadata.publishedAt, DateTime(2020, 1, 5));
    });

    test('un @type que no es citable se ignora', () {
      final metadata = readHtmlMetadata('''
<html><head>
<script type="application/ld+json">
{"@type": "WebSite", "name": "Sitio de prueba"}
</script>
</head></html>
''');

      expect(metadata.isEmpty, isTrue);
    });

    test('un bloque JSON-LD mal formado no rompe la lectura', () {
      final metadata = readHtmlMetadata('''
<html><head>
<script type="application/ld+json">{ esto no es json }</script>
<meta name="og:title" content="Titulo de respaldo">
</head></html>
''');

      expect(metadata.title, 'Titulo de respaldo');
    });
  });

  group('Open Graph, el ultimo respaldo', () {
    test('el titulo y la fecha de un articulo cualquiera', () {
      final metadata = readHtmlMetadata('''
<html><head>
<meta property="og:title" content="Titulo de la nota">
<meta property="article:published_time" content="2022-11-02T08:00:00Z">
</head></html>
''');

      expect(metadata.title, 'Titulo de la nota');
      expect(metadata.publishedAt, DateTime(2022, 11, 2));
    });
  });

  group('prioridad entre fuentes', () {
    test('citation_title gana sobre og:title', () {
      final metadata = readHtmlMetadata('''
<html><head>
<meta name="citation_title" content="Titulo academico">
<meta property="og:title" content="Titulo social">
</head></html>
''');

      expect(metadata.title, 'Titulo academico');
    });
  });

  test('una pagina sin ninguna etiqueta no encuentra nada', () {
    final metadata = readHtmlMetadata(
      '<html><head></head><body>Hola</body></html>',
    );

    expect(metadata.isEmpty, isTrue);
  });
}
