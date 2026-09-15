import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';

/// Recuerda qué modelo eligió la persona que usa la app —Gemma 4 E4B o
/// Gemma 3n E4B— entre reinicios, mismo criterio que `ThemeModeNotifier`.
///
/// Por defecto [ChatModelOption.gemma4E4b]: quien ya tenía la app y nunca
/// tocó nada sigue apuntando al mismo modelo de siempre, sin que un cambio
/// de versión le pida —sin haberlo pedido— bajar unos GB más pesados de
/// golpe.
class ChatModelOptionNotifier extends StateNotifier<ChatModelOption> {
  ChatModelOptionNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _prefsKey = 'chat_model_option';

  final SharedPreferences _prefs;

  static ChatModelOption _readInitial(SharedPreferences prefs) {
    final stored = prefs.getString(_prefsKey);
    return ChatModelOption.values.firstWhere(
      (option) => option.name == stored,
      orElse: () => ChatModelOption.gemma4E4b,
    );
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
