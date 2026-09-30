import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

/// Lleva al texto nuevo de un elemento todo lo que apuntaba a posiciones
/// del viejo, cuando se vuelve a extraer (F22): los subrayados, las
/// tarjetas y sus opciones que citan un fragmento, y las notas extraídas de
/// un fragmento.
///
/// Cada cosa se busca por el fragmento que marcaba —ver `locateExcerpt`—,
/// no por su posición: la misma frase puede haberse corrido cientos de
/// caracteres porque cambió cómo se cortan los renglones.
// ignore: one_member_abstracts
abstract interface class TextAnchorRelocator {
  /// Reubica lo que apuntaba al texto [from] de la forma [renditionId] de
  /// [itemId], que ahora dice [to]. Devuelve los subrayados que no se
  /// encontraron: ya no están en la base, y quien llama los conserva de otra
  /// forma (ver `notesWithLostHighlights`). Una tarjeta o una nota extraída
  /// cuyo fragmento no se encuentra queda sin posición —se abre el elemento,
  /// no un lugar equivocado—.
  ///
  /// Corre dentro de la transacción de quien llama.
  Future<List<LostHighlight>> relocate({
    required String itemId,
    required String renditionId,
    required String from,
    required String to,
  });
}
