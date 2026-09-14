import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';

/// Recuerda el token de acceso de Hugging Face entre reinicios de la app,
/// igual que `ThemeModeNotifier` recuerda el tema.
///
/// Hace falta porque el modelo de Gemma vive en un repositorio protegido:
/// sin un token válido, la descarga falla siempre con 401, para cualquiera
/// —ver `GemmaChatModelManager`—. `null` significa que todavía no se guardó
/// ninguno.
class HuggingFaceTokenNotifier extends StateNotifier<String?> {
  HuggingFaceTokenNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _prefsKey = 'hugging_face_token';

  final SharedPreferences _prefs;

  static String? _readInitial(SharedPreferences prefs) {
    final stored = prefs.getString(_prefsKey);
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  Future<void> setToken(String token) async {
    final trimmed = token.trim();
    state = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await _prefs.remove(_prefsKey);
    } else {
      await _prefs.setString(_prefsKey, trimmed);
    }
  }
}

final huggingFaceTokenNotifierProvider =
    StateNotifierProvider<HuggingFaceTokenNotifier, String?>((ref) {
      return HuggingFaceTokenNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      );
    });
