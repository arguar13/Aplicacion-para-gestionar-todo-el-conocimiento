/// Las direcciones de una página, completas (F30).
///
/// Una página escribe sus enlaces e imágenes como le queda cómodo: relativas
/// a la carpeta (`img/a.png`, `../b.pdf`), al sitio (`/wiki/Roma`) o al
/// esquema (`//upload.wikimedia.org/…`). Fuera de la página —en el Markdown
/// guardado, en un archivo bajado— esas direcciones no llevan a ningún lado:
/// hay que completarlas contra la dirección de la página, como lo hace un
/// navegador.
library;

import 'package:html/dom.dart' as dom;
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';

/// La dirección contra la que se resuelven las relativas de [document]: la
/// de su primer `<base href>`, si lo declara, resuelta a su vez contra
/// [pageUri]; si no, [pageUri].
///
/// Solo cuenta un `<base>` http o https: uno que apunte a `javascript:` o a
/// `file:` no puede convertir los enlaces de una página web en otra cosa.
Uri documentBaseUri(dom.Document document, Uri pageUri) {
  final href = document.querySelector('base[href]')?.attributes['href'];
  if (href == null) return pageUri;
  final resolved = resolvePageUrl(pageUri, href);
  return resolved ?? pageUri;
}

/// [reference] resuelta contra [base], o `null` si no es una dirección web.
///
/// Se descartan los espacios de los bordes y los saltos de línea y
/// tabulaciones de adentro, como hace un navegador. Lo que no es http ni
/// https —`data:`, `mailto:`, `javascript:`, `tel:`— da `null`: no es algo
/// que se pueda completar ni bajar.
Uri? resolvePageUrl(Uri base, String reference) {
  final cleaned = reference.replaceAll(RegExp('[\t\n\r]'), '').trim();
  if (cleaned.isEmpty) return null;
  final Uri resolved;
  try {
    resolved = base.resolve(cleaned);
  } on FormatException {
    return null;
  }
  if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
  if (resolved.host.isEmpty) return null;
  return resolved;
}

/// Los atributos que guardan una sola dirección, por etiqueta.
const _urlAttributes = <String, List<String>>{
  'a': ['href'],
  'area': ['href'],
  'img': ['src'],
  'source': ['src'],
  'video': ['src', 'poster'],
  'audio': ['src'],
  'track': ['src'],
  'embed': ['src'],
  'iframe': ['src'],
  'object': ['data'],
  'input': ['src'],
};

/// Completa en el lugar cada dirección de [document] contra [base].
///
/// Un ancla de la misma página (`#nota-3`) queda como está: es un salto
/// adentro del texto, no un enlace a otro lado. Lo que no es web
/// (`mailto:`, `data:`…) también queda como está.
void absolutizePageUrls(dom.Document document, Uri base) {
  String? absolute(String value) {
    if (value.trim().startsWith('#')) return null;
    return resolvePageUrl(base, value)?.toString();
  }

  for (final element in document.querySelectorAll('*')) {
    final tag = element.localName;
    final attributes = element.attributes;
    for (final name in _urlAttributes[tag] ?? const <String>[]) {
      final value = attributes[name];
      if (value == null) continue;
      final resolved = absolute(value);
      if (resolved != null) attributes[name] = resolved;
    }
    for (final entry in attributes.entries.toList()) {
      final name = entry.key;
      if (name is! String) continue;
      if (name == 'srcset' || lazyImageSrcsetAttributes.contains(name)) {
        attributes[name] = absolutizeSrcset(entry.value, base);
      } else if (lazyImageUrlAttributes.contains(name)) {
        final resolved = absolute(entry.value);
        if (resolved != null) attributes[name] = resolved;
      }
    }
  }
}

/// Un `srcset` —"a.jpg 1x, b.jpg 2x" o "a.jpg 320w, b.jpg 640w"— con cada
/// dirección completa y su descriptor intacto. Una dirección que no se
/// puede completar queda como venía.
String absolutizeSrcset(String srcset, Uri base) =>
    parseSrcset(srcset).map((candidate) {
      final url = resolvePageUrl(base, candidate.url)?.toString();
      final descriptor = candidate.descriptor;
      final written = url ?? candidate.url;
      return descriptor.isEmpty ? written : '$written $descriptor';
    }).join(', ');
