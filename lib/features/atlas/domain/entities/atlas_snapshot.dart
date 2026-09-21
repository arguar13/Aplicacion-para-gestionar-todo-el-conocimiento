import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';

part 'atlas_snapshot.freezed.dart';

/// El Atlas de UNA categoría en un momento: su árbol con los agregados de cada
/// rama y los vacíos detectados.
///
/// Es un derivado —se calcula de las propiedades y las notas y no se guarda—
/// y por eso nunca hay nada que mantener a mano.
@freezed
sealed class AtlasSnapshot with _$AtlasSnapshot {
  const factory AtlasSnapshot({
    required String definitionId,
    required String definitionName,

    /// Las ramas en preorden: cada valor seguido de sus subtemas, y los
    /// hermanos por nombre. Con `depth`, una lista que se recorre de corrido
    /// es un árbol.
    required List<AtlasNode> nodes,

    /// Los vacíos: primero los de más fuentes sin nota viva, después las ramas
    /// más abandonadas y al final las de un solo elemento.
    required List<AtlasGap> gaps,
  }) = _AtlasSnapshot;

  const AtlasSnapshot._();

  /// El Atlas de una categoría que no existe o no tiene valores.
  factory AtlasSnapshot.empty(String definitionId, {String name = ''}) =>
      AtlasSnapshot(
        definitionId: definitionId,
        definitionName: name,
        nodes: const [],
        gaps: const [],
      );

  /// La rama del valor [valueId], si está.
  AtlasNode? nodeOf(String valueId) {
    for (final node in nodes) {
      if (node.valueId == valueId) return node;
    }
    return null;
  }

  /// Las ramas del primer nivel.
  Iterable<AtlasNode> get roots => nodes.where((node) => node.parentId == null);
}
