import 'package:cristo_es_el_salvador/app/router/splash_screen.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/session/session_providers.dart';
import 'package:cristo_es_el_salvador/core/session/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// En vez de mockear `SessionController` (un `StateNotifier`, con toda su
/// plantillería de listeners) se usa el controller real con este fake de
/// almacenamiento — más simple y prueba el comportamiento de verdad:
/// ¿terminar en `SplashScreen` deja la sesión en el estado correcto?
class _FakeTokenStorage implements TokenStorage {
  _FakeTokenStorage({String? initialToken}) : _token = initialToken;

  String? _token;

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> saveAccessToken(String token) async => _token = token;

  @override
  Future<void> clearTokens() async => _token = null;
}

void main() {
  testWidgets(
    'muestra un CircularProgressIndicator mientras resuelve la sesión',
    (tester) async {
      // Arrange
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(
            _FakeTokenStorage(initialToken: 'a-valid-token'),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Act: un solo frame, antes de que la lectura async del storage
      // resuelva.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SplashScreen()),
        ),
      );

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'al montar, dispara checkInitialSession y termina en authenticated '
    'cuando hay un token guardado',
    (tester) async {
      // Arrange
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(
            _FakeTokenStorage(initialToken: 'a-valid-token'),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Act
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SplashScreen()),
        ),
      );
      // No `pumpAndSettle`: el spinner indeterminado nunca deja de pedir
      // frames dentro de este test aislado (no hay router que navegue
      // fuera del splash), así que colgaría esperando animaciones que no
      // van a terminar. Un par de `pump()` alcanza para drenar el único
      // `await` de `checkInitialSession`.
      await tester.pump();
      await tester.pump();

      // Assert
      expect(
        container.read(sessionControllerProvider),
        const SessionState.authenticated(),
      );
    },
  );

  testWidgets(
    'al montar, dispara checkInitialSession y termina en unauthenticated '
    'cuando no hay token guardado',
    (tester) async {
      // Arrange
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        ],
      );
      addTearDown(container.dispose);

      // Act
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SplashScreen()),
        ),
      );
      // No `pumpAndSettle`: el spinner indeterminado nunca deja de pedir
      // frames dentro de este test aislado (no hay router que navegue
      // fuera del splash), así que colgaría esperando animaciones que no
      // van a terminar. Un par de `pump()` alcanza para drenar el único
      // `await` de `checkInitialSession`.
      await tester.pump();
      await tester.pump();

      // Assert
      expect(
        container.read(sessionControllerProvider),
        const SessionState.unauthenticated(),
      );
    },
  );
}
