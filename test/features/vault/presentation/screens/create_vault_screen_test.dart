import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/create_vault_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/vault_test_doubles.dart';

/// La pantalla que faltaba: el proyecto tenía toda la plomería de registro
/// —caso de uso, notifier, fuente de datos y sus tests— sin ninguna
/// interfaz que la usara ni ruta que llevara a ella.
void main() {
  final es = AppLocalizationsEs();

  const tValidPin = '246810';

  late FakeVaultLocalDataSource vault;
  late ProviderContainer container;

  setUp(() {
    vault = FakeVaultLocalDataSource();
    container = ProviderContainer(
      overrides: [
        vaultLocalDataSourceProvider.overrideWithValue(vault),
        deviceBootProvider.overrideWithValue(testDeviceBoot),
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
        home: CreateVaultScreen(),
      ),
    );
  }

  Finder passcodeField() => find.byType(TextFormField).first;
  Finder confirmationField() => find.byType(TextFormField).last;

  group('contenido', () {
    testWidgets('advierte que la clave no se puede recuperar antes de que el '
        'usuario la elija', (tester) async {
      await tester.pumpWidget(buildTestableWidget());

      // No es un detalle de redacción: sin servidor no existe un "olvidé mi
      // contraseña", y perder la clave es perder todo lo guardado. Decirlo
      // después de elegirla no sirve de nada.
      expect(find.text(es.vaultCreateSubtitle), findsOneWidget);
      expect(find.text(es.vaultCreateTitle), findsOneWidget);
    });
  });

  group('validación del formulario', () {
    testWidgets('rechaza una clave más corta que el mínimo, sin llegar a '
        'tocar el almacenamiento', (tester) async {
      await tester.pumpWidget(buildTestableWidget());

      await tester.enterText(passcodeField(), '123');
      await tester.enterText(confirmationField(), '123');
      await tester.tap(find.text(es.vaultCreateAction));
      await tester.pumpAndSettle();

      expect(
        find.text(es.vaultPasscodeTooShortError(PinPolicy.minLength)),
        findsOneWidget,
      );
      expect(vault.credential, isNull);
    });

    testWidgets('rechaza dos claves que no coinciden', (tester) async {
      await tester.pumpWidget(buildTestableWidget());

      await tester.enterText(passcodeField(), tValidPin);
      await tester.enterText(confirmationField(), '999999');
      await tester.tap(find.text(es.vaultCreateAction));
      await tester.pumpAndSettle();

      expect(find.text(es.vaultPasscodeMismatchError), findsOneWidget);
      expect(vault.credential, isNull);
    });
  });

  group('creación', () {
    testWidgets('con datos válidos, guarda el credencial y deja la bóveda '
        'abierta', (tester) async {
      await tester.pumpWidget(buildTestableWidget());

      await tester.enterText(passcodeField(), tValidPin);
      await tester.enterText(confirmationField(), tValidPin);
      await tester.tap(find.text(es.vaultCreateAction));
      await tester.pumpAndSettle();

      expect(vault.credential, isNotNull);
      // Recién creada, la bóveda queda abierta: acaba de escribir la clave
      // dos veces, volver a pedirla sería puro trámite.
      expect(
        container.read(vaultSessionControllerProvider),
        const VaultSession.unlocked(),
      );
    });

    testWidgets('lo guardado no contiene la clave en claro', (tester) async {
      await tester.pumpWidget(buildTestableWidget());

      await tester.enterText(passcodeField(), tValidPin);
      await tester.enterText(confirmationField(), tValidPin);
      await tester.tap(find.text(es.vaultCreateAction));
      await tester.pumpAndSettle();

      // Con el doble de hasher esto es trivialmente cierto sólo si el
      // credencial pasó por él; si alguien cableara el PIN directo al
      // almacenamiento, este test lo encontraría.
      expect(vault.credential, isNot(tValidPin));
    });
  });
}
