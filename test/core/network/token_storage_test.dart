import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> backingStore;
  late SecureTokenStorage storage;

  setUp(() {
    // `TestFlutterSecureStoragePlatform` es el doble de prueba oficial del
    // propio paquete (in-memory, sin platform channels). `SecureTokenStorage`
    // ya acepta un `FlutterSecureStorage` inyectado justamente para esto.
    backingStore = <String, String>{};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      backingStore,
    );
    storage = SecureTokenStorage(storage: const FlutterSecureStorage());
  });

  test(
    'readAccessToken retorna null cuando no se ha guardado ningún token',
    () async {
      // Act
      final result = await storage.readAccessToken();

      // Assert
      expect(result, isNull);
    },
  );

  test(
    'saveAccessToken guarda el token y readAccessToken lo devuelve',
    () async {
      // Act
      await storage.saveAccessToken('mock-token-1');
      final result = await storage.readAccessToken();

      // Assert
      expect(result, 'mock-token-1');
    },
  );

  test('clearTokens borra el token guardado', () async {
    // Arrange
    await storage.saveAccessToken('mock-token-1');

    // Act
    await storage.clearTokens();
    final result = await storage.readAccessToken();

    // Assert
    expect(result, isNull);
  });
}
