/// Saca el texto que haya escrito dentro de una imagen: una captura de
/// pantalla, la foto de una página de un libro, un cartel.
///
/// Aparte del `Transformer` que la usa, a propósito: el reconocimiento de
/// texto necesita un motor distinto en cada plataforma —ML Kit fuera de la
/// web, Tesseract en WebAssembly ahí— y esta interfaz es lo único de todo
/// el camino que no se puede probar sin uno de los dos.
// ignore: one_member_abstracts
abstract interface class ImageTextExtractor {
  /// El texto reconocido en la imagen de [path]. Cadena vacía si no había
  /// ninguno —una foto de un paisaje, un ícono—, nunca `null`: no encontrar
  /// texto no es un error.
  ///
  /// [path] es la ruta absoluta fuera de la web; en la web, donde no existe
  /// tal cosa, es la ruta relativa que guarda la base.
  Future<String> extractText(String path);
}
