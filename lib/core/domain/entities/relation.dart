import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

part 'relation.freezed.dart';

/// Un vínculo entre dos elementos.
///
/// La app puede *proponer* candidatos —dos textos que comparten términos poco
/// frecuentes suelen tener algo que ver— pero la relación la confirma una
/// persona. Un grafo lleno de vínculos automáticos de baja calidad vale menos
/// que veinte hechos a mano: el valor está en que cada línea signifique algo.
@freezed
sealed class Relation with _$Relation {
  const factory Relation({
    required String id,

    /// El sentido importa en los tipos que no son simétricos: que A
    /// *continúe* a B no es lo mismo que B continúe a A.
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,
    required DateTime createdAt,

    /// Por qué están relacionados, si hace falta aclararlo.
    String? note,
  }) = _Relation;
}
