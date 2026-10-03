import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/dev_seed/domain/repositories/sample_library_ledger.dart';

/// [SampleLibraryLedger] en las preferencias de la app, el mismo almacén que
/// el tema y el idioma.
///
/// No en la base: es una marca de la función de desarrollo, no contenido de
/// la bóveda, y no tiene por qué viajar en una copia de seguridad ni
/// sincronizarse con otro dispositivo.
class SharedPreferencesSampleLibraryLedger implements SampleLibraryLedger {
  SharedPreferencesSampleLibraryLedger(this._prefs);

  static const _key = 'sample_library_loaded_ids';

  final SharedPreferences _prefs;

  @override
  Set<String> loadedIds() => {...?_prefs.getStringList(_key)};

  @override
  Future<void> markLoaded(String id) async {
    final loaded = loadedIds();
    if (!loaded.add(id)) return;
    await _prefs.setStringList(_key, loaded.toList());
  }
}
