import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/network/token_storage.dart';

/// `flutter_secure_storage` real usa platform channels que no existen en
/// widget tests; se sobreescribe `tokenStorageProvider` con este fake para
/// poder probar el route guard sin tocar el SO.
class _FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> saveAccessToken(String token) async => _token = token;

  @override
  Future<void> clearTokens() async => _token = null;
}

void main() {
  testWidgets('Sin sesión guardada, el guard manda a LoginScreen', (
    tester,
  ) async {
    EnvConfig.initialize(AppFlavor.dev);
    // `SharedPreferences` real usa platform channels; `setMockInitialValues`
    // es el mock oficial del propio paquete para tests. Se fija el idioma
    // para que la aserción de texto no dependa del idioma del sistema
    // donde corra el test (sin esto, cae al idioma del sistema —
    // `LocaleNotifier`— y en CI eso normalmente es inglés).
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
