import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'item_relation.freezed.dart';

/// De qué lado del vínculo está el elemento que se está mirando.
///
/// El sentido importa en los tipos que no son simétricos: parado en el
/// elemento A, un vínculo "A continúa a B" y uno "C continúa a A" son cosas
/// distintas — la primera dice "esto sigue después de B", la segunda dice
/// "esto es la continuación de C". Sin esta distinción, el detalle no podría
/// mostrar la flecha en el sentido correcto.
enum RelationDirection {
  /// El elemento que se mira es el origen (`fromItemId`).
  outgoing,

  /// El elemento que se mira es el destino (`toItemId`).
  incoming,
}

/// Un vínculo visto desde uno de los dos elementos que conecta, con lo
/// mínimo del otro lado para poder mostrarlo en una lista.
///
/// No carga el elemento entero del otro lado a propósito: una lista de
/// vínculos es una lista de líneas de texto con un ícono, no vale la pena
/// traer sus formas de contenido ni su procedencia completa solo para
/// mostrar un título.
@freezed
sealed class ItemRelation with _$ItemRelation {
  const factory ItemRelation({
    required String relationId,
    required RelationDirection direction,
    required RelationKind kind,
    required DateTime createdAt,
    required String otherItemId,
    required String otherItemTitle,
    required SourceKind otherItemSourceKind,
    String? note,

    /// Solo en una extracción (`extractedFrom`): de dónde a dónde del texto de
    /// la fuente salió el fragmento, en posiciones del contenido de la forma de
    /// texto de la que se extrajo —las mismas que usan los resaltados—. `null`
    /// en cualquier otro vínculo y en las extracciones anteriores a que se
    /// guardara.
    int? sourceCharStart,
    int? sourceCharEnd,
  }) = _ItemRelation;
}
