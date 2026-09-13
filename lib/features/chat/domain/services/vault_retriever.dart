import 'package:sinapsis/core/domain/entities/chat_source.dart';

/// Encuentra qué partes de la bóveda son relevantes para una pregunta.
///
/// Es la mitad "R" de RAG (retrieval-augmented generation), y la única que
/// no depende de tener un modelo de lenguaje descargado: sin él, esto solo
/// ya sirve para mostrar qué elementos hablan de lo preguntado, con su
/// fuente — la búsqueda de FTS5 que ya tiene la biblioteca, aplicada a una
/// pregunta en vez de a palabras sueltas. Ver la decisión 20 en
/// docs/arquitectura.md sobre por qué no hay embeddings vectoriales todavía.
// ignore: one_member_abstracts
abstract interface class VaultRetriever {
  /// Los fragmentos más relevantes para [question], como mucho [limit].
  /// Lista vacía si nada de la bóveda se relaciona con lo preguntado.
  Future<List<ChatSource>> retrieve(String question, {int limit = 4});
}
