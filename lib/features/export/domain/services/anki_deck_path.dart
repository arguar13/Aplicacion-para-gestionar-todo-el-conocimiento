import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';

/// El mazo raíz de toda exportación a Anki.
const kAnkiRootDeckName = 'Sinapsis';

/// El subdeck de una tarjeta sin ningún tema asignado (D1).
const kAnkiNoTopicDeckName = 'Sin tema';

/// El subdeck de Anki de un elemento, según D1/D2 (F17).
///
/// Pura, mismo patrón que `atlas_builder.dart`: recorre el árbol de Temas
/// —ya armado, no lo arma acá— de la raíz a la hoja, con el mismo texto que
/// el usuario ve en el Atlas, separado por `::` —el separador estándar de
/// subdecks de Anki—.
///
/// [firstTopicValueId] es el PRIMER tema asignado al elemento, por orden de
/// asignación (D1): un elemento con varios temas se exporta UNA sola vez, en
/// el subdeck de ese primero, nunca duplicada en cada uno de los suyos —eso
/// inflaría insignias como «cien tarjetas repasadas», contando la misma
/// tarjeta varias veces—. `null` —sin ningún tema— va a un subdeck fijo,
/// «Sinapsis::Sin tema».
String ankiDeckPathOf({
  required String? firstTopicValueId,
  required VocabularyTree temaTree,
  required Map<String, String> labelOf,
}) {
  if (firstTopicValueId == null) {
    return '$kAnkiRootDeckName::$kAnkiNoTopicDeckName';
  }

  final chain = [
    ...temaTree.ancestorsOf(firstTopicValueId).reversed,
    firstTopicValueId,
  ];
  return [
    kAnkiRootDeckName,
    for (final id in chain) labelOf[id] ?? id,
  ].join('::');
}
