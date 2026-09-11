import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Elige qué transformador se ocupa de cada elemento.
///
/// Se diferencia del registro de adaptadores en algo importante: acá puede no
/// haber ninguno, y eso no es un error. Una nota escrita a mano ya está
/// completa en el momento de guardarse; no hay nada que traer ni que
/// convertir. Por eso [resolve] devuelve `null` en vez de lanzar.
class TransformerRegistry {
  const TransformerRegistry(this._transformers);

  final List<Transformer> _transformers;

  /// El primero que tenga algo que hacer con [item], o `null` si ninguno.
  Transformer? resolve(KnowledgeItem item) {
    for (final transformer in _transformers) {
      if (transformer.canTransform(item)) return transformer;
    }
    return null;
  }
}
