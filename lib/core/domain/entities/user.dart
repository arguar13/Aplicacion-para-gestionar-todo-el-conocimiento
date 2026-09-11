import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// Vive en `core` (no en `features/auth`) porque más de un feature lo
/// necesita: `auth` lo produce al hacer login, `dashboard` lo vuelve a
/// pedir (`GET /me`) para probar que el token viaja en cada request.
/// Promoverlo aquí evita que `dashboard` tenga que depender de `auth`.
@freezed
sealed class User with _$User {
  const factory User({
    required String id,
    required String name,
    required String email,
  }) = _User;
}
