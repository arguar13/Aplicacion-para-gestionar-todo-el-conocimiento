import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/archive/page_archiver.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';

/// Archiva una página incrustando sus imágenes y hojas de estilo como datos,
/// al modo de la extensión [SingleFile](https://github.com/gildas-lormeau/SingleFile).
///
/// Deliberadamente **no** persigue la fidelidad completa de esa extensión.
/// Esta app archiva para poder *leer* después, no para reproducir la página
/// al pixel: quedan afuera el `srcset` de imágenes responsivas (el `src`
/// ya incrustado sirve de resguardo si el navegador no puede usar ninguna
/// alternativa), los `@import` entre hojas de estilo, y todo lo que no sea
/// HTML+CSS estático —video, iframes, contenido armado por JavaScript—.
/// Perseguir eso multiplicaría la complejidad para un beneficio que no le
/// sirve a una app de lectura.
class HtmlPageArchiver implements PageArchiver {
  const HtmlPageArchiver({
    required ResourceFetcher fetcher,
    int maxResourceBytes = _defaultMaxResourceBytes,
    int maxTotalBytes = _defaultMaxTotalBytes,
  }) : _fetcher = fetcher,
       _maxResourceBytes = maxResourceBytes,
       _maxTotalBytes = maxTotalBytes;

  final ResourceFetcher _fetcher;
  final int _maxResourceBytes;
  final int _maxTotalBytes;

  /// Lo más grande que se incrusta de un solo recurso, por defecto.
  ///
  /// Una imagen o una fuente de una página de lectura normal no se acerca a
  /// esto; algo que sí lo supera —una fuente completa de un alfabeto CJK, un
  /// video disfrazado de imagen— no vale lo que cuesta guardarlo, y se deja
  /// apuntando al original.
  static const _defaultMaxResourceBytes = 5 * 1024 * 1024;

  /// Lo que puede pesar el archivo entero, por defecto.
  ///
  /// Una docena de fotos e íconos entra cómoda. Más que eso, lo que importa
  /// de verdad —el texto— ya quedó guardado aparte, en la forma de
  /// Markdown, y seguir incrustando solo infla el almacenamiento del
  /// dispositivo sin agregarle nada a lo que se puede buscar o leer.
  static const _defaultMaxTotalBytes = 25 * 1024 * 1024;

  static final _cssUrlPattern = RegExp(r'''url\(\s*(['"]?)([^'")]+)\1\s*\)''');

  @override
  Future<Uint8List?> archive(String html, {required Uri baseUri}) async {
    try {
      final document = html_parser.parse(html);
      final budget = _Budget(_maxTotalBytes);

      await _embedImages(document, baseUri: baseUri, budget: budget);
      await _embedLinkedStylesheets(document, baseUri: baseUri, budget: budget);
      await _embedInlineStyles(document, baseUri: baseUri, budget: budget);

      return Uint8List.fromList(utf8.encode(document.outerHtml));
      // Una página ajena puede traer cualquier cosa. Nada de lo que salga
      // mal acá puede costarle al usuario el artículo que sí se extrajo:
      // por eso se atrapa cualquier fallo y se responde que no hay nada
      // que archivar, en vez de dejarlo escapar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  Future<void> _embedImages(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    for (final img in document.querySelectorAll('img')) {
      final src = img.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final resolved = _resolve(baseUri, src);
      if (resolved == null) continue;

      final dataUri = await _fetchAsDataUri(resolved, budget: budget);
      if (dataUri != null) img.attributes['src'] = dataUri;
    }
  }

  Future<void> _embedLinkedStylesheets(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    for (final link in document.querySelectorAll('link[rel="stylesheet"]')) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final resolved = _resolve(baseUri, href);
      if (resolved == null) continue;

      final bytes = await _fetcher.fetchBytes(resolved);
      if (bytes == null || !budget.spend(bytes.length)) continue;

      // Las referencias relativas de la hoja se resuelven contra la propia
      // hoja, no contra la página: un `url(../fuentes/icono.woff)` en
      // `/css/tema.css` apunta a `/fuentes/icono.woff`, no a donde esté la
      // página que la enlazó.
      final css = utf8.decode(bytes, allowMalformed: true);
      final rewritten = await _rewriteCssUrls(
        css,
        baseUri: resolved,
        budget: budget,
      );

      link.replaceWith(Element.tag('style')..text = rewritten);
    }
  }

  Future<void> _embedInlineStyles(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    for (final style in document.querySelectorAll('style')) {
      style.text = await _rewriteCssUrls(
        style.text,
        baseUri: baseUri,
        budget: budget,
      );
    }
  }

  /// Reemplaza cada `url(...)` de [css] por el dato incrustado que se pueda.
  ///
  /// Primero se resuelven todas las referencias, de a una, y recién después
  /// se reescribe el texto en un solo paso. Reemplazar sobre índices que van
  /// cambiando de longitud a medida que se recorre el texto es la forma
  /// clásica de terminar escribiendo en el lugar equivocado — y además hace
  /// falta: `String.replaceAllMapped` no acepta una función asíncrona, así
  /// que no hay manera de resolver y reemplazar en el mismo paso.
  Future<String> _rewriteCssUrls(
    String css, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    final replacements = <String, String>{};

    for (final match in _cssUrlPattern.allMatches(css)) {
      final rawUrl = match.group(2)!.trim();
      if (rawUrl.startsWith('data:') || replacements.containsKey(rawUrl)) {
        continue;
      }

      final resolved = _resolve(baseUri, rawUrl);
      if (resolved == null) continue;

      final dataUri = await _fetchAsDataUri(resolved, budget: budget);
      if (dataUri != null) replacements[rawUrl] = dataUri;
    }

    if (replacements.isEmpty) return css;

    return css.replaceAllMapped(_cssUrlPattern, (match) {
      final replacement = replacements[match.group(2)!.trim()];
      return replacement == null ? match.group(0)! : "url('$replacement')";
    });
  }

  Future<String?> _fetchAsDataUri(Uri url, {required _Budget budget}) async {
    final bytes = await _fetcher.fetchBytes(url);
    if (bytes == null || bytes.length > _maxResourceBytes) return null;

    final mimeType = _mimeTypeOf(bytes);
    if (mimeType == null) return null;

    if (!budget.spend(bytes.length)) return null;

    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  /// `null` si la referencia no apunta a algo que valga la pena traer: ya
  /// incrustada, rota, o directamente no es una URL.
  Uri? _resolve(Uri baseUri, String reference) {
    try {
      final resolved = baseUri.resolve(reference);
      if (!resolved.isScheme('http') && !resolved.isScheme('https')) {
        return null;
      }
      return resolved;
    } on FormatException {
      return null;
    }
  }
}

/// Cuánto queda del tope total.
///
/// Nace y muere en cada llamada a [PageArchiver.archive]: es mutable a
/// propósito, pero nunca se comparte entre el archivado de dos páginas.
class _Budget {
  _Budget(this._remaining);

  int _remaining;

  /// Si hay lugar para [bytes] más, los descuenta y devuelve `true`. Si no,
  /// no toca nada — quien pidió se queda sin incrustar ese recurso, pero
  /// nada más se rompe.
  bool spend(int bytes) {
    if (bytes > _remaining) return false;
    _remaining -= bytes;
    return true;
  }
}

/// A qué tipo de recurso corresponden estos bytes, para la cabecera del
/// dato incrustado. `null` si no se reconoce ninguno — incrustar algo sin
/// saber qué es no sirve de nada, y es más seguro dejarlo afuera.
///
/// Aparte de [FileFormat] porque este archivador reconoce cosas que
/// [FileFormat] no tiene por qué saber leer nunca: una fuente web no es un
/// formato que la app vaya a abrir ni a extraerle texto, así que ensuciar
/// ese enum compartido con `woff`/`woff2`/`ttf`/`otf` no tendría sentido
/// para el resto de la app.
String? _mimeTypeOf(Uint8List bytes) {
  final byFileFormat = switch (detectFileFormat(bytes)) {
    FileFormat.png => 'image/png',
    FileFormat.jpeg => 'image/jpeg',
    FileFormat.gif => 'image/gif',
    FileFormat.webp => 'image/webp',
    _ => null,
  };
  if (byFileFormat != null) return byFileFormat;

  if (_hasAscii(bytes, 'wOFF')) return 'font/woff';
  if (_hasAscii(bytes, 'wOF2')) return 'font/woff2';
  if (_hasAscii(bytes, 'OTTO')) return 'font/otf';
  if (_hasAscii(bytes, 'true') ||
      _hasBytes(bytes, const [0x00, 0x01, 0x00, 0x00])) {
    return 'font/ttf';
  }

  return null;
}

bool _hasAscii(Uint8List bytes, String text) =>
    _hasBytes(bytes, ascii.encode(text));

bool _hasBytes(Uint8List bytes, List<int> expected) {
  if (bytes.length < expected.length) return false;

  for (var i = 0; i < expected.length; i++) {
    if (bytes[i] != expected[i]) return false;
  }
  return true;
}
