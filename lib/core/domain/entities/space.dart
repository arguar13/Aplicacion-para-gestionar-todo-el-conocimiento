import 'package:freezed_annotation/freezed_annotation.dart';

part 'space.freezed.dart';

/// Un espacio: una carpeta para agrupar elementos.
///
/// Mismo criterio que `Tag` —nombre único sin distinguir mayúsculas, para
/// que dos espacios no terminen compitiendo por agrupar lo mismo— con una
/// diferencia real: un elemento pertenece a lo sumo a un espacio, no a
/// varios. Es una carpeta, no una marca.
@freezed
sealed class Space with _$Space {
  const factory Space({
    required String id,
    required String name,
    required DateTime createdAt,
  }) = _Space;
}
