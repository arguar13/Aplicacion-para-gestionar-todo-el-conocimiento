/// Convierte el audio de un archivo en el texto que se dice en él.
///
/// Mismo criterio que `ImageTextExtractor`: una sola operación, y quien la
/// implementa decide con qué motor y en qué hilo. Sirve tanto para un
/// archivo de audio como para uno de video —la pista de audio es lo único
/// que importa en los dos casos—.
// ignore: one_member_abstracts
abstract interface class AudioTranscriber {
  /// [path] es la ruta absoluta fuera de la web; en la web, donde no existe
  /// tal cosa, es la ruta relativa que guarda la base —mismo criterio que
  /// `ImageTextExtractor.extractText`—.
  Future<String> transcribe(String path);
}
