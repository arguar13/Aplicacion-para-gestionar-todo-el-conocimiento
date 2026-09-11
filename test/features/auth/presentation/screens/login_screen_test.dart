import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/network/token_storage.dart';
import 'package:sinapsis/features/auth/domain/repositories/auth_repository.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_providers.dart';
import 'package:sinapsis/features/auth/presentation/screens/login_screen.dart';
import 'package:sinapsis/features/auth/presentation/widgets/primary_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// `flutter_secure_storage` real usa platform channels que no existen en
/// widget tests. `SessionController` (que construye internamente
/// `authNotifierProvider`) lo necesita, así que se sobreescribe con este
/// fake — igual que en `test/widget_test.dart`.
class _FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<void> saveAccessToken(String token) async {}

  @override
  Future<void> clearTokens() async {}
}

void main() {
  late MockAuthRepository authRepository;

  const tEmail = 'ana@example.com';
  const tPassword = 'secret123';
  const tUser = User(id: '1', name: 'Ana Ejemplo', email: tEmail);
  // Locale fija (no la del sistema donde corra el test) para que las
  // aserciones de texto sean deterministas.
  final l10n = AppLocalizationsEn();

  setUp(() {
    authRepository = MockAuthRepository();
  });

  /// Envuelve `LoginScreen` con lo mínimo que necesita para vivir en un
  /// test: `MaterialApp` (Navigator/Directionality/Localizations, ahora
  /// con los delegates de `AppLocalizations`) y el `ProviderScope` con el
  /// repositorio real reemplazado por el mock — así el widget nunca toca
  /// Dio ni internet.
  Widget buildTestableWidget() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(),
      ),
    );
  }

  group('renderizado inicial', () {
    testWidgets(
      'dibuja el campo de email, el de contraseña y el botón Ingresar',
      (tester) async {
        // Arrange
        await tester.pumpWidget(buildTestableWidget());

        // Act: ninguna interacción — se verifica el primer render.
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(l10n.loginTitle), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(find.text(l10n.emailLabel), findsOneWidget);
        expect(find.text(l10n.passwordLabel), findsOneWidget);
        expect(find.byType(PrimaryButton), findsOneWidget);
        expect(find.text(l10n.loginButton), findsOneWidget);
      },
    );
  });

  group('validación de formulario', () {
    testWidgets(
      'al tocar Ingresar con los campos vacíos, muestra los errores de '
      'validación y nunca llama al repositorio',
      (tester) async {
        // Arrange
        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(l10n.loginButton));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(l10n.emailEmptyError), findsOneWidget);
        expect(find.text(l10n.passwordEmptyError), findsOneWidget);
        verifyNever(
          () => authRepository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        );
      },
    );
  });

  group('flujo de carga', () {
    testWidgets('mientras el login está en curso, el botón se deshabilita y '
        'muestra un CircularProgressIndicator en vez del texto', (
      tester,
    ) async {
      // Arrange: el repositorio nunca resuelve durante este test, para
      // poder inspeccionar el estado "loading" a mitad de camino.
      final pendingLogin = Completer<Either<Failure, User>>();
      when(
        () => authRepository.login(email: tEmail, password: tPassword),
      ).thenAnswer((_) => pendingLogin.future);
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, tEmail);
      await tester.enterText(find.byType(TextFormField).last, tPassword);

      // Act: un solo `pump` — con un CircularProgressIndicator
      // indeterminado en pantalla, `pumpAndSettle` nunca terminaría
      // (sigue animando y programando frames).
      await tester.tap(find.text(l10n.loginButton));
      await tester.pump();

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(l10n.loginButton), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      // Cleanup: se resuelve el Future pendiente para no dejar un
      // `setState`/cambio de estado colgando tras terminar el test.
      pendingLogin.complete(const Right(tUser));
      await tester.pump();
    });
  });
}
