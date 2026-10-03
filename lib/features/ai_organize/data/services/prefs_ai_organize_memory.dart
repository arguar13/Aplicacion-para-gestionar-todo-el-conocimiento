import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_memory.dart';

/// [AiOrganizeMemory] en las preferencias del dispositivo, como los
/// interruptores de Ajustes › IA: son datos de este dispositivo, no de la
/// bóveda —otra copia de la bóveda empieza a organizar sola cuando se abre
/// ahí—.
///
/// El largo de cada nota va en una clave por nota: son unos pocos bytes por
/// nota que la IA organizó, y leer uno no obliga a leer los demás.
class PrefsAiOrganizeMemory implements AiOrganizeMemory {
  PrefsAiOrganizeMemory({
    required SharedPreferences prefs,
    required Clock clock,
  }) : _prefs = prefs,
       _clock = clock;

  final SharedPreferences _prefs;
  final Clock _clock;

  static const _epochKey = 'ai_organize_epoch';
  static String _noteKey(String itemId) => 'ai_organize_note_length_$itemId';

  @override
  Future<DateTime> epoch() async {
    final stored = _prefs.getInt(_epochKey);
    if (stored != null) return DateTime.fromMillisecondsSinceEpoch(stored);
    final now = _clock();
    await _prefs.setInt(_epochKey, now.millisecondsSinceEpoch);
    return now;
  }

  @override
  int? noteLengthSeen(String itemId) => _prefs.getInt(_noteKey(itemId));

  @override
  Future<void> rememberNoteLength(String itemId, int length) =>
      _prefs.setInt(_noteKey(itemId), length);
}
