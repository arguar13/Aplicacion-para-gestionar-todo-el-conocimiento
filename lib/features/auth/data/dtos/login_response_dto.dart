import 'package:json_annotation/json_annotation.dart';
import 'package:sinapsis/core/data/dtos/user_dto.dart';

part 'login_response_dto.g.dart';

@JsonSerializable()
class LoginResponseDto {
  const LoginResponseDto({required this.token, required this.user});

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) =>
      _$LoginResponseDtoFromJson(json);

  final String token;
  final UserDTO user;

  Map<String, dynamic> toJson() => _$LoginResponseDtoToJson(this);
}
