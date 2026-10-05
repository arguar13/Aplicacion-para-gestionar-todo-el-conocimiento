import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
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
    // Se lee con un parser de HTML de verdad y no con expresiones regulares
    // (F22): así cada atributo llega con todas sus entidades traducidas
    // —"&#233;", "&nbsp;", "&hellip;"— y traducidas una sola vez. Antes se
    // desescapaban seis a mano, y como "&amp;" iba primero, un "&amp;lt;"
    // del original —que es el texto "&lt;"— terminaba como "<".
    final document = html_parser.parse(await _client.fetchHtml(url));

    if (url.host.contains('tiktok.com')) {
      final fromTikTok = _fromTikTokEmbed(document);
      if (fromTikTok != null) return fromTikTok;
    }

    return _fromOpenGraph(document);
  }

  /// El JSON que TikTok deja en la página para hidratar su propia interfaz.
  ///
  /// Trae más que Open Graph —el video sin marca de agua, el nombre de
  /// usuario— pero solo cuando la estructura es la esperada. `null` si el
  /// script no está o si algo del camino no es lo que se esperaba, para que
  /// [fetchPost] caiga en Open Graph en vez de fallar.
  SocialPostData? _fromTikTokEmbed(Document document) {
    // El contenido de un `<script>` es texto crudo para el parser: llega tal
    // cual, sin traducir entidades, que es lo que espera `jsonDecode`.
    final script = document.getElementById(
      '__UNIVERSAL_DATA_FOR_REHYDRATION__',
    );
    if (script == null) return null;

    try {
      final data = jsonDecode(script.text);
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
      // Una publicación de fotos —un carrusel— trae cada una en
      // `imagePost.images[].imageURL.urlList`, con la primera dirección
      // como la buena (F30).
      final photos = _tikTokPhotos(item['imagePost']);
      final hasVideo = playAddr is String && playAddr.isNotEmpty;

      return SocialPostData(
        caption: item['desc'] is String ? item['desc'] as String : null,
        authorName: username is String ? username : null,
        videoUrl: hasVideo ? Uri.tryParse(playAddr) : null,
        imageUrl: hasVideo
            ? null
            : photos.firstOrNull ??
                  (cover is String ? Uri.tryParse(cover) : null),
        moreImages: hasVideo ? const [] : photos.skip(1).toList(),
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
  /// Las fotos de un `imagePost` de TikTok, en orden.
  List<Uri> _tikTokPhotos(Object? imagePost) {
    final images = imagePost is Map ? imagePost['images'] : null;
    if (images is! List) return const [];
    return [
      for (final image in images)
        if (_dig(image, ['imageURL', 'urlList']) case [final String first, ...])
          ?Uri.tryParse(first),
    ];
  }

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
  SocialPostData _fromOpenGraph(Document document) {
    final videoUrl =
        _metaContent(document, 'og:video:secure_url') ??
        _metaContent(document, 'og:video');
    // Solo se guarda si no hay video: entre las dos, el video es el
    // contenido más completo, y `og:image` en una publicación con video
    // suele ser apenas un fotograma de portada, no algo que valga la pena
    // guardar aparte. Una página puede declarar varias `og:image` —un
    // carrusel, una galería—: todas cuentan, en orden y sin repetir (F30).
    final images = videoUrl == null
        ? {
            for (final image in _metaContents(document, 'og:image'))
              ?Uri.tryParse(image),
          }.toList()
        : const <Uri>[];

    return SocialPostData(
      caption: _metaContent(document, 'og:description'),
      authorName: _metaContent(document, 'og:title'),
      // Sin desescapar otra vez: el parser ya tradujo las entidades, y una
      // segunda pasada convertía un "&amp;lt;" en "<".
      videoUrl: videoUrl != null ? Uri.tryParse(videoUrl) : null,
      imageUrl: images.firstOrNull,
      moreImages: images.skip(1).toList(),
    );
  }

  /// El contenido de `<meta property="$property" content="...">`, con sus
  /// entidades ya traducidas por el parser, sin importar en qué orden vengan
  /// los atributos —ambos órdenes aparecen en la práctica según la
  /// plataforma— ni con qué comillas.
  String? _metaContent(Document document, String property) =>
      _metaContents(document, property).firstOrNull;

  Iterable<String> _metaContents(Document document, String property) => document
      .querySelectorAll('meta')
      .where((meta) => meta.attributes['property'] == property)
      .map((meta) => meta.attributes['content'])
      .nonNulls;
}
