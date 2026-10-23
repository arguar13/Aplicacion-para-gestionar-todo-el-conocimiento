import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;

/// Los temas en que se guardó lo último (F37, decisión B): con ellos arranca
/// lo próximo que se guarda, de a varios si fueron varios.
///
/// Se recuerda en el dispositivo, como el tema de la app: es una costumbre de
/// quien usa este teléfono, no un dato de la bóveda, y no viaja al unirla con
/// otra. Un tema que se borró después puede seguir acá: quien lo usa se queda
/// con los que existen.
class LastSpacesNotifier extends StateNotifier<Set<String>> {
  LastSpacesNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super({...?prefs.getStringList(_key)});

  static const _key = 'last_space_ids';

  final SharedPreferences _prefs;

  /// Lo que se acaba de guardar fue a [spaceIds]. Sin ninguno no cambia nada:
  /// algo que quedó sin tema no es una elección para lo próximo.
  Future<void> remember(Set<String> spaceIds) async {
    if (spaceIds.isEmpty) return;
    state = {...spaceIds};
    await _prefs.setStringList(_key, spaceIds.toList());
  }
}

final lastSpacesProvider =
    StateNotifierProvider<LastSpacesNotifier, Set<String>>(
      (ref) => LastSpacesNotifier(prefs: ref.watch(sharedPreferencesProvider)),
    );
