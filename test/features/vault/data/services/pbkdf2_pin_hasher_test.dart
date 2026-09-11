import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/data/services/pbkdf2_pin_hasher.dart';
import 'package:sinapsis/features/vault/domain/services/pin_hasher.dart';

void main() {
  late Pbkdf2PinHasher hasher;

  const tPin = '246810';
  const tWrongPin = '135791';

  setUp(() {
    hasher = Pbkdf2PinHasher();
  });

  /// Arma un credencial con un número de iteraciones arbitrario, para poder
  /// simular una bóveda creada por una versión anterior de la app. Replica
  /// a mano el formato que produce `hash()`, que es justamente lo que se
  /// quiere probar que sigue siendo legible.
  Future<String> buildCredentialWith({
    required int iterations,
    required String pin,
    String algorithmId = 'pbkdf2-sha256',
  }) async {
    final salt = List<int>.generate(32, (i) => i);
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);

    return [
      algorithmId,
      '$iterations',
      base64.encode(salt),
      base64.encode(await key.extractBytes()),
    ].join(r'$');
  }

  group('hash', () {
    test('produce un credencial con el algoritmo y los parámetros '
        'embebidos, para poder migrar de KDF sin invalidar bóvedas', () async {
      final encoded = await hasher.hash(tPin);

      final parts = encoded.split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], 'pbkdf2-sha256');
      expect(int.parse(parts[1]), greaterThanOrEqualTo(120000));
      // Sal de 32 bytes y clave derivada de 32 bytes (256 bits).
      expect(base64.decode(parts[2]), hasLength(32));
      expect(base64.decode(parts[3]), hasLength(32));
    });

    test('el PIN no aparece en ninguna parte del credencial', () async {
      final encoded = await hasher.hash(tPin);

      // La comprobación evidente, y también sobre el contenido decodificado
      // —un base64 podría estar escondiendo el PIN en claro—.
      expect(encoded, isNot(contains(tPin)));
      final parts = encoded.split(r'$');
      expect(
        utf8.decode(base64.decode(parts[3]), allowMalformed: true),
        isNot(contains(tPin)),
      );
    });

    test('dos derivaciones del MISMO PIN dan credenciales distintos: cada '
        'una usa su propia sal', () async {
      final first = await hasher.hash(tPin);
      final second = await hasher.hash(tPin);

      expect(first, isNot(second));
      // Y la diferencia está en la sal, no en un capricho del formato.
      expect(first.split(r'$')[2], isNot(second.split(r'$')[2]));
    });

    test('con la misma fuente de aleatoriedad y el mismo PIN, la derivación '
        'es determinista', () async {
      // Dos hashers con la misma semilla producen la misma sal, así que el
      // credencial tiene que ser idéntico. Prueba que no se está mezclando
      // ninguna otra fuente de variación (la hora, un contador) dentro de
      // la derivación.
      final a = Pbkdf2PinHasher(random: Random(1234));
      final b = Pbkdf2PinHasher(random: Random(1234));

      expect(await a.hash(tPin), await b.hash(tPin));
    });
  });

  group('verify', () {
    test('acepta el PIN correcto', () async {
      final encoded = await hasher.hash(tPin);

      expect(
        await hasher.verify(pin: tPin, encoded: encoded),
        PinVerification.correct,
      );
    });

    test('rechaza un PIN incorrecto', () async {
      final encoded = await hasher.hash(tPin);

      expect(
        await hasher.verify(pin: tWrongPin, encoded: encoded),
        PinVerification.incorrect,
      );
    });

    test('rechaza un PIN que solo difiere en el último dígito', () async {
      final encoded = await hasher.hash('246810');

      expect(
        await hasher.verify(pin: '246811', encoded: encoded),
        PinVerification.incorrect,
      );
    });

    test('rechaza el PIN vacío contra una bóveda real', () async {
      final encoded = await hasher.hash(tPin);

      expect(
        await hasher.verify(pin: '', encoded: encoded),
        PinVerification.incorrect,
      );
    });

    test('un credencial viejo con menos iteraciones sigue siendo válido, '
        'pero pide re-derivarse', () async {
      // El escenario real: la bóveda se creó con una versión de la app que
      // usaba menos iteraciones. El PIN es el correcto y el usuario tiene
      // que poder entrar; lo que corresponde es aprovechar que el PIN está
      // en claro en este instante para volver a derivarlo más fuerte.
      final legacy = await buildCredentialWith(iterations: 1000, pin: tPin);

      expect(
        await hasher.verify(pin: tPin, encoded: legacy),
        PinVerification.correctNeedsRehash,
      );
    });

    test('un credencial viejo con el PIN equivocado sigue siendo rechazo, '
        'no una invitación a re-derivar', () async {
      final legacy = await buildCredentialWith(iterations: 1000, pin: tPin);

      expect(
        await hasher.verify(pin: tWrongPin, encoded: legacy),
        PinVerification.incorrect,
      );
    });
  });

  group('credenciales corruptos', () {
    // Un credencial ilegible NO es "PIN incorrecto". Confundirlos dejaría a
    // alguien reintentando para siempre un PIN que en realidad es el suyo,
    // sin ninguna pista de que el problema es el almacenamiento.
    test('con menos campos de los esperados', () async {
      expect(
        () => hasher.verify(pin: tPin, encoded: r'pbkdf2-sha256$120000'),
        throwsA(isA<CorruptedCredentialException>()),
      );
    });

    test('con un algoritmo que esta versión no sabe leer', () async {
      final future = buildCredentialWith(
        iterations: 120000,
        pin: tPin,
        algorithmId: 'argon2id',
      );

      expect(
        () async => hasher.verify(pin: tPin, encoded: await future),
        throwsA(
          isA<CorruptedCredentialException>().having(
            (e) => e.reason,
            'reason',
            contains('argon2id'),
          ),
        ),
      );
    });

    test('con un número de iteraciones que no es un entero', () async {
      expect(
        () => hasher.verify(
          pin: tPin,
          encoded: r'pbkdf2-sha256$muchas$c2FsdA==$a2V5',
        ),
        throwsA(isA<CorruptedCredentialException>()),
      );
    });

    test('con cero iteraciones: un entero válido, pero sin sentido como '
        'parámetro de un KDF', () async {
      expect(
        () =>
            hasher.verify(pin: tPin, encoded: r'pbkdf2-sha256$0$c2FsdA==$a2V5'),
        throwsA(isA<CorruptedCredentialException>()),
      );
    });

    test('con base64 inválido en la sal', () async {
      expect(
        () => hasher.verify(
          pin: tPin,
          encoded: r'pbkdf2-sha256$120000$no-es-base64!!$a2V5',
        ),
        throwsA(
          isA<CorruptedCredentialException>().having(
            (e) => e.reason,
            'reason',
            contains('base64'),
          ),
        ),
      );
    });

    test('con la cadena vacía', () async {
      expect(
        () => hasher.verify(pin: tPin, encoded: ''),
        throwsA(isA<CorruptedCredentialException>()),
      );
    });
  });
}
