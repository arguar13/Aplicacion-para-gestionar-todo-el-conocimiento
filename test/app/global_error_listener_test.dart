import 'package:cristo_es_el_salvador/app/global_error_listener.dart';
import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/core/error/global_error_bus.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              GlobalErrorListener(child: child ?? const SizedBox.shrink()),
          // `ScaffoldMessenger.showSnackBar` exige al menos un `Scaffold`
          // descendiente montado (a diferencia de lo documentado para el
          // fallback host, en esta versión de Flutter lo requiere igual).
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    return container;
  }

  testWidgets('un NetworkException reportado al bus global muestra el SnackBar '
      'amigable correspondiente, sin importar qué pantalla esté montada', (
    tester,
  ) async {
    // Arrange
    final container = await pumpApp(tester);

    // Act
    container
        .read(globalErrorNotifierProvider.notifier)
        .report(const NetworkException(message: 'irrelevante para la UI'));
    await tester.pump();
    await tester.pump();

    // Assert: el mensaje mostrado es el amigable/traducido, no el crudo
    // del backend.
    expect(find.text(l10n.globalErrorNetwork), findsOneWidget);
  });

  testWidgets(
    'un UnauthorizedException muestra el mensaje de sesión expirada',
    (tester) async {
      // Arrange
      final container = await pumpApp(tester);

      // Act
      container
          .read(globalErrorNotifierProvider.notifier)
          .report(const UnauthorizedException(message: 'irrelevante'));
      await tester.pump();
      await tester.pump();

      // Assert
      expect(find.text(l10n.globalErrorUnauthorized), findsOneWidget);
    },
  );

  testWidgets('un ServerException muestra el mensaje genérico de servidor', (
    tester,
  ) async {
    // Arrange
    final container = await pumpApp(tester);

    // Act
    container
        .read(globalErrorNotifierProvider.notifier)
        .report(const ServerException(message: 'irrelevante'));
    await tester.pump();
    await tester.pump();

    // Assert
    expect(find.text(l10n.globalErrorServer), findsOneWidget);
  });

  testWidgets(
    'un segundo error reemplaza el SnackBar anterior en vez de apilarlo',
    (tester) async {
      // Arrange
      final container = await pumpApp(tester);
      final notifier = container.read(globalErrorNotifierProvider.notifier);

      // Act: separados por `await tester.pump()`, no encadenables en un
      // cascade.
      // ignore: cascade_invocations
      notifier.report(const NetworkException(message: 'primero'));
      await tester.pump();
      await tester.pump();
      notifier.report(const ServerException(message: 'segundo'));
      await tester.pump();
      await tester.pump();

      // Assert
      expect(find.text(l10n.globalErrorNetwork), findsNothing);
      expect(find.text(l10n.globalErrorServer), findsOneWidget);
    },
  );
}
