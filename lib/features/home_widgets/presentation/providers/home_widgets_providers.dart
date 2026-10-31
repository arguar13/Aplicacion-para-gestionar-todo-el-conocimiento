import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/home_widgets/data/android_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/data/null_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';

/// Los widgets de la pantalla de inicio: en Android, los de verdad; en la
/// web y en el escritorio, unos que no hacen nada
/// ([HomeScreenWidgets.isSupported] es `false`).
final homeScreenWidgetsProvider = Provider<HomeScreenWidgets>(
  (ref) => kIsWeb || defaultTargetPlatform != TargetPlatform.android
      ? const NullHomeScreenWidgets()
      : AndroidHomeScreenWidgets(),
);

/// Lo último que se escuchó (F47, paso 7): lo que muestra «Seguir
/// escuchando» y adónde lleva tocarlo.
///
/// **Es el único punto que lo alimenta**: lo llama `HomeWidgetsBinding` cada
/// vez que empieza a sonar algo con el foco de audio de la app —lo que
/// muestra la tarjeta de la sesión de medios (F47, paso 2b)—: el lector en
/// voz alta, un audio o un video, y lo que se registre después, como el
/// podcast.
///
/// Se guarda en las preferencias de la app: el widget lo sigue mostrando con
/// la app cerrada, y tocarlo después de reiniciar el teléfono tiene que saber
/// adónde ir. La dirección queda solo acá —el widget recibe el título—, así
/// que un toque nunca trae de afuera a qué pantalla ir.
class ContinueListeningNotifier extends Notifier<ContinueListening?> {
  static const _titleKey = 'continue_listening.title';
  static const _locationKey = 'continue_listening.location';

  @override
  ContinueListening? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final title = prefs.getString(_titleKey);
    final location = prefs.getString(_locationKey);
    if (title == null || location == null) return null;
    return ContinueListening(title: title, location: location);
  }

  /// Se escuchó [title], desde la pantalla de [location]. Lo mismo dos veces
  /// seguidas no cambia nada.
  Future<void> listened({
    required String title,
    required String location,
  }) async {
    final next = ContinueListening(title: title, location: location);
    if (next == state) return;
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_titleKey, title);
    await prefs.setString(_locationKey, location);
  }
}

final continueListeningProvider =
    NotifierProvider<ContinueListeningNotifier, ContinueListening?>(
      ContinueListeningNotifier.new,
    );
