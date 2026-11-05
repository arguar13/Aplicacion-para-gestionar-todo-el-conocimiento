import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';
import 'package:sinapsis/features/processed/domain/services/headings/markdown_headings.dart';

/// Lo que la fuente dice de una imagen, de lo más propio a lo menos: con eso
/// se le pone su título al triarla (F46, decisión E).
@immutable
class ImageTitleClues {
  const ImageTitleClues({
    required this.fileName,
    this.caption,
    this.alt,
    this.nearbyHeading,
  });

  /// El pie de foto: el epígrafe de la página, el título que la persona le
  /// puso a la imagen guardada.
  final String? caption;

  /// El texto alternativo de la página web o del libro.
  final String? alt;

  /// El título bajo el que está en el texto de la fuente.
  final String? nearbyHeading;

  /// El archivo —con su ruta, o como dirección—: lo último a lo que se
  /// recurre.
  final String fileName;
}

/// El título de una imagen (F46, decisión E): el primero que diga algo de
/// [clues] —el pie de foto, el texto alternativo, el título cercano— y, si
/// ninguno dice nada, el nombre de su archivo, limpio
/// ([imageTitleFromFileName]). `null` si tampoco el nombre dice nada —un
/// `IMG_2034.jpg`—: la pantalla la nombra por su lugar («Imagen 3»).
///
/// Lo que no dice nada no cuenta: vacío, solo números o signos, una
/// dirección, una palabra de relleno —«imagen», «foto», «image»— o un nombre
/// de archivo —que se limpia como tal—. Uno larguísimo se corta en
/// [kImageTitleMaxChars], como los nombres de lo que se baja de una página.
String? processedImageTitle(ImageTitleClues clues) {
  for (final candidate in [clues.caption, clues.alt, clues.nearbyHeading]) {
    if (_meaningful(candidate) case final title?) return title;
  }
  return imageTitleFromFileName(clues.fileName);
}

/// Cuántos caracteres tiene, como mucho, el título de una imagen.
const kImageTitleMaxChars = 160;

/// El nombre del archivo [path] como título (F46, decisión E): sin la
/// carpeta, sin la extensión, sin guiones ni guiones bajos, y sin lo que le
/// agregan la cámara, el teléfono o la página —`IMG_`, `DSC`, `PXL_`,
/// «Captura de pantalla», la fecha y la hora, un número de serie, `-1024x768`,
/// `@2x`, `-scaled`, «copia»—. Si estaba entero en minúsculas, con la
/// primera letra en mayúscula.
///
/// `mapa_imperio-romano_02.jpg` es «Mapa imperio romano»; `colon_1492.png`,
/// «Colon 1492» (un año se queda). `null` si no queda nada que diga algo:
/// `IMG_20231014_101530.jpg`.
String? imageTitleFromFileName(String path) {
  var name = path.replaceAll(r'\', '/');
  name = name.substring(name.lastIndexOf('/') + 1);
  final query = name.indexOf(RegExp('[?#]'));
  if (query >= 0) name = name.substring(0, query);
  name = _percentDecoded(name);
  for (
    var extension = _extension.firstMatch(name);
    extension != null;
    extension = _extension.firstMatch(name)
  ) {
    name = name.substring(0, extension.start);
  }
  final tokens = [
    for (final token in name.split(_separators))
      if (token.isNotEmpty) token,
  ];
  // Lo de la cámara o el teléfono, adelante; lo de la página o la copia,
  // atrás.
  final lower = [for (final token in tokens) token.toLowerCase()];
  var first = 0;
  while (first < tokens.length && _leadingJunk(lower, first)) {
    first++;
  }
  var last = tokens.length;
  while (last > first && _trailingJunk(lower[last - 1])) {
    last--;
  }
  tokens
    ..removeRange(last, tokens.length)
    ..removeRange(0, first);
  if (!tokens.any(_letter.hasMatch)) return null;
  final title = tokens.join(' ');
  final sentence = title == title.toLowerCase()
      ? '${title[0].toUpperCase()}${title.substring(1)}'
      : title;
  return _capped(sentence);
}

/// Los títulos de [images], las imágenes de una fuente que van a Procesado,
/// por su archivo (`SourceImage.path`): lo que se engancha al triar (F46,
/// decisión E).
///
/// - El nombre con que la ofrece la fuente (`SourceImage.title`: el texto
///   alternativo o el epígrafe que se guardó al bajar la página) es el texto
///   alternativo.
/// - [sourceTitle], el título de la fuente, es el pie de foto de su propio
///   archivo (`SourceImageOrigin.original`): el que la persona le puso a la
///   imagen guardada.
/// - Con [sourceMarkdown], el texto en Markdown de la fuente, el título bajo
///   el que está cada imagen que se bajó de ella (por su
///   `SourceImage.originUrl`) es su título cercano.
///
/// Lineal: el texto se recorre una sola vez para todas.
Map<String, String?> sourceImageTitles(
  List<SourceImage> images, {
  String? sourceTitle,
  String? sourceMarkdown,
}) {
  final nearby = sourceMarkdown == null
      ? const <String, String>{}
      : headingsAboveImages(sourceMarkdown, [
          for (final image in images)
            if (image.originUrl case final url?) url,
        ]);
  return {
    for (final image in images)
      image.path: processedImageTitle(
        ImageTitleClues(
          caption: image.origin == SourceImageOrigin.original
              ? sourceTitle
              : null,
          alt: image.title,
          nearbyHeading: switch (image.originUrl) {
            final url? => nearby[url],
            null => null,
          },
          fileName: image.originUrl ?? image.path,
        ),
      ),
  };
}

/// Bajo qué título de [markdown] está cada una de [urls], las direcciones de
/// imágenes que se bajaron de esa página: el último título antes del primer
/// lugar donde aparece la imagen —`![…](dirección)` o `<img src="…">`—. Las
/// que no aparecen, o no tienen ningún título arriba, no están en el
/// resultado.
///
/// Una imagen se reconoce por su dirección sin el `http`, ni su `#ancla`; si
/// no, por el nombre de su archivo, si en la página hay una sola con ese
/// nombre —la página puede mostrar una versión más chica, con otra
/// dirección—.
///
/// Lineal: un recorrido para los títulos y otro para las imágenes.
Map<String, String> headingsAboveImages(String markdown, List<String> urls) {
  if (urls.isEmpty) return const {};
  final headings = markdownHeadings(markdown);
  if (headings.isEmpty) return const {};
  final byAddress = <String, int>{};
  final byName = <String, int?>{};
  for (final reference in _imageReference.allMatches(markdown)) {
    final url = _decodeAttribute(reference[1] ?? reference[2]!);
    byAddress.putIfAbsent(_addressKey(url), () => reference.start);
    final name = _nameKey(url);
    // Dos imágenes con el mismo nombre: por nombre no se sabe cuál es.
    byName[name] = byName.containsKey(name) ? null : reference.start;
  }
  final starts = [for (final heading in headings) heading.start];
  final titles = <String, String>{};
  for (final url in urls) {
    final at = byAddress[_addressKey(url)] ?? byName[_nameKey(url)];
    if (at == null) continue;
    final above = _countBefore(starts, at);
    if (above > 0) titles[url] = headings[above - 1].title;
  }
  return titles;
}

String? _meaningful(String? candidate) {
  if (candidate == null) return null;
  final text = candidate.replaceAll(_whitespace, ' ').trim();
  if (!_letter.hasMatch(text)) return null;
  if (_address.hasMatch(text)) return null;
  if (_extension.hasMatch(text) && !text.contains(' ')) {
    return imageTitleFromFileName(text);
  }
  if (_filler.contains(headingKey(text))) return null;
  return _capped(text);
}

/// [name] con sus `%20`, `%C3%A9`… escritos como lo que son. Un `%` que no
/// codifica nada queda como está, y lo que no es UTF-8 válido sale como el
/// carácter de reemplazo: un nombre raro no puede dejar una imagen sin
/// título.
String _percentDecoded(String name) {
  if (!_percentByte.hasMatch(name)) return name;
  final bytes = <int>[];
  var plain = 0;
  for (final escape in _percentByte.allMatches(name)) {
    bytes
      ..addAll(utf8.encode(name.substring(plain, escape.start)))
      ..add(int.parse(escape[1]!, radix: 16));
    plain = escape.end;
  }
  bytes.addAll(utf8.encode(name.substring(plain)));
  return utf8.decode(bytes, allowMalformed: true);
}

String _capped(String title) => title.length <= kImageTitleMaxChars
    ? title
    : '${title.substring(0, kImageTitleMaxChars - 1).trimRight()}…';

/// Si el pedazo [index] de [tokens] —en minúsculas— es de lo que la cámara,
/// el teléfono o el programa le ponen adelante al nombre: un código de
/// cámara, un número, o una palabra común («foto», «de», «pantalla») que
/// solo lleva a más de eso —«Foto 2023 10 01» sí, «Foto de mi abuela» no—.
bool _leadingJunk(List<String> tokens, int index) {
  final token = tokens[index];
  if (_devicePrefixes.contains(token) || _junkToken(token)) return true;
  if (!_genericPrefixes.contains(token)) return false;
  return index + 1 == tokens.length || _leadingJunk(tokens, index + 1);
}

/// Si [token] —en minúsculas— es de lo que se le agrega atrás a una copia o
/// a una versión de una página. Un año se queda: «Colón 1492».
bool _trailingJunk(String token) {
  if (_year.hasMatch(token)) return false;
  return _copyWords.contains(token) || _junkToken(token);
}

/// Un pedazo del nombre que no dice nada: un número —una serie, una fecha,
/// una hora—, un código de cámara (`DSC01234`, `P1010123`), un hash, un
/// tamaño (`1024x768`, `@2x`), una versión o la marca de una página editada
/// de WordPress (`e1612345678`).
bool _junkToken(String lower) => _junkPattern.hasMatch(lower);

int _countBefore(List<int> starts, int at) {
  var low = 0;
  var high = starts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (starts[middle] < at) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// La dirección de una imagen, para compararla: sin el esquema, sin el
/// `www.` y sin su `#ancla`.
String _addressKey(String url) {
  var key = url.trim();
  final anchor = key.indexOf('#');
  if (anchor >= 0) key = key.substring(0, anchor);
  return key.replaceFirst(_scheme, '').replaceFirst(_www, '');
}

/// El nombre del archivo de una dirección, sin la consulta.
String _nameKey(String url) {
  var path = _addressKey(url);
  final query = path.indexOf('?');
  if (query >= 0) path = path.substring(0, query);
  return path.substring(path.lastIndexOf('/') + 1).toLowerCase();
}

String _decodeAttribute(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

final _whitespace = RegExp(r'\s+');
final _percentByte = RegExp('%([0-9A-Fa-f]{2})');
final _letter = RegExp(r'\p{L}', unicode: true);
final _address = RegExp(r'^(?:https?://|www\.)', caseSensitive: false);
final _scheme = RegExp('^(?:https?:)?//', caseSensitive: false);
final _www = RegExp(r'^www\.', caseSensitive: false);
final _extension = RegExp(
  r'\.(?:jpe?g|jfif|png|gif|webp|heic|heif|avif|bmp|tiff?|svg)$',
  caseSensitive: false,
);
final _separators = RegExp(r'[\s_\-.+~@]+');
final _year = RegExp(r'^(?:1\d|20)\d{2}$');
final _junkPattern = RegExp(
  r'^(?:\d+|\(\d+\)|(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{8,}'
  r'|\d+x\d+|\d+x|v\d+|e\d{9,}|p\d{7}'
  r'|(?:img|dsc[nf]?|pxl|mvimg|vid|gopr|dji|wa)\d+)$',
);

/// Las imágenes de una página en su texto en Markdown: `![…](dirección)`,
/// con o sin `<…>`, y `<img src="…">`.
final _imageReference = RegExp(
  r'!\[[^\]]*\]\(\s*<?([^\s)>]+)>?[^)]*\)|<img\b[^>]*?\bsrc="([^"]+)"',
  caseSensitive: false,
);

/// Lo que una cámara, un teléfono o un programa le ponen adelante al nombre,
/// y nada más lo usa así.
const _devicePrefixes = {
  'img',
  'dsc',
  'dscn',
  'dscf',
  'dcim',
  'pxl',
  'mvimg',
  'vid',
  'gopr',
  'dji',
  'wp',
  'screenshot',
  'captura',
  'whatsapp',
  'signal',
  'telegram',
};

/// Palabras comunes que también ponen adelante —«Photo 2023-10-01», «Captura
/// de pantalla 2023-10-14 a las 10.15.30», «WhatsApp Image … at …»— y que en
/// otro nombre dicen algo: se sacan solo si lo que sigue también se saca.
const _genericPrefixes = {
  'image',
  'imagen',
  'photo',
  'foto',
  'picture',
  'pic',
  'screen',
  'shot',
  'pantalla',
  'de',
  'a',
  'las',
  'at',
  'um',
  'from',
  'am',
  'pm',
};

/// Lo que se le agrega atrás a una copia o a una versión de la página.
const _copyWords = {
  'copy',
  'copia',
  'final',
  'edited',
  'editado',
  'editada',
  'scaled',
  'thumb',
  'thumbnail',
  'large',
  'medium',
  'small',
  'min',
  'hd',
  'hq',
  'orig',
  'original',
  'retina',
  'web',
  'full',
  'crop',
  'cropped',
  'resized',
};

/// Las palabras que no dicen qué es una imagen, ya como `headingKey`.
const _filler = {
  'image',
  'imagen',
  'img',
  'foto',
  'fotografia',
  'photo',
  'picture',
  'pic',
  'figura',
  'figure',
  'ilustracion',
  'illustration',
  'grafico',
  'chart',
  'captura',
  'screenshot',
  'untitled',
  'sin titulo',
  'placeholder',
  'banner',
  'logo',
  'icon',
  'icono',
  'thumbnail',
};
