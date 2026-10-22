/// Las fotos de una página web: cuál es la de verdad de cada `<img>` (F36).
///
/// Una sola elección para todo el que mira una foto de una página: el
/// buscador de adjuntos —la más grande, para bajarla—, el archivador —la
/// que alcanza para leer, para guardarla adentro del archivo— y el visor de
/// la página archivada, que arregla las fotos de los archivos viejos.
library;

import 'package:html/dom.dart';

/// Dónde guardan muchas páginas la foto de verdad para cargarla con un
/// programa cuando se llega a ella —la carga «perezosa»: lazysizes, los de
/// WordPress y Medium—: en `src` queda un cuadradito transparente, o nada.
const lazyImageUrlAttributes = {
  'data-src',
  'data-lazy-src',
  'data-original',
  'data-original-src',
  'data-lazy',
  'data-url',
  'data-hi-res-src',
  'data-full-src',
};

/// Lo mismo, con una lista de direcciones como la de `srcset`.
const lazyImageSrcsetAttributes = {'data-srcset', 'data-lazy-srcset'};

/// Lo que se le saca a una foto ya resuelta: las alternativas que un
/// navegador preferiría a su `src`.
const _alternatives = [
  'srcset',
  'sizes',
  ...lazyImageUrlAttributes,
  ...lazyImageSrcsetAttributes,
];

/// Qué tamaño de foto se busca.
enum ImageSize {
  /// La más grande que ofrece: un adjunto se baja para quedárselo.
  largest,

  /// La que alcanza para leer en un teléfono o una tableta —hasta 1600 de
  /// ancho o 2x—, sin guardar la versión para un monitor enorme.
  screen,
}

const _screenWidth = 1600;
const _screenDensity = 2.0;

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

/// La mejor de las fotos de un `srcset` según [size], o `null` si no trae
/// ninguna. Un dato incrustado no cuenta: es el cuadradito de una carga
/// perezosa.
///
/// Si dice anchos, se elige por ancho —un ancho en píxeles dice cuánto mide
/// la foto; "2x" no—; si no, por densidad, y sin descriptor es 1x. Para
/// leer, la más grande que entra —o la más chica, si todas se pasan—.
String? bestSrcsetCandidate(String? srcset, {required ImageSize size}) {
  if (srcset == null) return null;
  final candidates = [
    for (final candidate in parseSrcset(srcset))
      if (!candidate.url.startsWith('data:'))
        (url: candidate.url, measure: _measure(candidate.descriptor)),
  ];
  if (candidates.isEmpty) return null;

  final widths = candidates.where((c) => c.measure.isWidth).toList();
  final chosen = (widths.isNotEmpty ? widths : candidates)
    ..sort((a, b) => a.measure.value.compareTo(b.measure.value));
  if (size == ImageSize.largest) return chosen.last.url;
  final limit = widths.isNotEmpty ? _screenWidth : _screenDensity;
  final fitting = chosen.where((c) => c.measure.value <= limit);
  return (fitting.isEmpty ? chosen.first : fitting.last).url;
}

({double value, bool isWidth}) _measure(String descriptor) {
  final match = RegExp(r'^([\d.]+)([wx])$').firstMatch(descriptor);
  if (match == null) return (value: 1, isWidth: false);
  return (value: double.tryParse(match[1]!) ?? 1, isWidth: match[2] == 'w');
}

/// La foto de verdad de [img] según [size], como la escribió la página
/// —puede ser relativa—, o `null` si no tiene ninguna. Nunca un dato
/// incrustado: ese es el cuadradito, o ya está guardada.
///
/// Primero lo de la carga perezosa —su `srcset`, después su dirección—:
/// sin JavaScript nadie cambia el cuadradito por la foto, y el `srcset` de
/// al lado suele ser la versión borrosa que se ve mientras tanto. Después
/// el `srcset` —el del `<img>` o el de un `<source>` de su `<picture>`—,
/// que el navegador del teléfono, de pantalla densa, elige antes que el
/// `src`: si esa no se guardó, la foto no aparece. Y si no, su `src`.
String? bestImageSource(Element img, {required ImageSize size}) {
  final attributes = img.attributes;
  for (final name in lazyImageSrcsetAttributes) {
    final best = bestSrcsetCandidate(attributes[name], size: size);
    if (best != null) return best;
  }
  for (final name in lazyImageUrlAttributes) {
    final value = _webValue(attributes[name]);
    if (value != null) return value;
  }
  final own = bestSrcsetCandidate(attributes['srcset'], size: size);
  if (own != null) return own;
  final picture = img.parent;
  if (picture != null && picture.localName == 'picture') {
    for (final source in picture.children) {
      if (source.localName != 'source') continue;
      final best = bestSrcsetCandidate(
        source.attributes['srcset'] ?? source.attributes['data-srcset'],
        size: size,
      );
      if (best != null) return best;
    }
  }
  return _webValue(attributes['src']);
}

String? _webValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed.startsWith('data:')) {
    return null;
  }
  return trimmed;
}

/// Deja a [img] con [src] y nada que un navegador prefiera antes: sin
/// `srcset` ni lo de la carga perezosa, y sin los `<source>` de su
/// `<picture>`.
void settleImage(Element img, String src) {
  img.attributes['src'] = src;
  for (final name in _alternatives) {
    img.attributes.remove(name);
  }
  final picture = img.parent;
  if (picture != null && picture.localName == 'picture') {
    for (final source in picture.children.toList()) {
      if (source.localName == 'source') source.remove();
    }
  }
}

/// Las fotos de una página ya archivada, listas para verse: una que se
/// guardó adentro del archivo queda sola, sin alternativas que le ganen; una
/// que no, apunta a su foto de verdad, que se carga si hay conexión.
///
/// Arregla al mostrarlas las páginas archivadas antes de que el archivador
/// eligiera bien la foto —ver `HtmlPageArchiver`—.
void showArchivedImages(Document document) {
  for (final img in document.querySelectorAll('img')) {
    final src = img.attributes['src']?.trim() ?? '';
    if (_isSavedImage(src)) {
      settleImage(img, src);
      continue;
    }
    final best = bestImageSource(img, size: ImageSize.screen);
    if (best != null && best != src) settleImage(img, best);
  }
}

/// Una foto guardada adentro del archivo, y no el cuadradito transparente
/// que una carga perezosa pone en su lugar —un GIF o un SVG de unos pocos
/// bytes—.
bool _isSavedImage(String src) => src.startsWith('data:') && src.length > 512;
