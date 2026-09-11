/// Se lanza cuando `/login` responde 401/403: estas credenciales están mal.
/// Es distinta del `UnauthorizedException` genérico de `core/error`, que
/// significa "tu sesión (ya iniciada) expiró" — un caso que este endpoint
/// nunca produce, porque todavía no hay sesión que expirar.
final class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException([
    this.message = 'Correo o contraseña incorrectos.',
  ]);

  final String message;
}

/// Se lanza cuando `/signup` responde 400: ya existe una cuenta con ese
/// correo.
final class EmailAlreadyInUseException implements Exception {
  const EmailAlreadyInUseException([
    this.message = 'Ese correo ya está registrado.',
  ]);

  final String message;
}
