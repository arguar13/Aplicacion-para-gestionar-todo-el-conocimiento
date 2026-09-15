import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_style.dart';

/// Arma la cita de un elemento en el estilo pedido, a partir de la misma
/// procedencia que ya guarda cada [KnowledgeItem] —nunca hace falta
/// completar nada aparte, porque la procedencia nunca se pierde (principio
/// 2 de la arquitectura)—.
///
/// **Simplificación deliberada**: no separa "Apellido, Nombre" como exige
/// APA/MLA de verdad. `authorName` puede traer un nombre completo, el
/// nombre de un canal de YouTube o el de una cuenta de red social —esta
/// app no sabe ni le corresponde adivinar cuál es cuál—, así que se usa tal
/// cual viene. Zotero resuelve esto con una base de datos de miles de
/// formatos de nombre; acá alcanza con una cita legible y con todos los
/// datos, no con una que pase una revisión de estilo editorial estricta.
///
/// Sin autor conocido —pasa seguido con una página web o una nota propia
/// sin firma—, la cita arranca directo por el título: es lo que hacen las
/// tres normas cuando no hay a quién atribuirle la autoría.
String formatCitation(KnowledgeItem item, CitationStyle style) {
  final source = item.source;
  final author = source.authorName;
  final year = _yearOf(source);
  final title = item.title;
  final site = _siteNameOf(source);
  final url = source.url;

  return switch (style) {
    CitationStyle.apa => _apa(
      author: author,
      year: year,
      title: title,
      site: site,
      url: url,
    ),
    CitationStyle.mla => _mla(
      author: author,
      title: title,
      site: site,
      year: year,
      url: url,
    ),
    CitationStyle.chicago => _chicago(
      author: author,
      year: year,
      title: title,
      site: site,
      url: url,
    ),
  };
}

/// El año a citar es el de publicación cuando se sabe; sin eso, "s.f." (sin
/// fecha) — la fecha de captura no reemplaza a la de publicación, porque
/// decir que algo se publicó el día que uno lo guardó sería una cita
/// falsa, peor que una incompleta.
String _yearOf(Source source) =>
    source.publishedAt != null ? '${source.publishedAt!.year}' : 's.f.';

/// El dominio del enlace, como aproximación al "nombre del sitio" que
/// piden las tres normas. No es el nombre real del sitio —eso pediría una
/// base de datos de sitios conocidos, que esta app no tiene y no
/// necesita—, pero es lo mismo que hace cualquiera a mano cuando arma una
/// cita rápida: mirar la URL.
String? _siteNameOf(Source source) {
  final url = source.url;
  if (url == null) return null;

  final host = Uri.tryParse(url)?.host;
  if (host == null || host.isEmpty) return null;

  return host.startsWith('www.') ? host.substring(4) : host;
}

String _apa({
  required String? author,
  required String year,
  required String title,
  required String? site,
  required String? url,
}) {
  final parts = <String>[
    if (author != null) '$author.',
    '($year).',
    '$title.',
    if (site != null) '$site.',
    if (url != null) url,
  ];
  return parts.join(' ');
}

String _mla({
  required String? author,
  required String title,
  required String? site,
  required String year,
  required String? url,
}) {
  final parts = <String>[
    if (author != null) '$author.',
    '"$title."',
    if (site != null) '$site,',
    '$year,',
    if (url != null) url,
  ];
  final joined = parts.join(' ').trim();
  // MLA cierra con punto salvo cuando termina en un enlace: el punto se
  // confunde con el propio URL, así que se omite.
  return url == null && !joined.endsWith('.') ? '$joined.' : joined;
}

String _chicago({
  required String? author,
  required String year,
  required String title,
  required String? site,
  required String? url,
}) {
  final parts = <String>[
    if (author != null) '$author.',
    '$year.',
    '"$title."',
    if (site != null) '$site.',
    if (url != null) url,
  ];
  return parts.join(' ');
}
