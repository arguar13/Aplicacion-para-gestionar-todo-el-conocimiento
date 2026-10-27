import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;

/// Cómo quiere la persona que la app la llame (F42, decisión B): el saludo
/// del chat y el pie del panel de conversaciones lo usan.
///
/// Es opcional y lo escribe ella en Ajustes, «Cómo te llamo». La app **no lo
/// saca de ningún lado**: ni de una cuenta, ni de un email, ni del teléfono.
/// Se guarda solo en las preferencias de este teléfono, como el tema.
class OwnerNameNotifier extends StateNotifier<String?> {
  OwnerNameNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(normalize(prefs.getString(prefsKey)));

  static const prefsKey = 'owner_name';

  /// Lo más largo que se guarda: un nombre o un apodo, no una frase.
  static const maxLength = 40;

  final SharedPreferences _prefs;

  /// Guarda [name] tal como se lo va a mostrar ([normalize]); vacío, o
  /// `null`, lo quita.
  Future<void> rename(String? name) async {
    final clean = normalize(name);
    if (clean == state) return;
    state = clean;
    if (clean == null) {
      await _prefs.remove(prefsKey);
    } else {
      await _prefs.setString(prefsKey, clean);
    }
  }

  /// [raw] sin espacios de más —ni a los costados ni repetidos— y recortado
  /// a [maxLength]; `null` si no queda nada.
  static String? normalize(String? raw) {
    final collapsed = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return null;
    final runes = collapsed.runes;
    if (runes.length <= maxLength) return collapsed;
    return String.fromCharCodes(runes.take(maxLength)).trimRight();
  }
}

/// El nombre con que la app llama a la persona, o `null` si no puso
/// ninguno (F42). Para leerlo, `ref.watch(ownerNameProvider)`; para
/// cambiarlo, `ref.read(ownerNameProvider.notifier).rename(…)`.
final ownerNameProvider = StateNotifierProvider<OwnerNameNotifier, String?>(
  (ref) => OwnerNameNotifier(prefs: ref.watch(sharedPreferencesProvider)),
);
