import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';

/// Lo que el Atlas de la IA (F27) lee de la bóveda: el árbol de temas, lo que
/// junta cada tema, sus notas mapa y cómo creció una nota viva.

/// Un valor de la categoría «Tema».
@immutable
class AtlasTopic {
  const AtlasTopic({
    required this.id,
    required this.label,
    required this.createdAt,
    this.parentId,
  });

  final String id;
  final String label;
  final String? parentId;

  /// Cuándo se creó: un tema nacido desde que la IA organiza es «nuevo».
  final DateTime createdAt;
}

/// El árbol de la categoría «Tema» entero: son unos pocos miles de valores
/// en la bóveda más grande que se midió (2.164), y la IA lo recorre en
/// memoria con `VocabularyTree`, la misma regla de descendientes que el
/// Atlas y la pantalla de Vocabulario.
class AtlasTopicTree {
  AtlasTopicTree({required this.definitionId, required List<AtlasTopic> topics})
    : topics = List.unmodifiable(topics),
      _byId = {for (final topic in topics) topic.id: topic},
      tree = VocabularyTree([
        for (final topic in topics) (id: topic.id, parentId: topic.parentId),
      ]);

  /// La categoría «Tema».
  final String definitionId;
  final List<AtlasTopic> topics;
  final VocabularyTree tree;
  final Map<String, AtlasTopic> _byId;

  AtlasTopic? operator [](String id) => _byId[id];

  /// Si [id] está suelto: sin padre y sin subtemas. Es lo único que la IA
  /// ubica sola; una raíz con subtemas es una rama que alguien armó.
  bool isLoose(String id) =>
      tree.parentOf(id) == null && tree.childrenOf(id).isEmpty;

  /// Si [id] es parte del árbol: tiene padre o subtemas.
  bool isInTree(String id) =>
      tree.parentOf(id) != null || tree.childrenOf(id).isNotEmpty;

  /// [id] escrito con su camino desde la raíz: «Historia › Historia
  /// antigua». Es como se le muestra al modelo y a la persona.
  String pathOf(String id) => [
    for (final ancestor in tree.ancestorsOf(id).reversed)
      _byId[ancestor]!.label,
    _byId[id]!.label,
  ].join(' › ');
}

/// Un elemento que junta un tema: tiene puesto el tema o alguno de sus
/// subtemas. Las notas mapa no cuentan: son el índice, no el material.
@immutable
class TopicMaterial {
  const TopicMaterial({
    required this.itemId,
    required this.title,
    required this.updatedAt,
    required this.valueIds,
    this.noteKind,
  });

  final String itemId;
  final String title;
  final DateTime updatedAt;

  /// Qué valores de la rama tiene puestos: con ellos se agrupa por subtema.
  final Set<String> valueIds;

  /// El tipo de nota, o `null` si es una fuente.
  final NoteKind? noteKind;

  bool get isNote => noteKind != null;
}

/// Una nota mapa viva de un tema, como la ve la IA.
@immutable
class TopicMapNote {
  const TopicMapNote({
    required this.itemId,
    required this.title,
    required this.byAi,
    required this.edited,
    required this.aiLetGo,
    this.blocksContent,
  });

  final String itemId;
  final String title;

  /// La escribió la IA (`generated_by_model`).
  final bool byAi;

  /// La persona tocó su contenido después (`derived_edited`): ya es suya.
  final bool edited;

  /// La persona deshizo la última pasada de la IA sobre ella: la IA la suelta
  /// y no la vuelve a tocar.
  final bool aiLetGo;

  /// Su contenido en bloques, tal como está guardado; `null` si no tiene.
  final String? blocksContent;

  /// La IA la mantiene: es suya, nadie la editó y nadie se la sacó.
  bool get keptByAi => byAi && !edited && !aiLetGo;
}

/// Lo que dice cuánto creció una nota, para sugerir su madurez.
@immutable
class NoteGrowth {
  const NoteGrowth({
    required this.noteKind,
    required this.maturity,
    required this.createdAt,
    required this.connections,
  });

  final NoteKind noteKind;
  final NoteMaturity maturity;
  final DateTime createdAt;

  /// Con cuántos elementos vivos está vinculada, en cualquier sentido y por
  /// cualquier vínculo —también los de sus `[[ ]]`—, sin contar las notas
  /// mapa: que un índice la nombre no es que ella conecte.
  final int connections;
}
