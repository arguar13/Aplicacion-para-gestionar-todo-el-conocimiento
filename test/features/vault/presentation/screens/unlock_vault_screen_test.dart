import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/vault_test_doubles.dart';

void main() {
  final es = AppLocalizationsEs();

  const tPin = '246810';
  const tWrongPin = '135791';

  late FakeVaultLocalDataSource vault;
  late ProviderContainer container;

  setUp(() {
    vault = FakeVaultLocalDataSource.withPin(tPin);
    container = ProviderContainer(
      overrides: [
        vaultLocalDataSourceProvider.overrideWithValue(vault),
        pinHasherProvider.overrideWithValue(FakePinHasher()),
      ],
    );
    addTearDown(container.dispose);
  });

  Widget buildTestableWidget() {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UnlockVaultScreen(),
      ),
    );
  }

  Future<void> attempt(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(TextFormField), pin);
    await tester.tap(find.text(es.vaultUnlockAction));
    await tester.pumpAndSettle();
  }

  testWidgets('con la clave correcta, abre la bóveda', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    await attempt(tester, tPin);

    expect(
      container.read(vaultSessionControllerProvider),
      const VaultSession.unlocked(),
    );
  });

  testWidgets('con la clave equivocada, dice cuántos intentos quedan', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget());

    await attempt(tester, tWrongPin);

    expect(
      find.text(
        es.vaultUnlockWrongPasscode(PinPolicy.maxAttemptsBeforeLockout - 1),
      ),
      findsOneWidget,
    );
    expect(
      container.read(vaultSessionControllerProvider),
      isNot(const VaultSession.unlocked()),
    );
  });

  testWidgets('una clave demasiado corta cuenta como intento fallido, no se '
      'rechaza en la pantalla', (tester) async {
    // Rechazarla acá le contaría a quien lo intenta algo sobre la clave
    // guardada, y le dejaría probar claves cortas sin gastar intentos.
    await tester.pumpWidget(buildTestableWidget());

    await attempt(tester, '12');

    expect(vault.lockout.failedAttempts, 1);
  });

  testWidgets('al agotar los intentos, deshabilita el botón y muestra cuánto '
      'falta', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    for (var i = 0; i < PinPolicy.maxAttemptsBeforeLockout; i++) {
      await attempt(tester, tWrongPin);
    }

    // El mensaje de espera aparece con la duración formateada.
    expect(find.textContaining(RegExp('Demasiados intentos')), findsOneWidget);

    // Y el botón queda inerte: poder seguir apretando para recibir siempre
    // el mismo rechazo es una forma barata de frustración.
    final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(button.onPressed, isNull);

    // Se deja expirar el temporizador de la cuenta regresiva para no
    // terminar el test con uno vivo.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('el mensaje del intento anterior se limpia al empezar a '
      'escribir de nuevo', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    await attempt(tester, tWrongPin);
    expect(
      find.text(
        es.vaultUnlockWrongPasscode(PinPolicy.maxAttemptsBeforeLockout - 1),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), '2');
    await tester.pumpAndSettle();

    expect(
      find.text(
        es.vaultUnlockWrongPasscode(PinPolicy.maxAttemptsBeforeLockout - 1),
      ),
      findsNothing,
    );
  });
}
