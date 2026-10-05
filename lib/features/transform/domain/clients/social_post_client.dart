/// Lo que se pudo sacar de una publicación: TikTok, Instagram o cualquier
/// otra red que ponga las mismas etiquetas Open Graph en su HTML.
///
/// Cualquiera de los campos puede faltar — no todas las publicaciones tienen
/// video, no todas dejan leer el texto sin iniciar sesión — y eso no es un
/// error: es lo que hay.
class SocialPostData {
  const SocialPostData({
    this.caption,
    this.authorName,
    this.videoUrl,
    this.imageUrl,
    this.moreImages = const [],
  });

  final String? caption;
  final String? authorName;
  final Uri? videoUrl;

  /// La foto de portada de la publicación, o la única foto en una que no
  /// tiene video — de `og:image`, la misma etiqueta que arma la vista
  /// previa cuando se comparte el enlace en cualquier otra parte.
  ///
  /// En un carrusel es la primera; las demás van en [moreImages].
  final Uri? imageUrl;

  /// Las demás fotos de un carrusel, en orden, después de [imageUrl] (F30):
  /// las de una publicación de fotos de TikTok (su `imagePost`), o las
  /// demás `og:image` de una página que declara varias. Vacío si no hay
  /// más.
  ///
  /// Instagram no las da: su HTML público trae solo la primera sin iniciar
  /// sesión, ni con Open Graph ni con su JSON —verlas todas pediría la API
  /// privada de la red, y lo que no es público no se baja—.
  final List<Uri> moreImages;
}

/// Trae lo que se pueda de una publicación de una red social.
///
/// A diferencia de traer una página cualquiera, no hay una API oficial ni un
/// paquete
/// como `youtube_explode_dart` que abstraiga esto: lo que sale de acá viene
/// de raspar el HTML público de la página, que cada plataforma puede cambiar
/// sin aviso. Por eso el contrato es best-effort a propósito — devuelve lo
/// que encuentra, nunca lanza por no encontrar algo — y quien llama decide
/// qué hacer si no encontró nada de nada.
// ignore: one_member_abstracts
abstract interface class SocialPostClient {
  Future<SocialPostData> fetchPost(Uri url);
}

/// No se pudo sacar ni el texto ni el video de la publicación.
///
/// Pasa seguido y no siempre es un fallo de la app: una publicación privada,
/// borrada, o una plataforma que ese día decidió servirle a este cliente una
/// página distinta de la que ve una persona.
final class SocialPostUnavailableException implements Exception {
  const SocialPostUnavailableException(this.url);

  final Uri url;

  @override
  String toString() => 'SocialPostUnavailableException: $url';
}
