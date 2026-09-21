import 'package:freezed_annotation/freezed_annotation.dart';

part 'atlas_gap.freezed.dart';

/// Qué le falta o qué tiene raro una rama (F13, D7).
enum AtlasGapKind {
  /// Muchas fuentes y ninguna nota viva en toda la rama: material de sobra sin
  /// nada propio escrito. Ver `kAtlasManySources`.
  manySourcesNoLivingNote,

  /// Un solo elemento en toda la rama: un tema que todavía no es un tema.
  singleItem,

  /// Nada de la rama se tocó hace meses. Ver `kAtlasStaleAfter`.
  stale,
}

/// Un vacío detectado en la rama [valueId].
///
/// Se avisa en la rama MÁS ALTA donde se cumple y no se repite en sus
/// descendientes: si «Roma» tiene cincuenta fuentes y ninguna nota viva, sus
/// subtemas tampoco tienen, y avisar de todos sería el mismo vacío contado
/// varias veces.
@freezed
sealed class AtlasGap with _$AtlasGap {
  const factory AtlasGap({
    required AtlasGapKind kind,
    required String valueId,
  }) = _AtlasGap;
}
