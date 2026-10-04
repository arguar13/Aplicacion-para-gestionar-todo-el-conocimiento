import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';

import '../support/library_harness.dart';

/// F29: al cerrar la app —deslizarla fuera de "recientes"— el motor de
/// Flutter sigue vivo para que el trabajo largo termine, y Android le avisa a
/// Dart que la ventana se fue (`detached`). Antes cerrar la app se llevaba
/// el Dart entero y la bóveda quedaba cerrada sola; ahora la cierra la
/// `App`, y esta prueba la monta entera, con su router, sobre una bóveda
/// abierta.
void main() {
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpOpenApp(WidgetTester tester) async {
    harness.container
        .read(vaultSessionControllerProvider.notifier)
        .markUnlocked();
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

  testWidgets('cerrar la app cierra la bóveda: al volver pide el PIN', (
    tester,
  ) async {
    await pumpOpenApp(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await goThrough(tester, [
      ...toBackground,
      AppLifecycleState.detached,
      AppLifecycleState.resumed,
    ]);

    expect(find.byType(UnlockVaultScreen), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);
  });

  testWidgets('minimizarla no la cierra: al volver sigue donde estaba', (
    tester,
  ) async {
    await pumpOpenApp(tester);

    await goThrough(tester, [...toBackground, ...toForeground]);

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(UnlockVaultScreen), findsNothing);
  });
}
