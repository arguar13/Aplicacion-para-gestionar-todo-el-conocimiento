import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/util/clock.dart';

/// Lo que la cola de la IA recuerda en las preferencias del dispositivo
/// —[epoch], un `AiOrganizeEpoch`—, como los interruptores de Ajustes › IA:
/// son datos de este dispositivo, no de la bóveda —otra copia de la bóveda
/// empieza a organizar sola cuando se abre ahí—.
class PrefsAiOrganizeMemory {
  PrefsAiOrganizeMemory({
    required SharedPreferences prefs,
    required Clock clock,
  }) : _prefs = prefs,
       _clock = clock;

  final SharedPreferences _prefs;
  final Clock _clock;

  static const _epochKey = 'ai_organize_epoch';

  /// Ver `AiOrganizeEpoch`.
  Future<DateTime> epoch() async {
    final stored = _prefs.getInt(_epochKey);
    if (stored != null) return DateTime.fromMillisecondsSinceEpoch(stored);
    final now = _clock();
    await _prefs.setInt(_epochKey, now.millisecondsSinceEpoch);
    return now;
  }
}
