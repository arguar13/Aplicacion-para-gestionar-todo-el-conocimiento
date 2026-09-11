import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/splash_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

import '../../support/vault_test_doubles.dart';

/// En vez de mockear `VaultSessionController` (un `StateNotifier`, con toda
/// su plantillería de listeners) se usa el controlador real sobre un
/// almacenamiento falso — más simple y prueba el comportamiento de verdad:
/// ¿montar el splash deja la bóveda en el estado correcto?
void main() {
  ProviderContainer buildContainer({required FakeVaultLocalDataSource vault}) {
    final container = ProviderContainer(
      overrides: [
        vaultLocalDataSourceProvider.overrideWithValue(vault),
        pinHasherProvider.overrideWithValue(FakePinHasher()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('muestra un indicador de progreso mientras lee el '
      'almacenamiento', (tester) async {
    // Arrange: con una demora real en la lectura. Sin ella, el
    // almacenamiento falso responde antes del primer frame y el estado
    // intermedio nunca llega a existir — no porque la app no lo tenga, sino
    // porque el doble es demasiado rápido para que se note.
    final container = buildContainer(
      vault: FakeVaultLocalDataSource.withPin(
        '246810',
        delay: const Duration(milliseconds: 50),
      ),
    );

    // Act: un solo frame, antes de que la lectura asíncrona resuelva.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SplashScreen()),
      ),
    );

    // Assert
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      container.read(vaultSessionControllerProvider),
      const VaultSession.unknown(),
    );

    // Se deja terminar la lectura para no dejar un temporizador vivo al
    // final del test.
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('con una bóveda guardada, termina en `locked`', (tester) async {
    // Arrange
    final container = buildContainer(
      vault: FakeVaultLocalDataSource.withPin('246810'),
    );

    // Act
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SplashScreen()),
      ),
    );
    // No `pumpAndSettle`: el indicador indeterminado nunca deja de pedir
    // frames dentro de este test aislado (no hay router que navegue fuera
    // del splash), así que colgaría esperando animaciones que no van a
    // terminar. Un par de `pump()` alcanza para drenar el único `await`.
    await tester.pump();
    await tester.pump();

    // Assert
    expect(
      container.read(vaultSessionControllerProvider),
      const VaultSession.locked(),
    );
  });

  testWidgets('sin bóveda guardada, termina en `absent`', (tester) async {
    // Arrange
    final container = buildContainer(vault: FakeVaultLocalDataSource());

    // Act
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SplashScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Assert
    expect(
      container.read(vaultSessionControllerProvider),
      const VaultSession.absent(),
    );
  });
}
