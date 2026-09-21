import 'package:sinapsis/core/domain/entities/reference_data.dart';

/// Los datos bibliográficos de una fuente (F15), para la pantalla que los
/// muestra y los edita.
///
/// Lo que se guarda pasa por el escritor único: acá no hay una segunda
/// manera de escribir una referencia. Las personas se resuelven contra el
/// vocabulario de autores —«García Márquez, Gabriel» escrito dos veces es la
/// misma persona, no dos—.
abstract interface class ReferenceRepository {
  /// La referencia de [itemId], que se vuelve a emitir cada vez que cambia —o
  /// cambia el nombre de una de sus personas—. Una fuente sin nada guardado
  /// emite una referencia vacía: quien la muestra marca lo que falta.
  Stream<ReferenceData> watch(String itemId);

  /// La referencia de [itemId] ahora, una sola vez.
  Future<ReferenceData> read(String itemId);

  /// Guarda [reference] como la referencia de [itemId], entera: lo que no
  /// trae se borra. Devuelve `false`, sin tocar nada, si la fuente no existe.
  Future<bool> saveReference(String itemId, ReferenceData reference);

  /// Guarda la fecha de publicación de la fuente —`null` la borra—. Es un
  /// dato de la fuente y no de la referencia: la exactitud de la fecha sí va
  /// en la referencia.
  Future<bool> savePublishedAt(String itemId, DateTime? publishedAt);
}
