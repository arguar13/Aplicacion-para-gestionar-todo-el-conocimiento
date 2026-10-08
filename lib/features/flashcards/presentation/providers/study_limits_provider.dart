import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';

/// Los límites por día de estudio (F31, decisión 69): cuántas nuevas y cuántos
/// repasos, como mucho.
///
/// Mismo almacén que el tema y el idioma de la app: es una preferencia de este
/// teléfono, no un dato de la bóveda —otro dispositivo puede estudiar a otro
/// ritmo—.
class StudyLimitsNotifier extends StateNotifier<StudyLimits> {
  StudyLimitsNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(
        StudyLimits(
          newPerDay:
              _valid(prefs.getInt(_newKey)) ?? StudyLimits.defaultNewPerDay,
          reviewsPerDay:
              _valid(prefs.getInt(_reviewsKey)) ??
              StudyLimits.defaultReviewsPerDay,
        ),
      );

  static const _newKey = 'study_new_per_day';
  static const _reviewsKey = 'study_reviews_per_day';

  final SharedPreferences _prefs;

  /// Un valor guardado fuera de rango —de una versión futura, o tocado a
  /// mano— vuelve al de fábrica en vez de romper la sesión.
  static int? _valid(int? stored) =>
      stored != null && stored >= 0 && stored <= StudyLimits.maxPerDay
      ? stored
      : null;

  /// Cuántas nuevas por día, de 0 a [StudyLimits.maxPerDay].
  Future<void> setNewPerDay(int value) async {
    _check(value);
    state = state.copyWith(newPerDay: value);
    await _prefs.setInt(_newKey, value);
  }

  /// Cuántos repasos por día, de 0 a [StudyLimits.maxPerDay].
  Future<void> setReviewsPerDay(int value) async {
    _check(value);
    state = state.copyWith(reviewsPerDay: value);
    await _prefs.setInt(_reviewsKey, value);
  }

  /// Vuelve a los de fábrica: 20 y 200.
  Future<void> reset() async {
    state = const StudyLimits();
    await _prefs.remove(_newKey);
    await _prefs.remove(_reviewsKey);
  }

  static void _check(int value) {
    if (value < 0 || value > StudyLimits.maxPerDay) {
      throw RangeError.range(value, 0, StudyLimits.maxPerDay, 'value');
    }
  }
}

/// Los límites por día de estudio, cambiables y guardados.
final studyLimitsProvider =
    StateNotifierProvider<StudyLimitsNotifier, StudyLimits>(
      (ref) => StudyLimitsNotifier(prefs: ref.watch(sharedPreferencesProvider)),
    );
