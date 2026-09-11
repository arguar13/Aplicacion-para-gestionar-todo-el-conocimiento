/// Resultado de comprobar un PIN contra el credencial guardado.
///
/// Son tres casos y no un `bool` porque hay un tercero que importa:
/// el PIN es correcto, pero fue derivado con parámetros que hoy se
/// consideran flojos (menos iteraciones de las que usamos ahora). El
/// momento de comprobar el PIN es el único en que lo tenemos en claro y,
/// por lo tanto, la única oportunidad de volver a derivarlo con los
/// parámetros actuales. Ver [PinHasher.verify].
enum PinVerification {
  /// El PIN no coincide.
  incorrect,

  /// El PIN coincide y el credencial está al día.
  correct,

  /// El PIN coincide, pero conviene volver a derivarlo y guardar el
  /// resultado: quien llame debería pedir un [PinHasher.hash] nuevo.
  correctNeedsRehash,
}

/// Deriva y comprueba el PIN de la bóveda.
///
/// Vive en `domain` sin depender de ninguna librería de criptografía: el
/// dominio necesita saber que un PIN *se deriva y se comprueba*, no con
/// qué algoritmo. La implementación concreta (`Pbkdf2PinHasher`, en la capa
/// `data`) puede cambiarse sin tocar nada de acá — y está pensada para que
/// ese cambio no invalide las bóvedas ya creadas, porque el credencial
/// guardado lleva escrito con qué algoritmo y parámetros se generó.
///
/// El PIN **nunca** se guarda ni se registra en claro, en ningún lado.
abstract interface class PinHasher {
  /// Deriva [pin] con los parámetros vigentes y devuelve el credencial
  /// serializado, listo para guardar.
  ///
  /// Dos llamadas con el mismo PIN devuelven credenciales distintos: cada
  /// una genera su propia sal aleatoria.
  Future<String> hash(String pin);

  /// Comprueba [pin] contra un [encoded] previamente producido por [hash].
  ///
  /// Lanza [CorruptedCredentialException] si [encoded] no tiene el formato
  /// esperado. Eso no es "PIN incorrecto": es una bóveda ilegible, y
  /// confundir ambas cosas dejaría a alguien reintentando para siempre un
  /// PIN que en realidad es el correcto.
  Future<PinVerification> verify({
    required String pin,
    required String encoded,
  });
}

/// El credencial guardado no se puede interpretar: formato desconocido,
/// campos faltantes o base64 inválido.
///
/// En la práctica significa almacenamiento corrupto o escrito por una
/// versión incompatible de la app.
final class CorruptedCredentialException implements Exception {
  const CorruptedCredentialException(this.reason);

  final String reason;

  @override
  String toString() => 'CorruptedCredentialException: $reason';
}
