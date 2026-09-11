import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/vault/data/datasources/vault_local_data_source.dart';
import 'package:sinapsis/features/vault/data/models/lockout_state.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';
import 'package:sinapsis/features/vault/domain/entities/unlock_result.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';
import 'package:sinapsis/features/vault/domain/services/pin_hasher.dart';

class VaultRepositoryImpl implements VaultRepository {
  const VaultRepositoryImpl({
    required VaultLocalDataSource localDataSource,
    required PinHasher pinHasher,
    required TelemetryService telemetry,
    Clock clock = DateTime.now,
  }) : _localDataSource = localDataSource,
       _pinHasher = pinHasher,
       _telemetry = telemetry,
       _clock = clock;

  final VaultLocalDataSource _localDataSource;
  final PinHasher _pinHasher;
  final TelemetryService _telemetry;
  final Clock _clock;

  @override
  Future<Either<Failure, bool>> exists() async {
    try {
      final credential = await _localDataSource.readCredential();
      return right(credential != null && credential.isNotEmpty);
    } on CacheException catch (e) {
      return left(Failure.cache(message: e.message));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'VaultRepositoryImpl.exists'));
    }
  }

  @override
  Future<Either<Failure, Unit>> create({required String pin}) async {
    if (!PinPolicy.isValid(pin)) {
      return left(
        const Failure.validation(
          message: 'La clave no cumple la longitud mínima.',
        ),
      );
    }

    try {
      // Sobrescribir una bóveda existente dejaría todo lo guardado adentro
      // inaccesible para siempre, sin aviso y sin vuelta atrás. Que llegue
      // acá con una bóveda ya creada es un error de programación —el router
      // no debería haber mostrado esta pantalla—, así que se corta antes de
      // tocar nada.
      final alreadyExists = await _localDataSource.readCredential();
      if (alreadyExists != null && alreadyExists.isNotEmpty) {
        return left(
          const Failure.unexpected(
            message: 'Ya existe una bóveda en este dispositivo.',
          ),
        );
      }

      await _localDataSource.writeCredential(await _pinHasher.hash(pin));
      await _localDataSource.writeLockout(LockoutState.initial);
      return right(unit);
    } on CacheException catch (e) {
      return left(Failure.cache(message: e.message));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'VaultRepositoryImpl.create'));
    }
  }

  @override
  Future<Either<Failure, UnlockResult>> unlock({required String pin}) async {
    try {
      final now = _clock();
      final lockout = await _localDataSource.readLockout();

      // La espera se comprueba ANTES de derivar nada. Además de ser lo
      // correcto, evita regalar información por el costado: si durante el
      // bloqueo se siguiera comprobando el PIN, el tiempo de respuesta
      // delataría si era el correcto.
      if (lockout.isLockedAt(now)) {
        return right(UnlockResult.lockedOut(until: lockout.lockedUntil!));
      }

      final credential = await _localDataSource.readCredential();
      if (credential == null || credential.isEmpty) {
        return left(
          const Failure.unexpected(
            message: 'No hay ninguna bóveda creada en este dispositivo.',
          ),
        );
      }

      final verification = await _pinHasher.verify(
        pin: pin,
        encoded: credential,
      );

      return switch (verification) {
        PinVerification.incorrect => right(
          await _registerFailedAttempt(lockout, now),
        ),
        PinVerification.correct => right(await _grantAccess()),
        // El PIN es correcto pero fue derivado con parámetros que hoy
        // quedaron cortos. Este es el único instante en que el PIN está
        // disponible en claro, así que es acá o nunca: se vuelve a derivar
        // con los parámetros actuales y se guarda.
        PinVerification.correctNeedsRehash => right(
          await _grantAccess(rehashOf: pin),
        ),
      };
    } on CorruptedCredentialException catch (e, stackTrace) {
      // Una bóveda ilegible no es un PIN equivocado, y decirle al usuario
      // que se equivocó lo dejaría reintentando para siempre su propia
      // clave. Se reporta porque siempre es un defecto: almacenamiento
      // dañado o escrito por una versión incompatible.
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'VaultRepositoryImpl.unlock: credencial ilegible',
      );
      return left(
        const Failure.cache(
          message:
              'Los datos de la bóveda están dañados y no se pueden leer. '
              'Habrá que restaurar una copia de seguridad.',
        ),
      );
    } on CacheException catch (e) {
      return left(Failure.cache(message: e.message));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'VaultRepositoryImpl.unlock'));
    }
  }

  /// Suma un fallo y decide si todavía quedan intentos o si empieza la
  /// espera.
  Future<UnlockResult> _registerFailedAttempt(
    LockoutState lockout,
    DateTime now,
  ) async {
    final updated = lockout.afterFailedAttempt(now);
    await _localDataSource.writeLockout(updated);

    final lockedUntil = updated.lockedUntil;
    return updated.isLockedAt(now)
        ? UnlockResult.lockedOut(until: lockedUntil!)
        : UnlockResult.rejected(remainingAttempts: updated.remainingAttempts);
  }

  /// Abre la bóveda: borra el historial de fallos —incluidas las tandas
  /// acumuladas, para que la próxima espera no arranque donde quedó la
  /// anterior— y, si hace falta, re-deriva el credencial.
  Future<UnlockResult> _grantAccess({String? rehashOf}) async {
    await _localDataSource.writeLockout(LockoutState.initial);

    if (rehashOf != null) {
      await _localDataSource.writeCredential(await _pinHasher.hash(rehashOf));
    }

    return const UnlockResult.granted();
  }

  /// Catch-all deliberado, por el mismo motivo que en el resto de la app:
  /// el `fromJson` generado lanza `TypeError` ante datos inesperados, y un
  /// `TypeError` es un `Error`, no un `Exception`. Atrapar solo `Exception`
  /// lo dejaría escapar y quien llamó se quedaría esperando una respuesta
  /// que nunca llega. Siempre es un defecto, así que además se reporta.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
