import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';
import 'package:sinapsis/core/domain/services/person_name_parser.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/flexible_date.dart';

/// Lee los metadatos bibliográficos de una página (F15, D12): las etiquetas
/// `citation_*` que usan los repositorios académicos y Google Scholar, las
/// `DC.*` de Dublin Core, un bloque JSON-LD de tipo `Article` o `Book`, y por
/// último `og:` —el respaldo más pobre: un sitio cualquiera, no uno pensado
/// para citarse—.
///
/// Un mismo dato puede salir de varias fuentes a la vez —el título en
/// `citation_title` y en `og:title`—; gana la de la lista, en ese orden: lo
/// pensado para citar es más confiable que lo pensado para compartir en una
/// red social. Ninguna inventa lo que no trae: lo que falta queda en `null`.
ExtractedMetadata readHtmlMetadata(String html) {
  final document = html_parser.parse(html);
  final meta = _metaMap(document);

  return mergeExtractedMetadata([
    _fromCitationMeta(meta),
    _fromJsonLd(document),
    _fromDublinCoreMeta(meta),
    _fromOpenGraphMeta(meta),
  ]);
}

/// Cada `<meta>` por su `name` o su `property`, en minúsculas —los sitios no
/// son consistentes con las mayúsculas de `DC.title` o `DC.Title`—, con
/// todos los valores repetidos: `citation_author` trae uno por autor.
Map<String, List<String>> _metaMap(Document document) {
  final map = <String, List<String>>{};
  for (final tag in document.querySelectorAll('meta')) {
    final key = (tag.attributes['name'] ?? tag.attributes['property'])
        ?.trim()
        .toLowerCase();
    final content = tag.attributes['content']?.trim();
    if (key == null || key.isEmpty) continue;
    if (content == null || content.isEmpty) continue;
    map.putIfAbsent(key, () => []).add(content);
  }
  return map;
}

ExtractedMetadata _fromCitationMeta(Map<String, List<String>> meta) {
  String? one(String key) => meta[key]?.first;

  final dateText =
      one('citation_publication_date') ??
      one('citation_date') ??
      one('citation_online_date');
  final date = dateText == null ? null : parseFlexibleDate(dateText);
  final isbn = one('citation_isbn');
  final doi = one('citation_doi');

  return ExtractedMetadata(
    title: one('citation_title'),
    publishedAt: date?.date,
    publicationPrecision: date?.precision,
    reference: ReferenceData(
      contributors: _contributorsFromNames(meta['citation_author'] ?? const []),
      containerTitle:
          one('citation_journal_title') ??
          one('citation_conference_title') ??
          one('citation_book_title'),
      publisher: one('citation_publisher'),
      volume: one('citation_volume'),
      issue: one('citation_issue'),
      pages: _pagesOf(one('citation_firstpage'), one('citation_lastpage')),
      isbn: isbn == null ? null : normalizeIsbn(isbn),
      doi: doi == null ? null : normalizeDoi(doi),
    ),
  );
}

ExtractedMetadata _fromDublinCoreMeta(Map<String, List<String>> meta) {
  String? one(String key) => meta[key]?.first;

  final dateText = one('dc.date') ?? one('dc.date.issued') ?? one('dc.issued');
  final date = dateText == null ? null : parseFlexibleDate(dateText);
  // Dublin Core no separa el ISBN del DOI: los dos van en `DC.identifier`, y
  // solo uno de los dos lo reconoce.
  final identifier = one('dc.identifier');

  return ExtractedMetadata(
    title: one('dc.title'),
    publishedAt: date?.date,
    publicationPrecision: date?.precision,
    reference: ReferenceData(
      contributors: _contributorsFromNames(meta['dc.creator'] ?? const []),
      publisher: one('dc.publisher'),
      isbn: identifier == null ? null : normalizeIsbn(identifier),
      doi: identifier == null ? null : normalizeDoi(identifier),
    ),
  );
}

ExtractedMetadata _fromOpenGraphMeta(Map<String, List<String>> meta) {
  String? one(String key) => meta[key]?.first;

  final dateText = one('article:published_time') ?? one('og:updated_time');
  final date = dateText == null ? null : parseFlexibleDate(dateText);

  return ExtractedMetadata(
    title: one('og:title'),
    publishedAt: date?.date,
    publicationPrecision: date?.precision,
  );
}

/// Los tipos de `@type` de JSON-LD que valen como una obra citable. Los que
/// no están en la lista —un `Organization`, un `Person` suelto, un menú de
/// navegación con su propio bloque `SiteNavigationElement`— se ignoran.
const _knownJsonLdTypes = {
  'article',
  'newsarticle',
  'blogposting',
  'scholarlyarticle',
  'report',
  'book',
  'thesis',
};

ExtractedMetadata _fromJsonLd(Document document) {
  for (final script in document.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    final text = script.text.trim();
    if (text.isEmpty) continue;

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
      // Un bloque JSON-LD mal formado no tira abajo el resto de la
      // extracción: se lo salta y se sigue con el próximo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      continue;
    }

    for (final node in _jsonLdNodes(decoded)) {
      final extracted = _fromJsonLdNode(node);
      if (!extracted.isEmpty) return extracted;
    }
  }
  return const ExtractedMetadata();
}

/// Los nodos de un documento JSON-LD, que puede ser un objeto solo, una lista
/// de objetos, o un objeto con `@graph`.
Iterable<Map<String, dynamic>> _jsonLdNodes(Object? decoded) sync* {
  if (decoded is Map<String, dynamic>) {
    final graph = decoded['@graph'];
    if (graph is List) {
      for (final item in graph) {
        if (item is Map<String, dynamic>) yield item;
      }
    } else {
      yield decoded;
    }
  } else if (decoded is List) {
    for (final item in decoded) {
      if (item is Map<String, dynamic>) yield item;
    }
  }
}

ExtractedMetadata _fromJsonLdNode(Map<String, dynamic> node) {
  final type = node['@type'];
  final typeText = (type is List ? type.join(' ') : type?.toString() ?? '')
      .toLowerCase();
  if (!_knownJsonLdTypes.any(typeText.contains)) {
    return const ExtractedMetadata();
  }

  final dateText = _jsonLdText(node['datePublished']);
  final date = dateText == null ? null : parseFlexibleDate(dateText);
  final isbn = _jsonLdText(node['isbn']);

  return ExtractedMetadata(
    title: _jsonLdText(node['headline']) ?? _jsonLdText(node['name']),
    publishedAt: date?.date,
    publicationPrecision: date?.precision,
    reference: ReferenceData(
      contributors: _jsonLdPersons(node['author']),
      publisher: _jsonLdText(node['publisher']),
      isbn: isbn == null ? null : normalizeIsbn(isbn),
    ),
  );
}

/// El texto de un valor de JSON-LD: un texto tal cual, o el `name` de un
/// objeto —`{"@type": "Organization", "name": "Planeta"}`—.
String? _jsonLdText(Object? value) {
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is Map) return _jsonLdText(value['name']);
  return null;
}

/// Las personas de un valor de JSON-LD —un texto, un objeto, o una lista de
/// cualquiera de los dos—. Un `Organization` es una institución; una
/// `Person`, o un texto sin decir qué es, se parte en apellido y nombre.
List<Contributor> _jsonLdPersons(Object? value) {
  final nodes = switch (value) {
    null => const <Object>[],
    final List<dynamic> list => list,
    final other => [other],
  };

  final contributors = <Contributor>[];
  for (final node in nodes) {
    if (node is String) {
      final parsed = parseName(node);
      if (parsed != null) contributors.add(Contributor(name: parsed.name));
      continue;
    }
    if (node is Map) {
      final name = _jsonLdText(node['name']);
      if (name == null) continue;
      final isOrganization = (node['@type']?.toString().toLowerCase() ?? '')
          .contains('organization');
      contributors.add(
        Contributor(
          name: isOrganization
              ? PersonName.institution(name)
              : parseName(name)?.name ?? PersonName.institution(name),
        ),
      );
    }
  }
  return contributors;
}

/// Las personas de una lista de `<meta>` ya separados, uno por autor —cada
/// `citation_author` o `DC.creator` es UN nombre, no una lista de nombres—:
/// no hace falta partir por «y» ni por «and».
List<Contributor> _contributorsFromNames(Iterable<String> names) => [
  for (final name in names)
    if (parseName(name) case final parsed?) Contributor(name: parsed.name),
];

String? _pagesOf(String? first, String? last) {
  final f = first?.trim();
  final l = last?.trim();
  if (f == null || f.isEmpty) return null;
  if (l == null || l.isEmpty || l == f) return f;
  return '$f-$l';
}
