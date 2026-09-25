import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';

/// El árbol de Temas y, para cada elemento pedido, su primer tema asignado
/// (D1), listo para armar el subdeck de cada tarjeta con `ankiDeckPathOf`.
class AnkiTopicResolution {
  const AnkiTopicResolution({
    required this.tree,
    required this.labelOf,
    required this.firstTopicByItem,
  });

  final VocabularyTree tree;
  final Map<String, String> labelOf;

  /// El id del primer tema —por orden de asignación— de cada elemento
  /// pedido. Presente para todos los ids pedidos; `null` es «sin ningún
  /// tema», no «no se pidió».
  final Map<String, String?> firstTopicByItem;
}

/// Resuelve el árbol de Temas y el primer tema de un conjunto de elementos,
/// para exportar a Anki con subdecks (F17, D1/D2).
// ignore: one_member_abstracts
abstract interface class AnkiTopicResolver {
  Future<AnkiTopicResolution> resolve(Set<String> itemIds);
}
