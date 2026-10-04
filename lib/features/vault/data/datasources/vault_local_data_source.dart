import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/vault/data/models/lockout_state.dart';

/// Dónde viven el credencial de la bóveda y el contador de intentos
/// fallidos.
///
/// Se abstrae para que el repositorio no dependa de un mecanismo de
/// almacenamiento concreto, y para que los tests no necesiten los canales
/// de plataforma que usa `flutter_secure_storage`.
abstract interface class VaultLocalDataSource {
  /// El credencial derivado, o `null` si todavía no hay bóveda.
  Future<String?> readCredential();

  Future<void> writeCredential(String credential);

  /// El estado del límite de intentos. Si nunca se guardó nada, devuelve
  /// [LockoutState.initial] en lugar de `null`: "no hay registro de fallos"
  /// y "cero fallos" son lo mismo para quien llama.
  Future<LockoutState> readLockout();

  Future<void> writeLockout(LockoutState state);

  /// El encendido del dispositivo en que se abrió la bóveda por última vez,
  /// o `null` si está cerrada. Ver `DeviceBoot`.
  Future<String?> readOpenBoot();

  Future<void> writeOpenBoot(String boot);

  /// Cierra la sesión: la próxima vez que se abra la app pide la clave.
  Future<void> clearOpenBoot();
}

class SecureVaultLocalDataSource implements VaultLocalDataSource {
  SecureVaultLocalDataSource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _credentialKey = 'vault_pin_credential';
  static const _lockoutKey = 'vault_lockout_state';
  static const _openBootKey = 'vault_open_boot';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readCredential() async {
    try {
      return await _storage.read(key: _credentialKey);
    } on Exception catch (e) {
      throw CacheException(message: 'No se pudo leer la bóveda: $e');
    }
  }

  @override
  Future<void> writeCredential(String credential) async {
    try {
      await _storage.write(key: _credentialKey, value: credential);
    } on Exception catch (e) {
      throw CacheException(message: 'No se pudo guardar la bóveda: $e');
    }
  }

  @override
  Future<LockoutState> readLockout() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _lockoutKey);
    } on Exception catch (e) {
      throw CacheException(
        message: 'No se pudo leer el control de intentos: $e',
      );
    }

    if (raw == null) return LockoutState.initial;

    try {
      return LockoutState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // Un contador ilegible se trata como "sin fallos registrados" en vez
      // de propagar el error. Es la única concesión de este tipo en todo el
      // archivo, y es deliberada: dejar a alguien afuera de su propio
      // conocimiento porque un contador auxiliar se corrompió sería mucho
      // peor que regalarle unos intentos. El credencial —lo que realmente
      // decide el acceso— nunca recibe este trato: si está corrupto, falla
      // ruidosamente.
      //
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return LockoutState.initial;
    }
  }

  @override
  Future<void> writeLockout(LockoutState state) async {
    try {
      await _storage.write(key: _lockoutKey, value: jsonEncode(state.toJson()));
    } on Exception catch (e) {
      throw CacheException(
        message: 'No se pudo guardar el control de intentos: $e',
      );
    }
  }

  @override
  Future<String?> readOpenBoot() async {
    try {
      return await _storage.read(key: _openBootKey);
    } on Exception catch (e) {
      throw CacheException(message: 'No se pudo leer la sesión: $e');
    }
  }

  @override
  Future<void> writeOpenBoot(String boot) async {
    try {
      await _storage.write(key: _openBootKey, value: boot);
    } on Exception catch (e) {
      throw CacheException(message: 'No se pudo guardar la sesión: $e');
    }
  }

  @override
  Future<void> clearOpenBoot() async {
    try {
      await _storage.delete(key: _openBootKey);
    } on Exception catch (e) {
      throw CacheException(message: 'No se pudo cerrar la sesión: $e');
    }
  }
}
