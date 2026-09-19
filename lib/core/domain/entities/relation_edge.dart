import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

part 'relation_edge.freezed.dart';

/// Un vínculo tal cual vive en la base, sin el contexto de "desde qué
/// elemento se está mirando" que sí necesita `ItemRelation`.
///
/// Existe aparte de `ItemRelation` porque el grafo de toda la bóveda no mira
/// las cosas desde un elemento —el caso que resuelve `ItemRelation`—: mira
/// todos los vínculos a la vez, para dibujarlos todos juntos.
@freezed
sealed class RelationEdge with _$RelationEdge {
  const factory RelationEdge({
    required String id,
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,

    /// Cuándo se marcó como revisado. `null` = sin revisar. Hoy solo importa
    /// para `contradicts`: es lo que separa las contradicciones pendientes de
    /// las que ya se miraron en la pantalla de Tensión.
    DateTime? reviewedAt,
  }) = _RelationEdge;
}
