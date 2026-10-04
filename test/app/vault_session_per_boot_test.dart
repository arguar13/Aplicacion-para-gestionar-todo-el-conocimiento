import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';

import '../support/library_harness.dart';
import '../support/vault_test_doubles.dart';

/// La clave se pide una vez por encendido del teléfono —al apagarlo o
/// reiniciarlo— o después de "Bloquear bóveda"; no cada vez que se abre la
/// app (pedido del usuario). Con la app entera montada, con su router.
void main() {
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// La bóveda de prueba del arnés: su PIN es 246810.
  FakeVaultLocalDataSource vault() =>
      harness.container.read(vaultLocalDataSourceProvider)
          as FakeVaultLocalDataSource;

  /// Abre la app como al tocar su ícono: resuelve sola en qué estado está la
  /// bóveda.
  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Los estados por los que pasa la app, de a uno, como los entrega Flutter
  /// en Android: nunca salta de `paused` a `resumed` sin pasar por el medio.
  Future<void> goThrough(
    WidgetTester tester,
    List<AppLifecycleState> states,
  ) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  group('al abrir la app', () {
    testWidgets('en el mismo encendido en que se desbloqueó, entra sin la '
        'clave', (tester) async {
      await vault().writeOpenBoot(kTestDeviceBoot);

      await openApp(tester);

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('después de apagar o reiniciar el teléfono, pide la clave', (
      tester,
    ) async {
      await vault().writeOpenBoot('un-arranque-anterior');

      await openApp(tester);

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
    });

    testWidgets('si nunca se desbloqueó, pide la clave', (tester) async {
      await openApp(tester);

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
    });
  });

  group('con la bóveda abierta', () {
    testWidgets('cerrar la app desde recientes no la cierra', (tester) async {
      await vault().writeOpenBoot(kTestDeviceBoot);
      await openApp(tester);

      // F29: el motor sigue vivo al cerrar la app, y Android le avisa a Dart
      // que la ventana se fue.
      await goThrough(tester, [
        ...toBackground,
        AppLifecycleState.detached,
        AppLifecycleState.resumed,
      ]);

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('minimizarla no la cierra', (tester) async {
      await vault().writeOpenBoot(kTestDeviceBoot);
      await openApp(tester);

      await goThrough(tester, [...toBackground, ...toForeground]);

      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('"Bloquear bóveda" la cierra, y la próxima vez pide la clave '
        'aunque el teléfono no se haya reiniciado', (tester) async {
      await vault().writeOpenBoot(kTestDeviceBoot);
      await openApp(tester);

      await harness.container
          .read(vaultSessionControllerProvider.notifier)
          .lock();
      await tester.pumpAndSettle();

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
      expect(vault().openBoot, isNull);
    });
  });
}
