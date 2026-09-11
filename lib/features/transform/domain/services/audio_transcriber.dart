/// Convierte el audio de un archivo en el texto que se dice en él.
///
/// Mismo criterio que `ImageTextExtractor`: una sola operación, y quien la
/// implementa decide con qué motor y en qué hilo. Sirve tanto para un
/// archivo de audio como para uno de video —la pista de audio es lo único
/// que importa en los dos casos—.
// ignore: one_member_abstracts
abstract interface class AudioTranscriber {
  Future<String> transcribe(String absolutePath);
}
