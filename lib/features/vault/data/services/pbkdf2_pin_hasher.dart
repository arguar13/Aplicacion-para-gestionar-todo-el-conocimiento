import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/vault/domain/services/pin_hasher.dart';

/// Lo que cruza al isolate de trabajo. Solo tipos primitivos: todo lo que
/// se pasa entre isolates tiene que poder copiarse, y un `Pbkdf2` con su
/// algoritmo de MAC adentro no puede.
typedef _DerivationRequest = ({String pin, List<int> salt, int iterations});

/// [PinHasher] con PBKDF2-HMAC-SHA256 (NIST SP 800-132).
///
/// ## Formato del credencial
///
/// Se guarda una sola cadena con todo lo necesario para volver a
/// comprobarlo, separado por `$` (el mismo esquema que usan `passlib` o
/// los hashes de contraseña de UNIX):
///
/// ```text
/// pbkdf2-sha256$120000$<sal en base64>$<clave derivada en base64>
/// ```
///
/// Llevar el algoritmo y sus parámetros *dentro* del credencial es lo que
/// permite cambiarlos más adelante sin dejar afuera a quien ya tiene una
/// bóveda creada: al comprobar el PIN se lee con qué parámetros fue
/// derivado, y si quedaron por debajo de los actuales se informa con
/// [PinVerification.correctNeedsRehash] para volver a derivarlo en el
/// único momento en que el PIN está disponible en claro.
///
/// ## Qué protege esto realmente
///
/// Conviene ser honesto con lo que un KDF puede y no puede hacer acá. Un
/// PIN tiene poca entropía —un millón de combinaciones con seis dígitos—,
/// así que ningún número de iteraciones lo vuelve resistente a fuerza
/// bruta si alguien consigue el credencial; y PBKDF2-SHA256 además se
/// acelera muchísimo en GPU. Lo que protege de verdad es la suma de tres
/// cosas, y el KDF es la menos importante:
///
/// 1. El credencial vive en el almacén seguro del sistema operativo
///    (Keychain en iOS, Keystore en Android), no en un archivo cualquiera.
/// 2. El límite de intentos con espera creciente, que hace inviable probar
///    combinaciones a través de la propia interfaz de la app.
/// 3. Estas iteraciones, que encarecen cada intento si alguien llegara a
///    extraer el credencial del almacén.
///
/// ## Por qué 120 000 iteraciones, y por qué en otro isolate
///
/// El costo se midió, no se estimó: en la VM de Dart sobre x86, una
/// derivación tarda ~324 ms con 50 000 iteraciones, ~735 ms con 120 000 y
/// ~3,7 s con las 600 000 que recomienda OWASP para contraseñas de
/// servidor. Un teléfono de gama media es varias veces más lento que eso.
///
/// Con 600 000, desbloquear la app costaría diez segundos o más en un
/// dispositivo modesto; y como se explicó arriba, ese gasto no compra
/// seguridad real en este escenario, donde el control efectivo es el
/// almacén del sistema y el límite de intentos. 120 000 es un punto
/// defendible: encarece un ataque offline sin volver insufrible la
/// operación más frecuente de la app.
///
/// Lo que sí resuelve el problema de fondo es dónde corre. La derivación
/// se manda a un isolate de trabajo con [compute], así el hilo de la
/// interfaz queda libre: el indicador de progreso gira suave y la app
/// responde mientras tanto. Bloquear la UI durante uno o dos segundos se
/// ve exactamente igual que una app colgada.
class Pbkdf2PinHasher implements PinHasher {
  Pbkdf2PinHasher({Random? random}) : _random = random ?? Random.secure();

  static const _algorithmId = 'pbkdf2-sha256';
  static const _iterations = 120000;
  static const _derivedKeyBits = 256;
  static const _saltLengthBytes = 32;
  static const _fieldSeparator = r'$';

  /// Inyectable para que los tests puedan usar una fuente determinista.
  /// En producción siempre es `Random.secure()`, que toma su entropía del
  /// sistema operativo: un `Random()` común es predecible y volvería la
  /// sal inútil.
  final Random _random;

  @override
  Future<String> hash(String pin) async {
    final salt = _generateSalt();
    final derived = await _derive((
      pin: pin,
      salt: salt,
      iterations: _iterations,
    ));

    return [
      _algorithmId,
      '$_iterations',
      base64.encode(salt),
      base64.encode(derived),
    ].join(_fieldSeparator);
  }

  @override
  Future<PinVerification> verify({
    required String pin,
    required String encoded,
  }) async {
    final credential = _ParsedCredential.parse(encoded);

    // Se deriva con las iteraciones que dice el credencial, no con las
    // actuales: una bóveda creada por una versión anterior tiene que poder
    // comprobarse con *sus* parámetros antes de re-derivarse con los de
    // ahora.
    final derived = await _derive((
      pin: pin,
      salt: credential.salt,
      iterations: credential.iterations,
    ));

    if (!_constantTimeEquals(derived, credential.derivedKey)) {
      return PinVerification.incorrect;
    }

    return credential.iterations < _iterations
        ? PinVerification.correctNeedsRehash
        : PinVerification.correct;
  }

  Future<List<int>> _derive(_DerivationRequest request) {
    return compute(_derivePbkdf2, request, debugLabel: 'derivación del PIN');
  }

  /// Compara dos secuencias de bytes sin cortar en el primer byte distinto.
  ///
  /// Una comparación normal (`==` sobre listas, o un bucle con `return
  /// false`) termina apenas encuentra una diferencia, y ese tiempo de más o
  /// de menos le dice a quien lo intenta cuántos bytes acertó — con lo que
  /// el problema deja de ser adivinar la clave entera y pasa a ser
  /// adivinarla byte por byte. Acá se acumulan todas las diferencias con
  /// XOR y recién al final se mira el resultado, así el trabajo es el mismo
  /// acierte o no.
  ///
  /// Está escrita a mano a propósito. `cryptography` trae
  /// `constantTimeBytesEquality`, pero vive en `src/helpers/` y no está
  /// exportada: usarla obligaría a importar el interior de otro paquete, y
  /// eso se rompe en cualquier publicación menor. La parte difícil y
  /// delicada —el KDF— sigue viniendo del paquete; esto es un bucle XOR de
  /// seis líneas, un patrón estándar que se verifica de un vistazo.
  ///
  /// La salida temprana por longitudes distintas es deliberada y no filtra
  /// nada útil: el largo de la clave derivada es fijo y público (32 bytes),
  /// no es el secreto.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  Uint8List _generateSalt() {
    final salt = Uint8List(_saltLengthBytes);
    for (var i = 0; i < _saltLengthBytes; i++) {
      salt[i] = _random.nextInt(256);
    }
    return salt;
  }
}

/// Corre en el isolate de trabajo, no en el de la interfaz.
///
/// Tiene que ser una función de nivel superior (o un método estático):
/// [compute] necesita poder mandarle una referencia al otro isolate, y un
/// cierre que capture `this` no se puede enviar.
Future<List<int>> _derivePbkdf2(_DerivationRequest request) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: request.iterations,
    bits: Pbkdf2PinHasher._derivedKeyBits,
  );

  final secretKey = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(request.pin)),
    nonce: request.salt,
  );
  return secretKey.extractBytes();
}

/// Un credencial ya descompuesto en sus partes. Todo el manejo de formato
/// —y todos los modos en que puede venir mal— queda encerrado acá.
class _ParsedCredential {
  const _ParsedCredential({
    required this.iterations,
    required this.salt,
    required this.derivedKey,
  });

  factory _ParsedCredential.parse(String encoded) {
    final parts = encoded.split(Pbkdf2PinHasher._fieldSeparator);
    if (parts.length != 4) {
      throw CorruptedCredentialException(
        'se esperaban 4 campos separados por "\$", llegaron ${parts.length}',
      );
    }

    if (parts[0] != Pbkdf2PinHasher._algorithmId) {
      throw CorruptedCredentialException(
        'algoritmo desconocido "${parts[0]}"; esta versión de la app solo '
        'sabe leer "${Pbkdf2PinHasher._algorithmId}"',
      );
    }

    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) {
      throw CorruptedCredentialException(
        'el número de iteraciones "${parts[1]}" no es un entero positivo',
      );
    }

    try {
      return _ParsedCredential(
        iterations: iterations,
        salt: base64.decode(parts[2]),
        derivedKey: base64.decode(parts[3]),
      );
      // `base64.decode` lanza FormatException, que acá significa exactamente
      // lo mismo que los casos de arriba —credencial ilegible— y tiene que
      // llegar a quien llama con el mismo tipo.
    } on FormatException catch (e) {
      throw CorruptedCredentialException('base64 inválido: ${e.message}');
    }
  }

  final int iterations;
  final List<int> salt;
  final List<int> derivedKey;
}
