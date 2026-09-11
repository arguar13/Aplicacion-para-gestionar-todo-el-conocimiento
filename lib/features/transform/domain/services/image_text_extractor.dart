/// Saca el texto que haya escrito dentro de una imagen: una captura de
/// pantalla, la foto de una página de un libro, un cartel.
///
/// Aparte del `Transformer` que la usa, a propósito: el reconocimiento de
/// texto necesita un motor nativo —distinto en cada plataforma— y esta
/// interfaz es lo único de todo el camino que no se puede probar sin él.
// ignore: one_member_abstracts
abstract interface class ImageTextExtractor {
  /// El texto reconocido en la imagen de [absolutePath]. Cadena vacía si no
  /// había ninguno —una foto de un paisaje, un ícono—, nunca `null`: no
  /// encontrar texto no es un error.
  Future<String> extractText(String absolutePath);
}
