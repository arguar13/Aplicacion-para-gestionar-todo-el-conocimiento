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
///
/// **Liviano a propósito (F21).** Archivar la página de vaticannews costaba
/// 335 descargas y 13,8 MB —tipografías de armenio, canarés, malayalam, en
/// `.eot` y `.ttf` cada una, 134 de ellas 404— para un artículo de 1,5 KB:
/// once de los doce segundos que tardaba en quedar lista. Por eso:
///
/// - **Sin tipografías.** Se quitan las reglas `@font-face`: no aportan nada
///   para leer, y dejarlas apuntando afuera haría que la página archivada
///   salga a buscarlas a internet cada vez que se abre.
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
    Duration timeBudget = _defaultTimeBudget,
  }) : _fetcher = fetcher,
       _maxResourceBytes = maxResourceBytes,
       _maxTotalBytes = maxTotalBytes,
       _maxRequests = maxRequests,
       _timeBudget = timeBudget;

  final ResourceFetcher _fetcher;
  final int _maxResourceBytes;
  final int _maxTotalBytes;
  final int _maxRequests;
  final Duration _timeBudget;

  /// Cuántos recursos se piden, como mucho, para archivar una página. Una
  /// página de lectura normal tiene una docena de imágenes y un par de hojas
  /// de estilo; más que esto es decoración.
  static const _defaultMaxRequests = 60;

  /// Cuánto puede tardar el archivado entero. Pasado esto se deja de pedir,
  /// y lo que estaba en camino se abandona.
  static const _defaultTimeBudget = Duration(seconds: 20);

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

  @override
  Future<Uint8List?> archive(String html, {required Uri baseUri}) async {
    try {
      final document = html_parser.parse(html);
      final budget = _Budget(
        bytes: _maxTotalBytes,
        requests: _maxRequests,
        time: _timeBudget,
      );

      await _embedImages(document, baseUri: baseUri, budget: budget);
      // Los `<style>` de la página antes que las hojas enlazadas: las hojas
      // se convierten en `<style>` ya incrustados, y recorrerlos de nuevo
      // era buscar `url(...)` entre megas de datos que ya no hacía falta
      // tocar.
      await _embedInlineStyles(document, baseUri: baseUri, budget: budget);
      await _embedLinkedStylesheets(document, baseUri: baseUri, budget: budget);

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
    await _forEachConcurrently(document.querySelectorAll('img'), (img) async {
      final src = img.attributes['src'];
      if (src == null || src.isEmpty) return;

      final resolved = _resolve(baseUri, src);
      if (resolved == null) return;

      final dataUri = await _fetchAsDataUri(resolved, budget: budget);
      if (dataUri != null) img.attributes['src'] = dataUri;
    });
  }

  Future<void> _embedLinkedStylesheets(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    await _forEachConcurrently(
      document.querySelectorAll('link[rel="stylesheet"]'),
      (link) async {
        final href = link.attributes['href'];
        if (href == null || href.isEmpty) return;

        final resolved = _resolve(baseUri, href);
        if (resolved == null) return;

        final bytes = await budget.fetch(resolved, _fetcher);
        if (bytes == null || !budget.spend(bytes.length)) return;

        // Las referencias relativas de la hoja se resuelven contra la
        // propia hoja, no contra la página: un `url(../fuentes/icono.woff)`
        // en `/css/tema.css` apunta a `/fuentes/icono.woff`, no a donde
        // esté la página que la enlazó.
        final css = utf8.decode(bytes, allowMalformed: true);
        final rewritten = await _rewriteCssUrls(
          css,
          baseUri: resolved,
          budget: budget,
        );

        link.replaceWith(Element.tag('style')..text = rewritten);
      },
    );
  }

  Future<void> _embedInlineStyles(
    Document document, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    await _forEachConcurrently(document.querySelectorAll('style'), (
      style,
    ) async {
      style.text = await _rewriteCssUrls(
        style.text,
        baseUri: baseUri,
        budget: budget,
      );
    });
  }

  /// Reemplaza cada `url(...)` de [original] por el dato incrustado que se
  /// pueda, sin las reglas `@font-face`.
  ///
  /// Primero se resuelven todas las referencias —cada una que no sea
  /// repetida, a la vez que las demás— y recién después se reescribe el
  /// texto en un solo paso. Reemplazar sobre índices que van cambiando de
  /// longitud a medida que se recorre el texto es la forma clásica de
  /// terminar escribiendo en el lugar equivocado — y además hace falta:
  /// `String.replaceAllMapped` no acepta una función asíncrona, así que no
  /// hay manera de resolver y reemplazar en el mismo paso.
  Future<String> _rewriteCssUrls(
    String original, {
    required Uri baseUri,
    required _Budget budget,
  }) async {
    // Sin tipografías: ver la documentación de la clase.
    final css = original.replaceAll(_fontFacePattern, '');

    // Un `Set`, no una lista: una hoja de estilo repite la misma URL de
    // ícono muchas veces, y traerla una sola vez por referencia distinta
    // —no por aparición— es lo que evita pedirla de más.
    final rawUrls = _cssUrlPattern
        .allMatches(css)
        .map((match) => match.group(2)!.trim())
        .where((url) => !url.startsWith('data:'))
        .toSet();

    final replacements = <String, String>{};
    await _forEachConcurrently(rawUrls, (rawUrl) async {
      final resolved = _resolve(baseUri, rawUrl);
      if (resolved == null) return;

      final dataUri = await _fetchAsDataUri(resolved, budget: budget);
      if (dataUri != null) replacements[rawUrl] = dataUri;
    });

    if (replacements.isEmpty) return css;

    return css.replaceAllMapped(_cssUrlPattern, (match) {
      final replacement = replacements[match.group(2)!.trim()];
      return replacement == null ? match.group(0)! : "url('$replacement')";
    });
  }

  Future<String?> _fetchAsDataUri(Uri url, {required _Budget budget}) async {
    final bytes = await budget.fetch(url, _fetcher);
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

/// Cuánto queda de los tres topes —bytes, pedidos, tiempo— y lo que ya se
/// pidió.
///
/// Nace y muere en cada llamada a [PageArchiver.archive]: es mutable a
/// propósito, pero nunca se comparte entre el archivado de dos páginas.
class _Budget {
  _Budget({required int bytes, required int requests, required Duration time})
    : _bytes = bytes,
      _requests = requests,
      _time = time;

  int _bytes;
  int _requests;
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

  /// Trae [url] con [fetcher], una sola vez por archivado. `null` —sin
  /// pedirlo— si ya no quedan pedidos o tiempo; y lo que no llega antes de
  /// que se acabe el tiempo se abandona, también como `null`.
  Future<Uint8List?> fetch(Uri url, ResourceFetcher fetcher) {
    final known = _fetched[url];
    if (known != null) return known;

    final remaining = _time - _clock.elapsed;
    if (_requests <= 0 || remaining <= Duration.zero) {
      return Future<Uint8List?>.value();
    }
    _requests--;
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
