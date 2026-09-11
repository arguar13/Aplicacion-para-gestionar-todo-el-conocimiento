import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/vault/data/models/lockout_state.dart';
import 'package:sinapsis/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';
import 'package:sinapsis/features/vault/domain/entities/unlock_result.dart';
import 'package:sinapsis/features/vault/domain/services/pin_hasher.dart';

import '../../../../support/vault_test_doubles.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late MockTelemetryService telemetry;

  const tPin = '246810';
  const tWrongPin = '135791';

  /// Un reloj detenido, para que el test controle el paso del tiempo en vez
  /// de esperarlo.
  var now = DateTime(2026, 9, 11, 10);

  setUp(() {
    telemetry = MockTelemetryService();
    now = DateTime(2026, 9, 11, 10);
  });

  VaultRepositoryImpl buildRepository({
    required FakeVaultLocalDataSource vault,
    PinHasher? hasher,
  }) {
    return VaultRepositoryImpl(
      localDataSource: vault,
      pinHasher: hasher ?? FakePinHasher(),
      telemetry: telemetry,
      clock: () => now,
    );
  }

  group('exists', () {
    test('es true cuando hay un credencial guardado', () async {
      final repo = buildRepository(
        vault: FakeVaultLocalDataSource.withPin(tPin),
      );

      expect(await repo.exists(), right<Failure, bool>(true));
    });

    test('es false en un dispositivo sin bóveda', () async {
      final repo = buildRepository(vault: FakeVaultLocalDataSource());

      expect(await repo.exists(), right<Failure, bool>(false));
    });

    test('edge case: un credencial vacío cuenta como "no hay bóveda", no '
        'como una bóveda válida', () async {
      final repo = buildRepository(
        vault: FakeVaultLocalDataSource(credential: ''),
      );

      expect(await repo.exists(), right<Failure, bool>(false));
    });
  });

  group('create', () {
    test('deriva el PIN y lo guarda', () async {
      final vault = FakeVaultLocalDataSource();
      final repo = buildRepository(vault: vault);

      final result = await repo.create(pin: tPin);

      expect(result.isRight(), isTrue);
      expect(vault.credential, isNotNull);
    });

    test('lo que se guarda NO es el PIN en claro', () async {
      final vault = FakeVaultLocalDataSource();
      // Con el hasher real, no el falso: esta comprobación pierde sentido
      // si el doble guarda el PIN a propósito.
      final repo = buildRepository(vault: vault, hasher: _RealisticHasher());

      await repo.create(pin: tPin);

      expect(vault.credential, isNot(contains(tPin)));
    });

    test('rechaza un PIN más corto que la política', () async {
      final vault = FakeVaultLocalDataSource();
      final repo = buildRepository(vault: vault);

      final result = await repo.create(pin: '123');

      expect(result.isLeft(), isTrue);
      result.getLeft().fold(
        () => fail('se esperaba un Failure'),
        (f) => expect(f, isA<ValidationFailure>()),
      );
      // Y no escribió nada: un PIN rechazado no debe dejar rastro.
      expect(vault.credential, isNull);
    });

    test('se NIEGA a sobrescribir una bóveda existente', () async {
      // El peor error posible de esta app: pisar el credencial deja todo el
      // conocimiento guardado inaccesible para siempre, sin aviso.
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      final original = vault.credential;
      final repo = buildRepository(vault: vault);

      final result = await repo.create(pin: 'otraclave');

      expect(result.isLeft(), isTrue);
      expect(vault.credential, original);
    });

    test('deja el contador de intentos en cero', () async {
      final vault = FakeVaultLocalDataSource(
        lockout: const LockoutState(failedAttempts: 3),
      );
      final repo = buildRepository(vault: vault);

      await repo.create(pin: tPin);

      expect(vault.lockout.failedAttempts, 0);
    });
  });

  group('unlock', () {
    test('con el PIN correcto, concede acceso', () async {
      final repo = buildRepository(
        vault: FakeVaultLocalDataSource.withPin(tPin),
      );

      final result = await repo.unlock(pin: tPin);

      expect(result.getRight().toNullable(), const UnlockResult.granted());
    });

    test('un acceso concedido borra el historial de fallos, incluidas las '
        'tandas acumuladas', () async {
      // Si las tandas no se borraran, quien se equivocó dos veces hace un
      // mes arrancaría la próxima espera en una hora en vez de 30 segundos.
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      await vault.writeLockout(
        const LockoutState(failedAttempts: 2, completedRounds: 3),
      );
      final repo = buildRepository(vault: vault);

      await repo.unlock(pin: tPin);

      expect(vault.lockout.failedAttempts, 0);
      expect(vault.lockout.completedRounds, 0);
    });

    test('con el PIN equivocado, lo rechaza y descuenta un intento', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      final repo = buildRepository(vault: vault);

      final result = await repo.unlock(pin: tWrongPin);

      expect(
        result.getRight().toNullable(),
        const UnlockResult.rejected(
          remainingAttempts: PinPolicy.maxAttemptsBeforeLockout - 1,
        ),
      );
      expect(vault.lockout.failedAttempts, 1);
    });

    test('el contador sobrevive: los fallos se persisten, así que cerrar y '
        'reabrir la app no los borra', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);

      // Primer "arranque": dos intentos fallidos.
      final first = buildRepository(vault: vault);
      await first.unlock(pin: tWrongPin);
      await first.unlock(pin: tWrongPin);

      // Segundo "arranque": repositorio nuevo, mismo almacenamiento.
      final second = buildRepository(vault: vault);
      final result = await second.unlock(pin: tWrongPin);

      expect(
        result.getRight().toNullable(),
        const UnlockResult.rejected(
          remainingAttempts: PinPolicy.maxAttemptsBeforeLockout - 3,
        ),
      );
    });

    test('al agotar los intentos, impone una espera', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      final repo = buildRepository(vault: vault);

      UnlockResult? last;
      for (var i = 0; i < PinPolicy.maxAttemptsBeforeLockout; i++) {
        last = (await repo.unlock(pin: tWrongPin)).getRight().toNullable();
      }

      expect(last, isA<UnlockLockedOut>());
      expect(
        (last! as UnlockLockedOut).until,
        now.add(PinPolicy.lockoutDurations.first),
      );
    });

    test('durante la espera NO se comprueba el PIN: ni siquiera el correcto '
        'abre la bóveda', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      await vault.writeLockout(
        LockoutState(
          completedRounds: 1,
          lockedUntil: now.add(const Duration(minutes: 5)),
        ),
      );
      // Un hasher que explota si alguien lo llama: la prueba de que la
      // espera corta el camino antes de derivar nada. Además de ahorrar
      // trabajo, evita que el tiempo de respuesta delate si el PIN era el
      // correcto.
      final repo = buildRepository(
        vault: vault,
        hasher: const _ExplodingHasher(),
      );

      final result = await repo.unlock(pin: tPin);

      expect(result.getRight().toNullable(), isA<UnlockLockedOut>());
    });

    test('pasada la espera, vuelve a aceptar intentos', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      await vault.writeLockout(
        LockoutState(
          completedRounds: 1,
          lockedUntil: now.add(const Duration(minutes: 5)),
        ),
      );
      final repo = buildRepository(vault: vault);

      // El reloj avanza más allá del bloqueo.
      now = now.add(const Duration(minutes: 6));

      expect(
        (await repo.unlock(pin: tPin)).getRight().toNullable(),
        const UnlockResult.granted(),
      );
    });

    test(
      'cada tanda de fallos impone una espera más larga que la anterior',
      () async {
        final vault = FakeVaultLocalDataSource.withPin(tPin);
        final repo = buildRepository(vault: vault);

        final durations = <Duration>[];
        for (var round = 0; round < 3; round++) {
          for (var i = 0; i < PinPolicy.maxAttemptsBeforeLockout; i++) {
            final r = (await repo.unlock(
              pin: tWrongPin,
            )).getRight().toNullable();
            if (r is UnlockLockedOut) {
              durations.add(r.until.difference(now));
              // Se salta la espera para poder medir la tanda siguiente.
              now = r.until.add(const Duration(seconds: 1));
            }
          }
        }

        expect(durations, hasLength(3));
        expect(durations[1], greaterThan(durations[0]));
        expect(durations[2], greaterThan(durations[1]));
      },
    );

    test('un credencial derivado con parámetros viejos se vuelve a derivar '
        'al entrar', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      final writesBefore = vault.credentialWrites;
      final repo = buildRepository(
        vault: vault,
        hasher: FakePinHasher(
          forcedVerification: PinVerification.correctNeedsRehash,
        ),
      );

      final result = await repo.unlock(pin: tPin);

      expect(result.getRight().toNullable(), const UnlockResult.granted());
      // Se cuenta la escritura y no se compara el valor: el hasher falso
      // produce siempre el mismo credencial para el mismo PIN, así que
      // comparar strings no distinguiría "se re-derivó" de "no se tocó".
      expect(vault.credentialWrites, writesBefore + 1);
    });

    test('un credencial al día NO se reescribe: solo se re-deriva cuando '
        'hace falta', () async {
      final vault = FakeVaultLocalDataSource.withPin(tPin);
      final writesBefore = vault.credentialWrites;
      final repo = buildRepository(vault: vault);

      await repo.unlock(pin: tPin);

      expect(vault.credentialWrites, writesBefore);
    });

    test('una bóveda dañada NO se reporta como PIN incorrecto', () async {
      // Decirle "clave incorrecta" a alguien que escribió la suya lo deja
      // reintentando para siempre, sin ninguna pista de que el problema es
      // el almacenamiento.
      final repo = buildRepository(
        vault: FakeVaultLocalDataSource.withPin(tPin),
        hasher: const CorruptedPinHasher(),
      );

      final result = await repo.unlock(pin: tPin);

      expect(result.isLeft(), isTrue);
      result.getLeft().fold(
        () => fail('se esperaba un Failure'),
        (f) => expect(f, isA<CacheFailure>()),
      );
    });

    test(
      'una bóveda dañada se reporta a telemetría: siempre es un defecto',
      () async {
        final repo = buildRepository(
          vault: FakeVaultLocalDataSource.withPin(tPin),
          hasher: const CorruptedPinHasher(),
        );

        await repo.unlock(pin: tPin);

        verify(
          () => telemetry.recordError(
            any<dynamic>(),
            any<StackTrace?>(),
            hint: any(named: 'hint'),
          ),
        ).called(1);
      },
    );

    test(
      'desbloquear sin bóveda creada falla en vez de conceder acceso',
      () async {
        final repo = buildRepository(vault: FakeVaultLocalDataSource());

        final result = await repo.unlock(pin: tPin);

        expect(result.isLeft(), isTrue);
      },
    );
  });
}

/// Un hasher que no guarda el PIN en claro, para el test que comprueba
/// justamente eso. No deriva de verdad —sería lento— pero tampoco deja el
/// PIN visible.
class _RealisticHasher implements PinHasher {
  @override
  Future<String> hash(String pin) async =>
      'derivado:${pin.codeUnits.fold<int>(7, (a, b) => a * 31 + b)}';

  @override
  Future<PinVerification> verify({
    required String pin,
    required String encoded,
  }) async => encoded == await hash(pin)
      ? PinVerification.correct
      : PinVerification.incorrect;
}

/// Falla si alguien lo llama. Sirve para probar que cierto camino NO llega
/// a derivar el PIN.
class _ExplodingHasher implements PinHasher {
  const _ExplodingHasher();

  @override
  Future<String> hash(String pin) async =>
      fail('no debería derivarse nada en este caso');

  @override
  Future<PinVerification> verify({
    required String pin,
    required String encoded,
  }) async => fail('no debería comprobarse el PIN durante la espera');
}
