import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstrae dónde se guarda el token de sesión para que `AuthInterceptor`
/// no dependa de un mecanismo de almacenamiento concreto.
abstract interface class TokenStorage {
  Future<String?> readAccessToken();
  Future<void> saveAccessToken(String token);
  Future<void> clearTokens();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'auth_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  @override
  Future<void> clearTokens() => _storage.delete(key: _accessTokenKey);
}

/// Vive aquí (junto a lo que provee) en vez de en `network_providers.dart`
/// para que `core/session` pueda depender de él sin arrastrar `dioProvider`
/// — y `network_providers.dart` pueda depender de `core/session` sin ciclo.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});
