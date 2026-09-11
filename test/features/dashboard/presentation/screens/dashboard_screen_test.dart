import 'package:cristo_es_el_salvador/core/design/theme_mode_notifier.dart';
import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/i18n/locale_notifier.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/session/session_providers.dart';
import 'package:cristo_es_el_salvador/core/session/session_state.dart';
import 'package:cristo_es_el_salvador/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cristo_es_el_salvador/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:cristo_es_el_salvador/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:cristo_es_el_salvador/features/dashboard/presentation/widgets/dashboard_bottom_nav_bar.dart';
import 'package:cristo_es_el_salvador/features/dashboard/presentation/widgets/dashboard_nav_drawer.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

/// Igual que en los otros widget tests: fake simple en vez de mockear
/// `SessionController`, para poder comprobar el estado de sesión resultante
/// tras tocar "Cerrar sesión" sin lidiar con la plantillería de un
/// `StateNotifier` mockeado.
class _FakeTokenStorage implements TokenStorage {
  String? _token = 'a-valid-token';

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> saveAccessToken(String token) async => _token = token;

  @override
  Future<void> clearTokens() async => _token = null;
}

void main() {
  late MockDashboardRepository dashboardRepository;
  late SharedPreferences prefs;

  const tUser = User(id: '1', name: 'Ana Ejemplo', email: 'ana@example.com');
  // Locale fija (no la del sistema donde corra el test) para que las
  // aserciones de texto sean deterministas.
  final l10n = AppLocalizationsEn();

  setUp(() async {
    dashboardRepository = MockDashboardRepository();
    // `SharedPreferences` real usa platform channels; `setMockInitialValues`
    // es el mock oficial del propio paquete para tests. `ThemeModeNotifier`
    // lo necesita porque `DashboardScreen` ahora tiene el botón de tema, y
    // `LocaleNotifier` porque tiene el de idioma — se fija 'en' para que el
    // texto no dependa del idioma del sistema que corre el test.
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildTestableWidget({ProviderContainer? container}) {
    final overrides = [
      dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
      tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ];
    // Igual que en `app/app.dart`: el `locale` del MaterialApp sale de
    // Riverpod, para que quede sincronizado con lo que lee el botón de
    // idioma del propio DashboardScreen.
    const child = _LocaleAwareMaterialApp();
    return container != null
        ? UncontrolledProviderScope(container: container, child: child)
        : ProviderScope(overrides: overrides, child: child);
  }

  Future<void> setViewportWidth(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('estado cargado', () {
    testWidgets('muestra el nombre y el email del usuario tras cargar', (
      tester,
    ) async {
      // Arrange
      when(
        () => dashboardRepository.getCurrentUser(),
      ).thenAnswer((_) async => const Right(tUser));

      // Act
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Assert: el nombre viaja dentro del propio mensaje traducido
      // (ver la nota en dashboard_screen.dart), ya no como Text aparte.
      expect(find.text(l10n.welcomeMessage(tUser.name)), findsOneWidget);
      expect(find.text(tUser.email), findsOneWidget);
    });
  });

  group('estado de error', () {
    testWidgets(
      'muestra el mensaje de error y el botón de reintentar, que vuelve '
      'a llamar al repositorio al tocarlo',
      (tester) async {
        // Arrange
        when(() => dashboardRepository.getCurrentUser()).thenAnswer(
          (_) async => const Left(Failure.network(message: 'Sin conexión')),
        );

        // Act
        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.loadErrorRetry));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Sin conexión'), findsOneWidget);
        verify(() => dashboardRepository.getCurrentUser()).called(2);
      },
    );
  });

  group('layout responsivo', () {
    testWidgets(
      'en pantallas anchas (>= 600) usa Drawer, no BottomNavigationBar',
      (tester) async {
        // Arrange
        when(
          () => dashboardRepository.getCurrentUser(),
        ).thenAnswer((_) async => const Right(tUser));
        await setViewportWidth(tester, 1024);

        // Act: el Drawer de Scaffold no se monta en el árbol hasta que se
        // abre (Flutter lo construye perezosamente), así que hay que tocar
        // el ícono de menú que el AppBar agrega automáticamente cuando
        // `drawer` no es null.
        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.menu), findsOneWidget);
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(DashboardNavDrawer), findsOneWidget);
        expect(find.byType(DashboardBottomNavBar), findsNothing);
      },
    );

    testWidgets(
      'en pantallas angostas (< 600) usa BottomNavigationBar, no Drawer',
      (tester) async {
        // Arrange
        when(
          () => dashboardRepository.getCurrentUser(),
        ).thenAnswer((_) async => const Right(tUser));
        await setViewportWidth(tester, 390);

        // Act
        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(DashboardBottomNavBar), findsOneWidget);
        expect(find.byType(DashboardNavDrawer), findsNothing);
        expect(find.byIcon(Icons.menu), findsNothing);
      },
    );
  });

  group('cerrar sesión', () {
    testWidgets(
      'al tocar el botón de logout, solo le avisa a SessionController '
      '(sin navegar) y la sesión queda unauthenticated',
      (tester) async {
        // Arrange
        when(
          () => dashboardRepository.getCurrentUser(),
        ).thenAnswer((_) async => const Right(tUser));
        final container = ProviderContainer(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
            tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );
        addTearDown(container.dispose);
        // La sesión arranca autenticada (así se llegaría a este dashboard
        // en la app real, vía el route guard).
        container.read(sessionControllerProvider.notifier).markAuthenticated();
        await tester.pumpWidget(buildTestableWidget(container: container));
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byIcon(Icons.logout));
        await tester.pumpAndSettle();

        // Assert
        expect(
          container.read(sessionControllerProvider),
          const SessionState.unauthenticated(),
        );
      },
    );
  });
}

/// Igual patrón que `App` (`lib/app/app.dart`): lee el `Locale` de
/// Riverpod para que el `MaterialApp` de prueba muestre el mismo idioma
/// que el botón de idioma de `DashboardScreen` cree que está activo.
class _LocaleAwareMaterialApp extends ConsumerWidget {
  const _LocaleAwareMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      locale: ref.watch(localeNotifierProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DashboardScreen(),
    );
  }
}
