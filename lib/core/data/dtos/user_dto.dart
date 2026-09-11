import 'package:json_annotation/json_annotation.dart';
import 'package:sinapsis/core/domain/entities/user.dart';

part 'user_dto.g.dart';

/// Compartido entre `auth` (viene dentro de la respuesta de `/login`) y
/// `dashboard` (`GET /me`). Ambos endpoints devuelven la misma forma de
/// usuario; si alguna vez divergen, el feature que cambie se lleva su
/// propio DTO y dejamos este como el "shape" original.
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
