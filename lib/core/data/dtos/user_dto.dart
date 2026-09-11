import 'package:json_annotation/json_annotation.dart';
import 'package:sinapsis/core/domain/entities/user.dart';

part 'user_dto.g.dart';

/// Compartido entre `auth` (llega dentro de la respuesta del login) y
/// `dashboard` (que vuelve a pedir el perfil). Ambos endpoints devuelven
/// la misma forma de usuario; si alguna vez divergen, el feature que
/// cambie se lleva su propio DTO y dejamos este como el "shape" original.
///
/// A propósito no se nombra acá el path concreto de cada endpoint: ese
/// dato vive en el data source que lo llama y en ningún otro lado. Tener
/// la ruta repetida en un comentario de `core` es exactamente cómo se
/// desincronizó antes (decía `/me` mientras el código pedía `/user`).
@JsonSerializable()
class UserDTO {
  const UserDTO({required this.id, required this.name, required this.email});

  factory UserDTO.fromJson(Map<String, dynamic> json) =>
      _$UserDTOFromJson(json);

  final String id;
  final String name;
  final String email;

  Map<String, dynamic> toJson() => _$UserDTOToJson(this);

  User toEntity() => User(id: id, name: name, email: email);
}
