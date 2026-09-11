import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag.freezed.dart';

/// Una etiqueta. Puesta a mano o aceptada de una sugerencia, pero siempre
/// confirmada por una persona.
@freezed
sealed class Tag with _$Tag {
  const factory Tag({
    required String id,

    /// Único, sin distinguir mayúsculas: "Filosofía" y "filosofía" son la
    /// misma etiqueta. Dejar que convivan las dos parte la biblioteca en dos
    /// mitades que no se encuentran entre sí.
    required String name,
    required DateTime createdAt,
  }) = _Tag;
}
