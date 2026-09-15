import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;

/// Cuánto se agranda o achica el texto del modo de lectura respecto del
/// tamaño de base, entre reinicios — mismo criterio que `ThemeModeNotifier`.
///
/// Quien lee un libro entero en la pantalla, y no solo un fragmento como en
/// el detalle de un elemento, es quien más se beneficia de ajustar la letra
/// a su gusto: hay tanta variación en preferencia de lectura como en
/// personas, y lo que entra cómodo en una pantalla chica no siempre es lo
/// que se prefiere en una grande.
class ReaderFontScaleNotifier extends StateNotifier<double> {
  ReaderFontScaleNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _prefsKey = 'reader_font_scale';

  /// Un paso de más o de menos no cambia mucho a simple vista; cinco pasos
  /// sí, sin llegar a un extremo donde el texto deje de caber cómodo en la
  /// tarjeta de la página.
  static const min = 0.8;
  static const max = 1.6;
  static const _step = 0.1;

  final SharedPreferences _prefs;

  static double _readInitial(SharedPreferences prefs) {
    final stored = prefs.getDouble(_prefsKey);
    if (stored == null) return 1;
    return stored.clamp(min, max);
  }

  Future<void> increase() => _setScale(state + _step);
  Future<void> decrease() => _setScale(state - _step);

  Future<void> _setScale(double value) async {
    final clamped = double.parse(value.clamp(min, max).toStringAsFixed(2));
    state = clamped;
    await _prefs.setDouble(_prefsKey, clamped);
  }
}

final readerFontScaleNotifierProvider =
    StateNotifierProvider<ReaderFontScaleNotifier, double>((ref) {
      return ReaderFontScaleNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      );
    });
