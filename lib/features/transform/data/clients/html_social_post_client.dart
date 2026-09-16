import 'dart:convert';

import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// [SocialPostClient] que raspa el HTML público de la publicación.
///
/// TikTok e Instagram no tienen una API pública sin clave, así que esto lee
/// lo mismo que vería un navegador: el JSON que TikTok incrusta en la página
/// para su propio uso interno, o las etiquetas Open Graph que cualquier red
/// social pone para que un enlace compartido muestre una vista previa. Es el
/// mismo truco que usan los sitios de descarga de reels, sin depender de que
/// uno de ellos siga funcionando.
///
/// Es inestable por diseño: si la plataforma cambia cómo arma la página, la
/// extracción específica deja de encontrar lo que busca. Por eso cada intento
/// tiene un resguardo —Open Graph como último recurso— y ninguno lanza: si no
/// se encuentra nada, se devuelve un [SocialPostData] vacío y es quien lo
/// use el que decide qué hacer con eso.
class HtmlSocialPostClient implements SocialPostClient {
  const HtmlSocialPostClient(this._client);

  final WebPageClient _client;

  @override
  Future<SocialPostData> fetchPost(Uri url) async {
    final html = await _client.fetchHtml(url);

    if (url.host.contains('tiktok.com')) {
      final fromTikTok = _fromTikTokEmbed(html);
      if (fromTikTok != null) return fromTikTok;
    }

    return _fromOpenGraph(html);
  }

  /// El JSON que TikTok deja en la página para hidratar su propia interfaz.
  ///
  /// Trae más que Open Graph —el video sin marca de agua, el nombre de
  /// usuario— pero solo cuando la estructura es la esperada. `null` si el
  /// script no está o si algo del camino no es lo que se esperaba, para que
  /// [fetchPost] caiga en Open Graph en vez de fallar.
  SocialPostData? _fromTikTokEmbed(String html) {
    final scriptMatch = RegExp(
      '<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (scriptMatch == null) return null;

    try {
      final data = jsonDecode(scriptMatch.group(1)!);
      final item = _dig(data, [
        '__DEFAULT_SCOPE__',
        'webapp.video-detail',
        'itemInfo',
        'itemStruct',
      ]);
      if (item is! Map) return null;

      final video = item['video'];
      final playAddr = video is Map ? video['playAddr'] : null;
      // La carátula: solo hace falta si el video no se pudo conseguir —un
      // TikTok siempre trae video, pero `playAddr` puede faltar por la
      // misma razón que cualquier otro campo de este JSON— para no dejar
      // la publicación sin nada que mostrar.
      final cover = video is Map
          ? (video['cover'] ?? video['originCover'])
          : null;
      final author = item['author'];
      final username = author is Map ? author['uniqueId'] : null;

      return SocialPostData(
        caption: item['desc'] is String ? item['desc'] as String : null,
        authorName: username is String ? username : null,
        videoUrl: playAddr is String ? Uri.tryParse(playAddr) : null,
        imageUrl: playAddr == null && cover is String
            ? Uri.tryParse(cover)
            : null,
      );
      // El JSON de una plataforma ajena puede cambiar de forma sin aviso:
      // cualquier tropiezo acá —una clave que ya no está, un tipo distinto
      // del esperado— cae en Open Graph en vez de tirar abajo la captura.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  /// Recorre un mapa anidado por una lista de claves, sin lanzar si alguna
  /// falta en el camino.
  Object? _dig(Object? node, List<String> path) {
    var current = node;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }

  /// Las etiquetas `og:` que casi cualquier página pone para las vistas
  /// previas de enlaces compartidos. El resguardo universal: más pobre que
  /// leer el JSON propio de la plataforma, pero disponible en casi cualquier
  /// publicación pública.
  SocialPostData _fromOpenGraph(String html) {
    final videoUrl =
        _metaContent(html, 'og:video:secure_url') ??
        _metaContent(html, 'og:video');
    // Solo se guarda si no hay video: entre las dos, el video es el
    // contenido más completo, y `og:image` en una publicación con video
    // suele ser apenas un fotograma de portada, no algo que valga la pena
    // guardar aparte.
    final imageUrl = videoUrl == null ? _metaContent(html, 'og:image') : null;

    return SocialPostData(
      caption: _metaContent(html, 'og:description'),
      authorName: _metaContent(html, 'og:title'),
      videoUrl: videoUrl != null
          ? Uri.tryParse(_unescapeHtmlEntities(videoUrl))
          : null,
      imageUrl: imageUrl != null
          ? Uri.tryParse(_unescapeHtmlEntities(imageUrl))
          : null,
    );
  }

  /// El contenido de `<meta property="$property" content="...">`, sin
  /// importar en qué orden vengan los atributos —ambos órdenes aparecen en
  /// la práctica según la plataforma.
  String? _metaContent(String html, String property) {
    final propertyFirst = RegExp(
      '<meta[^>]*property="$property"[^>]*content="([^"]*)"',
    ).firstMatch(html);
    if (propertyFirst != null) {
      return _unescapeHtmlEntities(propertyFirst.group(1)!);
    }

    final contentFirst = RegExp(
      '<meta[^>]*content="([^"]*)"[^>]*property="$property"',
    ).firstMatch(html);
    return contentFirst != null
        ? _unescapeHtmlEntities(contentFirst.group(1)!)
        : null;
  }

  /// Las entidades que de verdad aparecen en atributos HTML de un `<meta>`.
  ///
  /// No hace falta una lista completa: esto no interpreta HTML de verdad,
  /// solo el puñado de entidades que las plataformas usan al escapar
  /// comillas, símbolos y saltos de línea dentro de un atributo.
  String _unescapeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}
