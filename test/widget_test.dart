import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/create_vault_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';

import 'support/fake_shared_content_listener.dart';
import 'support/vault_test_doubles.dart';

/// Prueba de arriba abajo del route guard: se monta la `App` entera y se
/// comprueba en qué pantalla termina el usuario según el estado de la
/// bóveda.
///
/// Es el único test que cubre la bifurcación que trajo el modelo local: con
/// un backend había una sola puerta de entrada (el login), y acá hay dos
/// —crear y desbloquear— que dependen de si este dispositivo ya tiene
/// bóveda. Equivocar esa decisión es de los errores más caros posibles:
/// llevar a la pantalla de creación a alguien que ya tiene datos guardados
/// le sugiere que los perdió.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    // Mismo contrato que cumplen los entry points de flavor: el router lee
    // `EnvConfig.current` al construirse.
    EnvConfig.initialize(AppFlavor.dev);
    // `SharedPreferences` real usa canales de plataforma;
    // `setMockInitialValues` es el mock oficial del propio paquete. Se fija
    // el idioma para que las aserciones no dependan del sistema donde corra
    // el test.
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeVaultLocalDataSource vault,
    FakeSharedContentListener? sharedContent,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultLocalDataSourceProvider.overrideWithValue(vault),
          pinHasherProvider.overrideWithValue(FakePinHasher()),
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Sin un sistema operativo real, el plugin de compartir no tiene
          // con qué hablar.
          sharedContentListenerProvider.overrideWithValue(
            sharedContent ?? FakeSharedContentListener(),
          ),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin bóveda en el dispositivo, el guard lleva a crearla', (
    tester,
  ) async {
    await pumpApp(tester, vault: FakeVaultLocalDataSource());

    expect(find.byType(CreateVaultScreen), findsOneWidget);
    expect(find.byType(UnlockVaultScreen), findsNothing);
  });

  testWidgets('con una bóveda ya creada, el guard lleva a desbloquearla y '
      'NO a crear una nueva', (tester) async {
    await pumpApp(tester, vault: FakeVaultLocalDataSource.withPin('246810'));

    expect(find.byType(UnlockVaultScreen), findsOneWidget);
    expect(find.byType(CreateVaultScreen), findsNothing);
  });
}
