import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';

/// Los límites por día, guardados en SharedPreferences (F31, decisión 69).
void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('sin nada guardado, son los de fábrica: 20 y 200', () async {
    final container = await containerWith({});

    expect(container.read(studyLimitsProvider), const StudyLimits());
  });

  test('cambiarlos se guarda y sobrevive a reabrir la app', () async {
    final container = await containerWith({});

    await container.read(studyLimitsProvider.notifier).setNewPerDay(5);
    await container.read(studyLimitsProvider.notifier).setReviewsPerDay(80);

    expect(
      container.read(studyLimitsProvider),
      const StudyLimits(newPerDay: 5, reviewsPerDay: 80),
    );
    // Otra "apertura" de la app, con lo que quedó guardado.
    final prefs = container.read(sharedPreferencesProvider);
    final reopened = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reopened.dispose);
    expect(
      reopened.read(studyLimitsProvider),
      const StudyLimits(newPerDay: 5, reviewsPerDay: 80),
    );
  });

  test('un valor guardado fuera de rango vuelve al de fábrica', () async {
    final container = await containerWith({
      'study_new_per_day': -3,
      'study_reviews_per_day': 1000000,
    });

    expect(container.read(studyLimitsProvider), const StudyLimits());
  });

  test('0 es un valor válido: sin tarjetas nuevas por hoy', () async {
    final container = await containerWith({});

    await container.read(studyLimitsProvider.notifier).setNewPerDay(0);

    expect(container.read(studyLimitsProvider).newPerDay, 0);
  });

  test('rechaza lo que no entra, sin cambiar nada', () async {
    final container = await containerWith({});
    final notifier = container.read(studyLimitsProvider.notifier);

    await expectLater(notifier.setNewPerDay(-1), throwsRangeError);
    await expectLater(
      notifier.setReviewsPerDay(StudyLimits.maxPerDay + 1),
      throwsRangeError,
    );

    expect(container.read(studyLimitsProvider), const StudyLimits());
  });

  test('reset vuelve a los de fábrica y borra lo guardado', () async {
    final container = await containerWith({});
    final notifier = container.read(studyLimitsProvider.notifier);
    await notifier.setNewPerDay(7);
    await notifier.setReviewsPerDay(9);

    await notifier.reset();

    expect(container.read(studyLimitsProvider), const StudyLimits());
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getInt('study_new_per_day'), isNull);
    expect(prefs.getInt('study_reviews_per_day'), isNull);
  });
}
