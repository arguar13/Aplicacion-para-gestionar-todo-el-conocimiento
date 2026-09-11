import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_error_screen.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/network/token_storage.dart';
import 'package:sinapsis/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:sinapsis/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

/// Mismo enfoque que `splash_screen_test.dart`: el `SessionController` real
/// con un almacenamiento falso, en vez de mockear el controller entero.
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
  late MockDashboardRepository dashboardRepository;
  late SharedPreferences prefs;

  final en = AppLocalizationsEn();
  final es = AppLocalizationsEs();

  final tUri = Uri.parse('/ruta-que-no-existe');
  const tUser = User(id: '1', name: 'Ana Ejemplo', email: 'ana@example.com');

  setUp(() async {
    // Mismo contrato que cumplen los entry points de flavor y
    // `widget_test.dart`: `goRouterProvider` lee `EnvConfig.current` (para
    // decidir `debugLogDiagnostics`), y sin inicializar salta el assert
    // que exige haber elegido un flavor antes de construir la app.
    EnvConfig.initialize(AppFlavor.dev);
    dashboardRepository = MockDashboardRepository();
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildIsolatedScreen({Locale locale = const Locale('es')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteErrorScreen(uri: tUri),
    );
  }

  group('contenido', () {
    testWidgets('muestra título, explicación y la dirección que falló', (
      tester,
    ) async {
      await tester.pumpWidget(buildIsolatedScreen());

      expect(find.text(es.routeNotFoundTitle), findsOneWidget);
      expect(find.text(es.routeNotFoundMessage), findsOneWidget);
      expect(find.text(tUri.toString()), findsOneWidget);
    });

    testWidgets('la dirección es seleccionable, para poder copiarla al '
        'reportar el problema', (tester) async {
      await tester.pumpWidget(buildIsolatedScreen());

      final address = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(address.data, tUri.toString());
    });

    testWidgets('el texto está traducido: en inglés no queda ni una cadena '
        'en español', (tester) async {
      await tester.pumpWidget(buildIsolatedScreen(locale: const Locale('en')));

      expect(find.text(en.routeNotFoundTitle), findsOneWidget);
      expect(find.text(en.routeNotFoundMessage), findsOneWidget);
      expect(find.text(en.routeNotFoundAction), findsOneWidget);
      // La regresión concreta que motivó esta pantalla: el mensaje estaba
      // escrito a mano en español dentro de `app_router.dart`, así que
      // salía igual con la app en inglés.
      expect(find.text(es.routeNotFoundTitle), findsNothing);
    });
  });

  group('integración con el router real', () {
    /// Monta el `GoRouter` de la app —no uno de mentira— para probar que el
    /// `errorBuilder` está efectivamente cableado a esta pantalla.
    ///
    /// El dashboard se deja cargar de verdad (repositorio mockeado
    /// devolviendo un usuario) en vez de dejarlo en `loading`: su
    /// `CircularProgressIndicator` es una animación indeterminada que pide
    /// frames para siempre, y `pumpAndSettle` colgaría esperando a que
    /// termine.
    Widget buildRoutedApp(ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: ref.watch(goRouterProvider),
          ),
        ),
      );
    }

    ProviderContainer buildContainer() {
      when(
        dashboardRepository.getCurrentUser,
      ).thenAnswer((_) async => right<Failure, User>(tUser));

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(
            _FakeTokenStorage(initialToken: 'a-valid-token'),
          ),
          dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('una URL que no corresponde a ninguna ruta cae en '
        'RouteErrorScreen', (tester) async {
      // Arrange: con sesión activa. El `redirect` global corre antes que el
      // matching de rutas, así que sin sesión NINGUNA dirección llega al
      // `errorBuilder` — el guard las manda todas a /login primero. Es el
      // comportamiento correcto (no le confirmamos a un visitante anónimo
      // qué rutas existen), pero implica que esta pantalla solo es
      // alcanzable con la sesión ya resuelta.
      final container = buildContainer();

      await tester.pumpWidget(buildRoutedApp(container));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);

      // Act
      container.read(goRouterProvider).go(tUri.toString());
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(RouteErrorScreen), findsOneWidget);
      expect(find.text(es.routeNotFoundTitle), findsOneWidget);
    });

    testWidgets('el botón devuelve a un destino válido en vez de dejar al '
        'usuario encerrado', (tester) async {
      // Arrange
      final container = buildContainer();

      await tester.pumpWidget(buildRoutedApp(container));
      await tester.pumpAndSettle();

      container.read(goRouterProvider).go(tUri.toString());
      await tester.pumpAndSettle();
      expect(find.byType(RouteErrorScreen), findsOneWidget);

      // Act
      await tester.tap(find.text(es.routeNotFoundAction));
      await tester.pumpAndSettle();

      // Assert: el botón va al splash y es el route guard el que elige el
      // destino final — por eso esta pantalla no necesita saber nada de la
      // sesión. Con sesión activa, eso termina en el dashboard.
      expect(find.byType(RouteErrorScreen), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });
}
