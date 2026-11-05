import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/home_widgets/data/android_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/data/null_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

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

/// Si «Seguir escuchando» deja ver el título con la bóveda cerrada (F47, paso
/// 7a-bis, decisión G precisada el 5/11): el interruptor de Ajustes › Widgets.
///
/// **De entrada, no**: el widget está en la pantalla de inicio, a la vista de
/// cualquiera que mire el teléfono, y protege por defecto; quien lo quiera a
/// la vista, lo prende. Se guarda en las preferencias de la app, como lo
/// escuchado.
class ContinueListeningShowWhileLockedNotifier extends Notifier<bool> {
  static const _key = 'continue_listening.show_while_locked';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  /// Lo deja a la vista con la bóveda cerrada ([show]) o lo oculta. Cambia al
  /// instante —y con eso el widget—, y queda guardado.
  Future<void> set({required bool show}) async {
    if (show == state) return;
    state = show;
    await ref.read(sharedPreferencesProvider).setBool(_key, show);
  }
}

final continueListeningShowWhileLockedProvider =
    NotifierProvider<ContinueListeningShowWhileLockedNotifier, bool>(
      ContinueListeningShowWhileLockedNotifier.new,
    );

/// El encendido del teléfono de ahora (ver `DeviceBoot`), el mismo que anota
/// la bóveda al abrirse. Se pregunta una sola vez: no cambia mientras viva el
/// proceso, porque apagar o reiniciar el teléfono lo termina.
///
/// Si la plataforma no lo da o el canal falla, no hay encendido —un error o
/// `null`—, y «Seguir escuchando» oculta el título: el lado seguro. La bóveda,
/// por su lado, ya reporta esa falla al anotar la sesión.
final deviceBootNowProvider = FutureProvider<String?>(
  (ref) => ref.watch(deviceBootProvider)(),
);

/// Lo que se le manda a «Seguir escuchando» (F47, paso 7a-bis): lo escuchado,
/// la preferencia de [continueListeningShowWhileLockedProvider] y si la bóveda
/// está abierta, y en qué encendido. Ver [ContinueListeningDisplay]: el widget
/// decide con eso solo, también con la app muerta.
///
/// `null` mientras no se sabe qué mandar, y entonces no se le manda nada —el
/// widget sigue con lo último, que de por sí no muestra de más—:
/// - al arrancar la app, hasta que se sabe si la bóveda quedó abierta;
/// - con la bóveda recién abierta, el instante en que se pregunta el
///   encendido.
///
/// Con la bóveda cerrada —«Bloquear bóveda» o todavía sin la clave— no hay
/// encendido abierto, y se manda enseguida, sin esperar nada.
final continueListeningDisplayProvider = Provider<ContinueListeningDisplay?>((
  ref,
) {
  final session = ref.watch(vaultSessionControllerProvider);
  if (session is VaultUnknown) return null;
  String? openBoot;
  if (session is VaultUnlocked) {
    final boot = ref.watch(deviceBootNowProvider);
    if (boot.isLoading) return null;
    openBoot = boot.valueOrNull;
  }
  return ContinueListeningDisplay(
    title: ref.watch(continueListeningProvider)?.title,
    showWhileLocked: ref.watch(continueListeningShowWhileLockedProvider),
    openBoot: openBoot,
  );
});
