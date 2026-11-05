import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';

/// Si la tarjeta de lo que suena deja ver el título en la pantalla de bloqueo
/// (F47, paso 7a-bis, decisión J precisada el 5/11): el interruptor de
/// Ajustes › Privacidad.
///
/// **De entrada, no**: con el teléfono bloqueado la tarjeta dice
/// «Reproduciendo» y el nombre de la app, sin imagen, con los mismos botones.
/// Quien quiera ver qué suena sin desbloquear, lo prende. Se guarda en las
/// preferencias de la app.
///
/// Qué se oculta y cómo lo decide el lado de Android, que es quien sabe si el
/// teléfono está bloqueado: `LockScreenPrivacy.kt`.
class LockScreenTitleNotifier extends Notifier<bool> {
  static const _key = 'media_session.show_title_on_lock_screen';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  /// Lo deja ver en la pantalla de bloqueo ([show]) o lo oculta. Cambia al
  /// instante —y con eso la tarjeta que está a la vista—, y queda guardado.
  Future<void> set({required bool show}) async {
    if (show == state) return;
    state = show;
    await ref.read(sharedPreferencesProvider).setBool(_key, show);
  }
}

final lockScreenTitleProvider = NotifierProvider<LockScreenTitleNotifier, bool>(
  LockScreenTitleNotifier.new,
);

/// Le dice al lado de Android lo que diga [lockScreenTitleProvider]: al
/// abrirse la app —antes de que suene nada— y cada vez que cambia. Hasta
/// entonces, Android oculta.
///
/// Lo mantiene vivo `App`, y no la tarjeta: la preferencia tiene que llegar
/// aunque todavía no haya sonado nada.
final lockScreenTitleSyncProvider = Provider<void>((ref) {
  final platform = ref.watch(mediaSessionPlatformProvider);
  if (!platform.isSupported) return;
  ref.listen<bool>(
    lockScreenTitleProvider,
    (_, show) => unawaited(platform.showTitleOnLockScreen(show: show)),
    fireImmediately: true,
  );
});
