// Los identificadores con que se sabe que dos referencias son la misma obra:
// DOI, ISBN, ISSN y enlace.
//
// Importar una bibliografía dos veces no puede duplicarla, y eso depende de
// que «10.1000/XYZ», «doi:10.1000/xyz» y «https://doi.org/10.1000/xyz» sean
// UN texto. Por eso todo identificador se guarda normalizado, y por eso cada
// función devuelve `null` si lo que recibe no es un identificador válido:
// mejor ninguno que uno equivocado con el que después se fusionen dos obras
// distintas.

// ---------------------------------------------------------------------------
// DOI
// ---------------------------------------------------------------------------

final _doiPrefix = RegExp(
  r'^(?:doi:\s*|urn:doi:\s*|https?://(?:dx\.)?doi\.org/|(?:dx\.)?doi\.org/)',
  caseSensitive: false,
);
final _doiShape = RegExp(r'^10\.\d{4,9}/\S+$');

/// El DOI de [raw] en su forma canónica —minúsculas, sin prefijo ni espacios—,
/// o `null` si no es un DOI.
///
/// Acepta el DOI pelado, con `doi:` y como enlace de `doi.org`, con o sin
/// escapes de URL. Un DOI no distingue mayúsculas de minúsculas.
String? normalizeDoi(String raw) {
  var doi = raw.trim().replaceFirst(_doiPrefix, '');
  // Un `%` que no abre un escape (`%zz`) es del DOI y no se decodifica; y un
  // escape que no forma UTF-8 válido tampoco.
  if (doi.contains('%') && !RegExp('%(?![0-9A-Fa-f]{2})').hasMatch(doi)) {
    try {
      doi = Uri.decodeComponent(doi);
    } on FormatException {
      // Sin decodificar.
    }
  }
  // Lo que un texto pone detrás de un DOI —un punto, una coma— no es del DOI.
  doi = doi.trim().replaceAll(RegExp(r'[.,;:]+$'), '').toLowerCase();
  return _doiShape.hasMatch(doi) ? doi : null;
}

// ---------------------------------------------------------------------------
// ISBN
// ---------------------------------------------------------------------------

/// El ISBN de [raw] como ISBN-13, sin guiones, o `null` si no es uno válido.
///
/// Acepta ISBN-10 y ISBN-13, con guiones, espacios o el prefijo «ISBN», y
/// comprueba el dígito de control: un ISBN con un dígito mal escrito no se
/// guarda. Un ISBN-10 se convierte a ISBN-13, así que el mismo libro tiene
/// siempre el mismo texto, lo haya escrito como lo haya escrito. Si hay más de
/// uno en [raw] —tapa dura y tapa blanda—, se toma el primero válido.
String? normalizeIsbn(String raw) {
  final withoutLabel = raw.replaceAll(
    RegExp(r'isbn(?:-1[03])?\s*:?', caseSensitive: false),
    ' ',
  );
  for (final match in RegExp(
    r'[0-9][0-9\- ]{8,16}[0-9Xx]',
  ).allMatches(withoutLabel)) {
    final digits = match.group(0)!.replaceAll(RegExp(r'[\- ]'), '');
    if (digits.length == 13 && _isValidIsbn13(digits)) return digits;
    if (digits.length == 10 && _isValidIsbn10(digits)) {
      return _isbn10To13(digits);
    }
  }
  return null;
}

bool _isValidIsbn10(String isbn) {
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final char = isbn[i];
    final value = (i == 9 && (char == 'X' || char == 'x'))
        ? 10
        : int.tryParse(char);
    if (value == null) return false;
    sum += value * (10 - i);
  }
  return sum % 11 == 0;
}

bool _isValidIsbn13(String isbn) {
  if (!RegExp(r'^\d{13}$').hasMatch(isbn)) return false;
  var sum = 0;
  for (var i = 0; i < 13; i++) {
    sum += int.parse(isbn[i]) * (i.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}

/// El ISBN-13 que le corresponde a un ISBN-10 válido: el prefijo `978`, sus
/// nueve primeros dígitos y un dígito de control nuevo.
String _isbn10To13(String isbn10) {
  final body = '978${isbn10.substring(0, 9)}';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(body[i]) * (i.isEven ? 1 : 3);
  }
  return '$body${(10 - sum % 10) % 10}';
}

// ---------------------------------------------------------------------------
// ISSN
// ---------------------------------------------------------------------------

/// El ISSN de [raw] como `NNNN-NNNC`, o `null` si no es uno válido.
///
/// El dígito de control es un módulo 11 que puede dar `X`.
String? normalizeIssn(String raw) {
  final match = RegExp(r'(\d{4})\s*-?\s*(\d{3}[\dXx])').firstMatch(raw);
  if (match == null) return null;
  final digits = '${match.group(1)}${match.group(2)!.toUpperCase()}';

  var sum = 0;
  for (var i = 0; i < 7; i++) {
    sum += int.parse(digits[i]) * (8 - i);
  }
  final check = (11 - sum % 11) % 11;
  final expected = check == 10 ? 'X' : '$check';
  if (digits[7] != expected) return null;

  return '${digits.substring(0, 4)}-${digits.substring(4)}';
}

// ---------------------------------------------------------------------------
// URL
// ---------------------------------------------------------------------------

/// Los parámetros que solo rastrean de dónde vino un clic: no cambian a qué
/// página se llega.
final _trackingParam = RegExp(
  '^(?:utm_.*|fbclid|gclid|dclid|msclkid|yclid|igshid|mc_cid|mc_eid|_ga|'
  r'_gl|ref_src|ref_url)$',
  caseSensitive: false,
);

/// El enlace de [raw] en una forma que sirve para comparar, o `null` si no es
/// un enlace web.
///
/// Ignora lo que no cambia a qué página se llega: mayúsculas en el esquema y
/// el dominio, el `www.`, el puerto por defecto, la barra final, el
/// fragmento (`#…`) y los parámetros de rastreo, y ordena los que quedan. No
/// es el enlace que se abre —eso es `Source.originUrl`, tal como se guardó—:
/// es la identidad con que se decide que dos enlaces son el mismo.
String? canonicalUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);

  final defaultPort = scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';

  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') path = '';

  final params =
      uri.queryParametersAll.entries
          .where((entry) => !_trackingParam.hasMatch(entry.key))
          .expand(
            (entry) => [for (final value in entry.value) (entry.key, value)],
          )
          .toList()
        ..sort((a, b) {
          final byKey = a.$1.compareTo(b.$1);
          return byKey != 0 ? byKey : a.$2.compareTo(b.$2);
        });
  final query = params.isEmpty
      ? ''
      : '?${params.map((p) => '${Uri.encodeQueryComponent(p.$1)}='
            '${Uri.encodeQueryComponent(p.$2)}').join('&')}';

  return '$scheme://$host$port$path$query';
}
