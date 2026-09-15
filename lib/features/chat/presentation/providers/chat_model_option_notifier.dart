import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';

/// Si esta plataforma es un escritorio "de verdad" —Windows, macOS o
/// Linux, ni web ni un teléfono—: lo único que puede correr
/// [ChatModelOption.gemma412b], porque el propio modelo no se publica para
/// Android ni iOS (ver la decisión 27 en docs/arquitectura.md).
///
/// `defaultTargetPlatform` y no `dart:io.Platform` a propósito: este
/// archivo también lo importa la web —`ChatModelScreen` corre ahí, aunque
/// el chat en sí no tenga sentido sin descargar nada—, y `dart:io` no
/// compila en ese target sin un archivo condicional aparte. `kIsWeb` se
/// comprueba primero porque, en la web, `defaultTargetPlatform` refleja el
/// sistema operativo *debajo* del navegador —Windows, macOS...— y sin este
/// chequeo se confundiría "Chrome en Windows" con Windows de escritorio de
/// verdad.
bool get isDesktopChatPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Las opciones que esta plataforma puede de verdad descargar y correr.
/// [ChatModelOption.gemma412b] queda afuera fuera de escritorio — ver
/// [isDesktopChatPlatform] — para que el selector de la pantalla de
/// descarga nunca ofrezca algo que va a fallar.
List<ChatModelOption> get availableChatModelOptions => [
  ChatModelOption.gemma4E4b,
  ChatModelOption.gemma3nE4b,
  if (isDesktopChatPlatform) ChatModelOption.gemma412b,
];

/// A quién apunta esta plataforma si nunca se tocó el selector: en
/// escritorio, a la opción más pesada e inteligente de las tres —es la
/// única plataforma donde correrla no compite con la batería ni con la
/// memoria limitada de un teléfono—; en cualquier otro lado, a
/// [ChatModelOption.gemma4E4b] de siempre.
ChatModelOption get defaultChatModelOption => isDesktopChatPlatform
    ? ChatModelOption.gemma412b
    : ChatModelOption.gemma4E4b;

/// Recuerda qué modelo eligió la persona que usa la app entre reinicios,
/// mismo criterio que `ThemeModeNotifier`.
class ChatModelOptionNotifier extends StateNotifier<ChatModelOption> {
  ChatModelOptionNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _prefsKey = 'chat_model_option';

  final SharedPreferences _prefs;

  static ChatModelOption _readInitial(SharedPreferences prefs) {
    final stored = prefs.getString(_prefsKey);
    final storedOption = ChatModelOption.values
        .where((option) => option.name == stored)
        .firstOrNull;
    // Nunca se restaura una opción que esta plataforma no puede correr:
    // `SharedPreferences` es local al dispositivo, así que en la práctica
    // esto no pasa solo cambiando de plataforma —pero si alguna vez pasa
    // (una copia de seguridad restaurada en otro dispositivo, por
    // ejemplo), es mejor caer al valor por defecto que ofrecer una
    // descarga de casi 7 GB que después no va a andar.
    if (storedOption != null &&
        availableChatModelOptions.contains(storedOption)) {
      return storedOption;
    }
    return defaultChatModelOption;
  }

  Future<void> select(ChatModelOption option) async {
    state = option;
    await _prefs.setString(_prefsKey, option.name);
  }
}

final chatModelOptionNotifierProvider =
    StateNotifierProvider<ChatModelOptionNotifier, ChatModelOption>((ref) {
      return ChatModelOptionNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      );
    });
