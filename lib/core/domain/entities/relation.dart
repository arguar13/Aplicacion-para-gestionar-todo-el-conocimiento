import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

part 'relation.freezed.dart';

/// Un vínculo entre dos elementos.
///
/// Desde F27 la IA también los crea sola, cada uno con el motivo en [note],
/// marcado como suyo ([origin]) y con la pasada que lo hizo ([aiRunId]): un
/// grafo lleno de vínculos automáticos vale si cada línea se puede corregir,
/// editar o deshacer, y si lo que la persona dijo que «no era» no vuelve.
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

    /// Por qué están relacionados, si hace falta aclararlo. En uno de la IA,
    /// el motivo que dio.
    String? note,

    /// Quién lo hizo (F27). Uno de la IA que la persona edita pasa a ser suyo.
    @Default(ContentOrigin.user) ContentOrigin origin,

    /// Qué tan segura estaba la IA, de 0 a 1. `null` en los de la persona.
    double? confidence,

    /// La pasada de la IA que lo creó, con la que se deshace entera.
    String? aiRunId,
  }) = _Relation;

  const Relation._();

  /// Si sigue siendo de la IA: lo que «deshacer todo» se lleva.
  bool get isFromAi => origin == ContentOrigin.ai;
}
