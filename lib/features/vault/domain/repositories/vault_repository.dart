import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vault/domain/entities/unlock_result.dart';

/// La bóveda: lo que guarda el PIN y decide si alguien puede entrar.
///
/// Es el reemplazo local de lo que antes era un `AuthRepository` contra un
/// backend. Sinapsis procesa y guarda todo en el dispositivo, así que no
/// hay ninguna cuenta remota contra la cual autenticarse — lo que hay es un
/// dispositivo que puede estar en manos de otra persona. Por eso el modelo
/// no es "iniciar sesión" sino "abrir la bóveda".
///
/// Ninguna implementación debe guardar, registrar ni devolver el PIN en
/// claro. Lo único que se persiste es el credencial derivado (ver
/// `PinHasher`).
abstract interface class VaultRepository {
  /// Si ya hay una bóveda creada en este dispositivo.
  ///
  /// Es lo primero que se pregunta al arrancar: define si el usuario va a
  /// la pantalla de crear la bóveda o a la de desbloquearla.
  Future<Either<Failure, bool>> exists();

  /// Crea la bóveda con [pin].
  ///
  /// Falla con [ValidationFailure] si el PIN no cumple `PinPolicy`, y con
  /// [UnexpectedFailure] si ya existía una: sobrescribirla en silencio
  /// dejaría todo el conocimiento guardado inaccesible para siempre.
  Future<Either<Failure, Unit>> create({required String pin});

  /// Intenta abrir la bóveda con [pin].
  ///
  /// El `Right` es un [UnlockResult], no un `bool`: un PIN equivocado es un
  /// resultado normal de esta operación, no un error. `Left` queda
  /// reservado para cuando la comprobación no se puede ni hacer.
  Future<Either<Failure, UnlockResult>> unlock({required String pin});

  /// Si la bóveda quedó abierta en este mismo encendido del dispositivo: se
  /// desbloqueó —o se creó— desde que el teléfono arrancó, y nadie la cerró
  /// con "Bloquear bóveda". Entonces se entra sin pedir la clave. Siempre
  /// `false` donde la plataforma no dice nada de su encendido.
  Future<Either<Failure, bool>> isOpenThisBoot();

  /// Cierra la sesión: la próxima vez que se abra la app pide la clave,
  /// aunque el dispositivo no se haya reiniciado. No borra nada más.
  Future<Either<Failure, Unit>> lock();
}
