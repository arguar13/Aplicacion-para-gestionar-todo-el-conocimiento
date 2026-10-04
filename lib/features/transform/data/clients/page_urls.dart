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

/// Atributos de carga diferida con una dirección: los que usan los
/// cargadores de imágenes más comunes (lazysizes, los de WordPress y
/// Medium) para que el navegador no baje la imagen hasta que se ve.
const _lazyUrlAttributes = {
  'data-src',
  'data-lazy-src',
  'data-original',
  'data-original-src',
  'data-hi-res-src',
  'data-full-src',
  'data-url',
};

/// Atributos de carga diferida con una lista de direcciones, como `srcset`.
const _lazySrcsetAttributes = {'data-srcset', 'data-lazy-srcset'};

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
      if (name == 'srcset' || _lazySrcsetAttributes.contains(name)) {
        attributes[name] = absolutizeSrcset(entry.value, base);
      } else if (_lazyUrlAttributes.contains(name)) {
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

/// Un candidato de un `srcset`: la dirección y lo que dice de su tamaño.
typedef SrcsetCandidate = ({String url, String descriptor});

/// Los candidatos de un `srcset`, en orden.
///
/// Las comas separan candidatos, pero una dirección puede tener comas
/// adentro (`…/w_640,h_480/foto.jpg`, común en los CDN de imágenes): el
/// estándar dice que la dirección termina en el primer espacio, y solo una
/// coma pegada al final de la dirección —sin descriptor— la cierra.
List<SrcsetCandidate> parseSrcset(String srcset) {
  final candidates = <SrcsetCandidate>[];
  var i = 0;
  final text = srcset;
  bool isSpace(int index) => ' \t\n\r\f'.contains(text[index]);

  while (i < text.length) {
    while (i < text.length && (isSpace(i) || text[i] == ',')) {
      i++;
    }
    if (i >= text.length) break;
    final urlStart = i;
    while (i < text.length && !isSpace(i)) {
      i++;
    }
    var url = text.substring(urlStart, i);
    var descriptor = '';
    if (url.endsWith(',')) {
      url = url.replaceFirst(RegExp(r',+$'), '');
    } else {
      final descriptorStart = i;
      while (i < text.length && text[i] != ',') {
        i++;
      }
      descriptor = text.substring(descriptorStart, i).trim();
    }
    if (url.isNotEmpty) candidates.add((url: url, descriptor: descriptor));
  }
  return candidates;
}
