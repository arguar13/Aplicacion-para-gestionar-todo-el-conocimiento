import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/archive/page_archiver.dart';
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';

/// Archiva una página incrustando sus imágenes y hojas de estilo como datos,
/// al modo de la extensión [SingleFile](https://github.com/gildas-lormeau/SingleFile).
///
/// Persigue que la página archivada se vea como la original (F39), pero sin
/// ejecutarla: queda afuera todo lo que arma un programa —video, iframes,
/// contenido que aparece con JavaScript—. Lo que sí se conserva, de la
/// página y de sus hojas de estilo:
///
/// - **Todas las hojas, enteras.** Las enlazadas con `<link>` —también las
///   que se cargan como `rel="preload" as="style"`— pasan a ser `<style>` en
///   el mismo lugar del documento, con su `media` (una hoja `print` no se
///   convierte en una que manda en pantalla), y sus `@import` se traen y se
///   ponen donde estaban. Primero las hojas, y con pedidos aparte de los de
///   las fotos: antes compartían el tope, y una página con muchas fotos
///   (Wikipedia, 63) se quedaba sin su `site.styles` —el del cuadro de
///   datos— y sin el resto.
/// - **Las tipografías que la página usa** (ver [_rewriteFontFaces]): una
///   sola fuente por `@font-face`, la mejor que entiende el navegador, y solo
///   si el texto de la página tiene letras de su `unicode-range`.
/// - **Las imágenes de los `style=""`** y las de las hojas, además de las
///   `<img>`; los SVG, los AVIF, los BMP y los íconos.
/// - **El `<base href>`** de la página: las direcciones se resuelven contra
///   él, como las resolvería el navegador.
/// - Sin la política de contenido (`Content-Security-Policy`) que declare la
///   página: bloquearía el CSS y las fotos ahora incrustados.
///
/// **De cada foto, una: la de verdad (F36).** Se guarda la que nombra la
/// carga perezosa (`data-src` y parecidos) o la mejor de su `srcset`, y se le
/// sacan las alternativas. Antes se guardaba solo el `src`: en muchas páginas
/// es un cuadradito transparente que un programa cambia por la foto, y donde
/// había `srcset`, el navegador del teléfono elegía de ahí una que no se
/// había guardado. En los dos casos la página archivada salía sin fotos.
///
/// **Liviano a propósito (F21).** Archivar la página de vaticannews costaba
/// 335 descargas y 13,8 MB —tipografías de armenio, canarés, malayalam, en
/// `.eot` y `.ttf` cada una, 134 de ellas 404— para un artículo de 1,5 KB:
/// once de los doce segundos que tardaba en quedar lista. Por eso:
///
/// - **Tipografías con tope.** Una por `@font-face`, solo las que la página
///   usa, y no más de [_maxFonts] ni de [_maxFontBytes] en total: las que no
///   entran se quitan, en vez de dejarlas apuntando afuera —la página
///   archivada saldría a buscarlas a internet cada vez que se abre—.
/// - **Cada recurso se pide una vez**, aunque lo nombren varias hojas.
/// - **Tope de pedidos y de tiempo.** Pasado cualquiera de los dos, lo que
///   falta se deja apuntando al original: el artículo ya quedó guardado
///   aparte, y el archivado es un extra que no puede frenar la cola.
class HtmlPageArchiver implements PageArchiver {
  const HtmlPageArchiver({
    required ResourceFetcher fetcher,
    int maxResourceBytes = _defaultMaxResourceBytes,
    int maxTotalBytes = _defaultMaxTotalBytes,
    int maxRequests = _defaultMaxRequests,
    int maxStyleRequests = _defaultMaxStyleRequests,
    Duration timeBudget = _defaultTimeBudget,
  }) : _fetcher = fetcher,
       _maxResourceBytes = maxResourceBytes,
       _maxTotalBytes = maxTotalBytes,
       _maxRequests = maxRequests,
       _maxStyleRequests = maxStyleRequests,
       _timeBudget = timeBudget;

  final ResourceFetcher _fetcher;
  final int _maxResourceBytes;
  final int _maxTotalBytes;
  final int _maxRequests;
  final int _maxStyleRequests;
  final Duration _timeBudget;

  /// Cuántas fotos se piden, como mucho, para archivar una página. Una página
  /// de lectura normal tiene una docena; más que esto es decoración.
  static const _defaultMaxRequests = 60;

  /// Cuántos pedidos tienen las hojas de estilo, lo que importan y lo que
  /// nombran —íconos, fondos, tipografías—, como mucho. Aparte de las fotos
  /// (F39): sin esto, las fotos se comían el tope y las hojas quedaban sin
  /// guardar.
  static const _defaultMaxStyleRequests = 60;

  /// Cuánto puede tardar el archivado entero. Pasado esto se deja de pedir,
  /// y lo que estaba en camino se abandona.
  static const _defaultTimeBudget = Duration(seconds: 20);

  /// Cuántas tipografías se incrustan, como mucho, y cuánto pueden pesar
  /// todas juntas (F39): las que la página usa, no las 134 del alfabeto de
  /// cada idioma (F21).
  static const _maxFonts = 12;
  static const _maxFontBytes = 6 * 1024 * 1024;

  /// Cuántas hojas se anidan con `@import`: más que esto es un bucle.
  static const _maxImportDepth = 3;

  static final _fontFacePattern = RegExp(r'@font-face\s*\{[^}]*\}');

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

  /// `@import url(x.css) media;` o `@import "x.css" media;`.
  static final _cssImportPattern = RegExp(
    r'''@import\s+(?:url\(\s*(['"]?)([^'")]+)\1\s*\)|(['"])([^'"]+)\3)\s*([^;]*);''',
  );

  @override
  Future<Uint8List?> archive(String html, {required Uri baseUri}) async {
    try {
      final document = html_parser.parse(html);
      _declareUtf8(document);
      _dropContentSecurityPolicy(document);
      // Las direcciones de la página se resuelven contra su `<base href>`,
      // si lo tiene, como lo haría el navegador.
      final base = _baseOf(document, baseUri);
      final budget = _Budget(
        bytes: _maxTotalBytes,
        requests: _maxRequests,
        styleRequests: _maxStyleRequests,
        fontBytes: _maxFontBytes,
        fonts: _maxFonts,
        time: _timeBudget,
      );
      final page = _Page(document, _lettersOf(document));

      // Las hojas de estilo primero (F39): son lo que hace que la página se
      // vea como era, y no pueden quedar afuera porque las fotos llegaron
      // antes. Los `<style>` de la página antes que las hojas enlazadas: las
      // hojas se convierten en `<style>` ya incrustados, y recorrerlos de
      // nuevo era buscar `url(...)` entre megas de datos que ya no hacía
      // falta tocar.
      await _embedInlineStyles(
        document,
        baseUri: base,
        budget: budget,
        page: page,
      );
      await _embedLinkedStylesheets(
        document,
        baseUri: base,
        budget: budget,
        page: page,
      );
      await _embedStyleAttributes(document, baseUri: base, budget: budget);
      await _embedImages(document, baseUri: base, budget: budget);

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

  /// El archivo se escribe en UTF-8, y tiene que decirlo (F22).
  ///
  /// La página llega ya convertida a texto con la codificación que declaraba
  /// —ver `decodeHtmlBytes`—, y se guarda en UTF-8. Si conservara su
  /// `<meta charset="windows-1252">`, el navegador que abra el archivo
  /// leería esos bytes UTF-8 como Windows-1252 y cada tilde saldría como dos
  /// caracteres rotos ("aÃ±o").
  void _declareUtf8(Document document) {
    for (final meta in document.querySelectorAll('meta')) {
      final httpEquiv = meta.attributes['http-equiv']?.trim().toLowerCase();
      if (meta.attributes.containsKey('charset') ||
          httpEquiv == 'content-type') {
        meta.remove();
      }
    }
    document.head?.nodes.insert(
      0,
      Element.tag('meta')..attributes['charset'] = 'utf-8',
    );
  }

  /// La política de contenido que declara una página prohíbe justo lo que
  /// este archivo es: estilos en línea y datos incrustados (F39).
  void _dropContentSecurityPolicy(Document document) {
    for (final meta in document.querySelectorAll('meta')) {
      final httpEquiv = meta.attributes['http-equiv']?.trim().toLowerCase();
      if (httpEquiv == 'content-security-policy') meta.remove();
    }
  }

  /// Contra qué se resuelven las direcciones de la página: su `<base href>`,
  /// si tiene uno válido, o [pageUri].
  Uri _baseOf(Document document, Uri pageUri) {
    final href = document.querySelector('base[href]')?.attributes['href'];
    if (href == null || href.trim().isEmpty) return pageUri;
    return _resolve(pageUri, href.trim()) ?? pageUri;
  }

  /// Los caracteres que tiene el texto de la página, ordenados: lo que decide
  /// qué tipografías se usan de verdad (ver [_rewriteFontFaces]).
  List<int> _lettersOf(Document document) {
    final letters = <int>{};
    void collect(Node node) {
      for (final child in node.nodes) {
        if (child is Text) {
          letters.addAll(child.data.runes);
        } else if (child is Element &&
            child.localName != 'script' &&
            child.localName != 'style') {
          collect(child);
        }
      }
    }

    final body = document.body;
    if (body != null) collect(body);
    return letters.toList()..sort();
  }

  Future<void> _embedImages(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    await _forEachConcurrently(document.querySelectorAll('img'), (img) async {
      // La foto de verdad, no el cuadradito de una carga perezosa ni el
      // `src` chico al que un `srcset` le gana —ver `bestImageSource`—.
      final source = bestImageSource(img, size: ImageSize.screen);
      if (source == null) return;

      final resolved = _resolve(baseUri, source);
      if (resolved == null) return;

      // Guardada o no, queda sola y completa: lo que no se pudo guardar
      // apunta a la foto de verdad, y se ve si hay conexión.
      final dataUri = await _fetchAsDataUri(resolved, budget: budget);
      settleImage(img, dataUri ?? resolved.toString());
    });
  }

  Future<void> _embedLinkedStylesheets(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
    required _Page page,
  }) async {
    // Las que se cargan después con un programa —`rel="preload"
    // as="style"` con un `onload` que las prende— también son hojas de la
    // página: el programa ya no corre.
    await _forEachConcurrently(
      document.querySelectorAll(
        'link[rel="stylesheet"], link[rel="preload"][as="style"]',
      ),
      (link) async {
        final href = link.attributes['href'];
        if (href == null || href.isEmpty) return;

        final resolved = _resolve(baseUri, href);
        if (resolved == null) return;

        final bytes = await budget.fetch(
          resolved,
          _fetcher,
          pool: _Pool.styles,
        );
        if (bytes == null || !budget.spend(bytes.length)) return;

        // Las referencias relativas de la hoja se resuelven contra la
        // propia hoja, no contra la página: un `url(../fuentes/icono.woff)`
        // en `/css/tema.css` apunta a `/fuentes/icono.woff`, no a donde
        // esté la página que la enlazó.
        final css = utf8.decode(bytes, allowMalformed: true);
        final rewritten = await _rewriteCss(
          css,
          baseUri: resolved,
          budget: budget,
          page: page,
        );

        final style = Element.tag('style')..text = rewritten;
        // Una hoja `media="print"` no manda en la pantalla: sin esto, al
        // volverse `<style>` mandaría siempre (F39).
        final media = link.attributes['media']?.trim();
        if (media != null && media.isNotEmpty && media != 'all') {
          style.attributes['media'] = media;
        }
        link.replaceWith(style);
      },
    );
  }

  Future<void> _embedInlineStyles(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
    required _Page page,
  }) async {
    await _forEachConcurrently(document.querySelectorAll('style'), (
      style,
    ) async {
      style.text = await _rewriteCss(
        style.text,
        baseUri: baseUri,
        budget: budget,
        page: page,
      );
    });
  }

  /// Las imágenes de fondo de los `style=""` (F39): un `<div
  /// style="background-image:url(...)">` es la foto principal de muchas
  /// portadas.
  Future<void> _embedStyleAttributes(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    await _forEachConcurrently(document.querySelectorAll('[style*="url("]'), (
      element,
    ) async {
      final style = element.attributes['style'];
      if (style == null) return;
      element.attributes['style'] = await _rewriteCssUrls(
        style,
        baseUri: baseUri,
        budget: budget,
        pool: _Pool.images,
      );
    });
  }

  /// Deja [original] listo para vivir adentro de la página: sus `@import`
  /// puestos, sus tipografías elegidas y cada `url(...)` incrustado.
  Future<String> _rewriteCss(
    String original, {
    required Uri baseUri,
    required _Budget budget,
    required _Page page,
    int depth = 0,
  }) async {
    var css = await _inlineImports(
      original,
      baseUri: baseUri,
      budget: budget,
      page: page,
      depth: depth,
    );
    css = await _rewriteFontFaces(
      css,
      baseUri: baseUri,
      budget: budget,
      page: page,
    );
    return _rewriteCssUrls(
      css,
      baseUri: baseUri,
      budget: budget,
      pool: _Pool.styles,
      document: page.document,
    );
  }

  /// Cada `@import` de [css] reemplazado por la hoja que trae, en el mismo
  /// lugar —lo que importa va donde está el `@import`, y el orden manda en
  /// la cascada—. Con una condición de `media`, la hoja va dentro de un
  /// `@media`. El que no se pudo traer queda con su dirección completa: sin
  /// esto, dentro de la página se resolvería contra la página, no contra la
  /// hoja.
  Future<String> _inlineImports(
    String css, {
    required Uri baseUri,
    required _Budget budget,
    required _Page page,
    required int depth,
  }) async {
    final imports = _cssImportPattern.allMatches(css).toList();
    if (imports.isEmpty) return css;

    final replacements = <String, String>{};
    await _forEachConcurrently(imports, (match) async {
      final reference = (match.group(2) ?? match.group(4))!.trim();
      final media = match.group(5)!.trim();
      final key = match.group(0)!;
      final resolved = _resolve(baseUri, reference);
      if (resolved == null) return;

      String? imported;
      if (depth < _maxImportDepth) {
        final bytes = await budget.fetch(
          resolved,
          _fetcher,
          pool: _Pool.styles,
        );
        if (bytes != null && budget.spend(bytes.length)) {
          imported = await _rewriteCss(
            utf8.decode(bytes, allowMalformed: true),
            baseUri: resolved,
            budget: budget,
            page: page,
            depth: depth + 1,
          );
        }
      }
      replacements[key] = imported == null
          ? "@import url('$resolved')${media.isEmpty ? '' : ' $media'};"
          : media.isEmpty
          ? imported
          : '@media $media{$imported}';
    });

    return css.replaceAllMapped(
      _cssImportPattern,
      (match) => replacements[match.group(0)!] ?? match.group(0)!,
    );
  }

  /// Las `@font-face` de [css] que la página usa, cada una con una sola
  /// fuente incrustada (F39); las demás, quitadas.
  ///
  /// Una tipografía que la página no usa no se baja: tiene un `unicode-range`
  /// con letras que el texto no tiene (el navegador tampoco la bajaría). De
  /// las fuentes que ofrece una regla se elige la mejor que entiende el
  /// navegador —woff2, woff, ttf, otf; `.eot` y SVG, no—. Y entran hasta el
  /// tope de cantidad y de peso: la que no entra se quita, y la página la
  /// reemplaza por la de reserva, en vez de salir a buscarla a internet
  /// cada vez que se abre.
  Future<String> _rewriteFontFaces(
    String css, {
    required Uri baseUri,
    required _Budget budget,
    required _Page page,
  }) async {
    final faces = _fontFacePattern.allMatches(css).toList();
    if (faces.isEmpty) return css;

    final replacements = <int, String>{};
    await _forEachConcurrently(faces.indexed, (entry) async {
      final (index, match) = entry;
      replacements[index] = await _fontFaceFor(
        match.group(0)!,
        baseUri: baseUri,
        budget: budget,
        page: page,
      );
    });

    var index = 0;
    return css.replaceAllMapped(
      _fontFacePattern,
      (_) => replacements[index++] ?? '',
    );
  }

  static final _srcPattern = RegExp(r'src\s*:([^;}]*)', caseSensitive: false);
  static final _srcEntryPattern = RegExp(
    r'''url\(\s*(['"]?)([^'")]+)\1\s*\)(?:\s*format\(\s*['"]?([^'")]+)['"]?\s*\))?''',
    caseSensitive: false,
  );
  static final _unicodeRangePattern = RegExp(
    r'unicode-range\s*:([^;}]*)',
    caseSensitive: false,
  );

  Future<String> _fontFaceFor(
    String face, {
    required Uri baseUri,
    required _Budget budget,
    required _Page page,
  }) async {
    final src = _srcPattern.firstMatch(face);
    // Sin fuente que bajar —un `local()`—, o ya incrustada: tal cual.
    if (src == null || src.group(1)!.contains('data:')) return face;
    final entries = _srcEntryPattern.allMatches(src.group(1)!).toList();
    if (entries.isEmpty) return face;

    final range = _unicodeRangePattern.firstMatch(face)?.group(1);
    if (range != null && !_rangeHasLetters(range, page.letters)) return '';

    ({String url, String format, int rank})? best;
    for (final entry in entries) {
      final url = entry.group(2)!.trim();
      final format = _fontFormatOf(url, entry.group(3));
      final rank = _fontRank[format];
      if (rank == null) continue;
      if (best == null || rank < best.rank) {
        best = (url: url, format: format, rank: rank);
      }
    }
    if (best == null) return '';

    final resolved = _resolve(baseUri, best.url);
    if (resolved == null || !budget.takeFont()) return '';
    final bytes = await budget.fetch(resolved, _fetcher, pool: _Pool.styles);
    if (bytes == null ||
        bytes.length > _maxResourceBytes ||
        !budget.spendFont(bytes.length) ||
        !budget.spend(bytes.length)) {
      return '';
    }
    final mime = _mimeTypeOf(bytes);
    if (mime == null || !mime.startsWith('font/')) return '';

    final data =
        "url('data:$mime;base64,${base64Encode(bytes)}') "
        "format('${best.format}')";
    return face.replaceFirst(_srcPattern, 'src:$data');
  }

  /// Qué tan buena es cada fuente para un navegador de hoy: menos, mejor.
  static const _fontRank = {
    'woff2': 0,
    'woff': 1,
    'truetype': 2,
    'opentype': 3,
  };

  /// El formato de una fuente: el que dice `format(...)` o, sin él, el de la
  /// extensión de su dirección.
  String _fontFormatOf(String url, String? declared) {
    final format = declared?.trim().toLowerCase();
    if (format != null && format.isNotEmpty) {
      return switch (format) {
        'ttf' => 'truetype',
        'otf' => 'opentype',
        _ => format,
      };
    }
    final path = url.split('?').first.split('#').first.toLowerCase();
    if (path.endsWith('.woff2')) return 'woff2';
    if (path.endsWith('.woff')) return 'woff';
    if (path.endsWith('.ttf')) return 'truetype';
    if (path.endsWith('.otf')) return 'opentype';
    return 'unknown';
  }

  /// Si alguna de las letras ordenadas [letters] cae en el `unicode-range`
  /// [range] (`U+0000-00FF, U+0131, U+4??`).
  bool _rangeHasLetters(String range, List<int> letters) {
    for (final part in range.split(',')) {
      final text = part.trim().toUpperCase();
      if (!text.startsWith('U+')) continue;
      final body = text.substring(2);
      int? low;
      int? high;
      if (body.contains('?')) {
        low = int.tryParse(body.replaceAll('?', '0'), radix: 16);
        high = int.tryParse(body.replaceAll('?', 'F'), radix: 16);
      } else if (body.contains('-')) {
        final ends = body.split('-');
        low = int.tryParse(ends[0], radix: 16);
        high = int.tryParse(ends[1], radix: 16);
      } else {
        low = high = int.tryParse(body, radix: 16);
      }
      // Un rango que no se entiende se da por usado: es más seguro bajarla.
      if (low == null || high == null) return true;
      if (_hasLetterBetween(letters, low, high)) return true;
    }
    return false;
  }

  bool _hasLetterBetween(List<int> sorted, int low, int high) {
    var from = 0;
    var to = sorted.length;
    while (from < to) {
      final middle = (from + to) >> 1;
      if (sorted[middle] < low) {
        from = middle + 1;
      } else {
        to = middle;
      }
    }
    return from < sorted.length && sorted[from] <= high;
  }

  /// Reemplaza cada `url(...)` de [original] por el dato incrustado que se
  /// pueda.
  ///
  /// Primero se resuelven todas las referencias —cada una que no sea
  /// repetida, a la vez que las demás— y recién después se reescribe el
  /// texto en un solo paso. Reemplazar sobre índices que van cambiando de
  /// longitud a medida que se recorre el texto es la forma clásica de
  /// terminar escribiendo en el lugar equivocado — y además hace falta:
  /// `String.replaceAllMapped` no acepta una función asíncrona, así que no
  /// hay manera de resolver y reemplazar en el mismo paso.
  ///
  /// La que no se pudo guardar queda con su dirección completa (F39): una
  /// relativa, dentro de un `<style>` de la página, se resolvería contra la
  /// página y no contra la hoja de donde salió.
  Future<String> _rewriteCssUrls(
    String original, {
    required Uri baseUri,
    required _Budget budget,
    required _Pool pool,
    Document? document,
  }) async {
    final css = original;

    // Un `Set`, no una lista: una hoja de estilo repite la misma URL de
    // ícono muchas veces, y traerla una sola vez por referencia distinta
    // —no por aparición— es lo que evita pedirla de más.
    final rawUrls = _cssUrlPattern
        .allMatches(css)
        .map((match) => match.group(2)!.trim())
        .where((url) => !url.startsWith('data:') && !url.startsWith('#'))
        .toSet();
    // Con la página a mano, solo se traen las de las reglas que le tocan a
    // algún elemento de ella (F39): la hoja de íconos de Wikipedia nombra
    // 205, la página usa media docena, y el tope de pedidos se las comía en
    // el orden en que venían.
    final needed = document == null
        ? rawUrls
        : _urlsOfRulesInUse(css, document).intersection(rawUrls);

    final replacements = <String, String>{};
    await _forEachConcurrently(rawUrls, (rawUrl) async {
      final resolved = _resolve(baseUri, rawUrl);
      if (resolved == null) return;

      final dataUri = needed.contains(rawUrl)
          ? await _fetchAsDataUri(resolved, budget: budget, pool: pool)
          : null;
      replacements[rawUrl] = dataUri ?? resolved.toString();
    });

    if (replacements.isEmpty) return css;

    return css.replaceAllMapped(_cssUrlPattern, (match) {
      final replacement = replacements[match.group(2)!.trim()];
      return replacement == null ? match.group(0)! : "url('$replacement')";
    });
  }

  static final _cssCommentPattern = RegExp(r'/\*.*?\*/', dotAll: true);
  static final _cssRulePattern = RegExp(r'([^{}]+)\{([^{}]*url\([^{}]*)\}');

  /// Lo que no se puede mirar en un documento quieto: el puntero, el foco, los
  /// pseudoelementos. Una regla de `a:hover` le toca a la página aunque
  /// nadie la esté tocando.
  static final _cssDynamicPseudo = RegExp(
    '::?(?:hover|focus|focus-visible|focus-within|active|visited|link|'
    'any-link|target|before|after|first-line|first-letter|placeholder|'
    r'selection|marker|backdrop|-[\w-]+)(?![\w-])',
    caseSensitive: false,
  );

  /// Las direcciones de `url(...)` de las reglas de [css] cuyo selector toca
  /// a algún elemento de [document]. Un selector que no se entiende cuenta
  /// como usado: más vale traer de más que dejar sin guardar.
  Set<String> _urlsOfRulesInUse(String css, Document document) {
    final used = <String>{};
    final verdicts = <String, bool>{};
    bool inUse(String selector) => verdicts.putIfAbsent(selector, () {
      final stripped = selector.replaceAll(_cssDynamicPseudo, '').trim();
      if (stripped.isEmpty) return true;
      try {
        return document.querySelector(stripped) != null;
        // El motor de selectores no entiende todo lo de CSS moderno.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        return true;
      }
    });

    final plain = css.replaceAll(_cssCommentPattern, '');
    for (final rule in _cssRulePattern.allMatches(plain)) {
      final selector = rule.group(1)!.trim();
      // El preámbulo de un `@media` o `@supports` que llegó hasta acá no es
      // un selector: la regla de adentro ya se mira por su cuenta.
      if (selector.startsWith('@')) continue;
      if (!inUse(selector)) continue;
      for (final url in _cssUrlPattern.allMatches(rule.group(2)!)) {
        used.add(url.group(2)!.trim());
      }
    }
    return used;
  }

  Future<String?> _fetchAsDataUri(
    Uri url, {
    required _Budget budget,
    _Pool pool = _Pool.images,
  }) async {
    final bytes = await budget.fetch(url, _fetcher, pool: pool);
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

/// Cuántas descargas de recursos —imágenes, hojas de estilo, fuentes
/// dentro de un `url(...)` de CSS— corren al mismo tiempo, como mucho.
///
/// Sin este tope, archivar una página con muchas imágenes las pedía de a
/// una: con una docena de recursos y un rato de ida y vuelta por cada uno,
/// eso solo alcanzaba para sumar segundos —a veces minutos— al momento en
/// que el elemento pasaba a "listo". Un número muy alto tampoco ayuda: la
/// mayoría de los servidores (y el propio cliente HTTP) empiezan a
/// encolar o a cortar conexiones mucho antes de las decenas.
const _archiveConcurrency = 6;

/// Corre [action] sobre cada elemento de [items], sin más de
/// [_archiveConcurrency] llamadas en vuelo al mismo tiempo.
///
/// Un puñado de "trabajadores" comparten el mismo iterador: en cuanto uno
/// termina su recurso, toma el siguiente que quede, en vez de que cada
/// recurso espere a que termine el anterior. `moveNext()`/`current` son
/// síncronos, así que dos trabajadores nunca pueden tomar el mismo
/// elemento a la vez, aunque corran "a la vez" en el sentido de Dart —un
/// único hilo que va turnándose entre `Future`s en cada `await`—.
Future<void> _forEachConcurrently<T>(
  Iterable<T> items,
  Future<void> Function(T item) action, {
  int concurrency = _archiveConcurrency,
}) async {
  final iterator = items.iterator;

  Future<void> worker() async {
    while (iterator.moveNext()) {
      await action(iterator.current);
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
}

/// La página que se archiva, como la miran las hojas de estilo: su documento
/// —para saber qué reglas le tocan— y las letras de su texto.
class _Page {
  _Page(this.document, this.letters);

  final Document document;
  final List<int> letters;
}

/// De dónde sale un pedido: las fotos y las hojas de estilo tienen topes de
/// pedidos aparte (F39).
enum _Pool { images, styles }

/// Cuánto queda de los topes —bytes, pedidos, tipografías, tiempo— y lo que
/// ya se pidió.
///
/// Nace y muere en cada llamada a [PageArchiver.archive]: es mutable a
/// propósito, pero nunca se comparte entre el archivado de dos páginas.
class _Budget {
  _Budget({
    required int bytes,
    required int requests,
    required int styleRequests,
    required int fontBytes,
    required int fonts,
    required Duration time,
  }) : _bytes = bytes,
       _requests = {_Pool.images: requests, _Pool.styles: styleRequests},
       _fontBytes = fontBytes,
       _fonts = fonts,
       _time = time;

  int _bytes;
  final Map<_Pool, int> _requests;
  int _fontBytes;
  int _fonts;
  final Duration _time;
  final _clock = Stopwatch()..start();

  /// Lo que ya se pidió, por URL: un recurso que nombran dos hojas de estilo
  /// se pide una vez, y los dos esperan la misma respuesta.
  final _fetched = <Uri, Future<Uint8List?>>{};

  /// Si hay lugar para [bytes] más, los descuenta y devuelve `true`. Si no,
  /// no toca nada — quien pidió se queda sin incrustar ese recurso, pero
  /// nada más se rompe.
  bool spend(int bytes) {
    if (bytes > _bytes) return false;
    _bytes -= bytes;
    return true;
  }

  /// Lo mismo, del tope que tienen las tipografías.
  bool spendFont(int bytes) {
    if (bytes > _fontBytes) return false;
    _fontBytes -= bytes;
    return true;
  }

  /// Si todavía entra una tipografía más, la cuenta.
  bool takeFont() {
    if (_fonts <= 0) return false;
    _fonts--;
    return true;
  }

  /// Trae [url] con [fetcher], una sola vez por archivado. `null` —sin
  /// pedirlo— si ya no quedan pedidos de [pool] o tiempo; y lo que no llega
  /// antes de que se acabe el tiempo se abandona, también como `null`.
  Future<Uint8List?> fetch(
    Uri url,
    ResourceFetcher fetcher, {
    _Pool pool = _Pool.images,
  }) {
    final known = _fetched[url];
    if (known != null) return known;

    final remaining = _time - _clock.elapsed;
    final left = _requests[pool]!;
    if (left <= 0 || remaining <= Duration.zero) {
      return Future<Uint8List?>.value();
    }
    _requests[pool] = left - 1;
    return _fetched[url] = fetcher
        .fetchBytes(url)
        .timeout(remaining, onTimeout: () => null);
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

  if (_hasAscii(bytes, 'BM') &&
      bytes.length > 14 &&
      bytes.sublist(6, 10).every((byte) => byte == 0)) {
    return 'image/bmp';
  }
  if (_hasBytes(bytes, const [0x00, 0x00, 0x01, 0x00])) return 'image/x-icon';
  if (_isAvif(bytes)) return 'image/avif';
  if (_isSvg(bytes)) return 'image/svg+xml';

  if (_hasAscii(bytes, 'wOFF')) return 'font/woff';
  if (_hasAscii(bytes, 'wOF2')) return 'font/woff2';
  if (_hasAscii(bytes, 'OTTO')) return 'font/otf';
  if (_hasAscii(bytes, 'true') ||
      _hasBytes(bytes, const [0x00, 0x01, 0x00, 0x00])) {
    return 'font/ttf';
  }

  return null;
}

/// Un SVG es texto: empieza —tras un BOM, espacios o la declaración XML— con
/// `<svg`.
bool _isSvg(Uint8List bytes) {
  final head = utf8
      .decode(
        bytes.sublist(0, bytes.length < 1024 ? bytes.length : 1024),
        allowMalformed: true,
      )
      .replaceFirst('﻿', '')
      .trimLeft();
  return head.startsWith('<svg') ||
      (head.startsWith('<?xml') ||
              head.startsWith('<!--') ||
              head.startsWith('<!DOCTYPE svg')) &&
          head.contains('<svg');
}

/// Un AVIF es un contenedor `ftyp` con la marca `avif`.
bool _isAvif(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp' &&
    String.fromCharCodes(bytes.sublist(8, 12)).startsWith('avi');

bool _hasAscii(Uint8List bytes, String text) =>
    _hasBytes(bytes, ascii.encode(text));

bool _hasBytes(Uint8List bytes, List<int> expected) {
  if (bytes.length < expected.length) return false;

  for (var i = 0; i < expected.length; i++) {
    if (bytes[i] != expected[i]) return false;
  }
  return true;
}
