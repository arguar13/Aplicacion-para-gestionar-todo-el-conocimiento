/// Reconocimiento de direcciones de YouTube.
///
/// Vive en `core` y no dentro de un feature porque la usan dos: la captura,
/// para saber que un enlace pegado es un video, y la transformación, para
/// saber qué video pedir. Duplicarla habría sido peor que compartirla — dos
/// copias de un parser terminan divergiendo en los casos raros, que son
/// justamente los que importan.
abstract final class YouTubeUrl {
  /// Los dominios que YouTube usa para repartir enlaces.
  static const hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
    'www.youtu.be',
  };

  /// Si [url] apunta a un video de YouTube.
  ///
  /// Se compara el host completo y no con un `contains('youtube')`: un
  /// dominio como `youtube.ejemplo.com` no es YouTube, y tratarlo como tal
  /// haría que la app le pidiera subtítulos a un sitio cualquiera.
  static bool isVideo(Uri url) =>
      hosts.contains(url.host.toLowerCase()) && videoIdOf(url) != null;

  /// El identificador del video, o `null` si la dirección no apunta a uno.
  ///
  /// Cubre las tres formas en que YouTube reparte enlaces: el clásico `?v=`,
  /// el corto `youtu.be/ID` y el de los shorts `/shorts/ID`. Una dirección
  /// que no sea ninguna de esas —la portada, un canal, una lista— no tiene
  /// video que capturar.
  static String? videoIdOf(Uri url) {
    final host = url.host.toLowerCase();

    if (host == 'youtu.be' || host == 'www.youtu.be') {
      final segments = url.pathSegments.where((s) => s.isNotEmpty);
      return segments.isEmpty ? null : segments.first;
    }

    final fromQuery = url.queryParameters['v'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex != -1 && shortsIndex + 1 < segments.length) {
      return segments[shortsIndex + 1];
    }

    return null;
  }
}
