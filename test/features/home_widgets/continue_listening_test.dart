import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';

/// Lo último que se escuchó (F47, paso 7): el único punto que alimenta
/// «Seguir escuchando», y que sobrevive a cerrar la app.
void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('sin nada escuchado, no hay nada', () async {
    final container = await containerWith({});
    expect(container.read(continueListeningProvider), isNull);
  });

  test('lo escuchado queda, y se recupera al volver a abrir la app', () async {
    final first = await containerWith({});
    await first
        .read(continueListeningProvider.notifier)
        .listened(title: 'El Imperio', location: '/processed/p1');
    const expected = ContinueListening(
      title: 'El Imperio',
      location: '/processed/p1',
    );
    expect(first.read(continueListeningProvider), expected);

    final prefs = await SharedPreferences.getInstance();
    final reopened = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reopened.dispose);
    expect(reopened.read(continueListeningProvider), expected);
  });

  test('lo mismo dos veces no avisa dos veces', () async {
    final container = await containerWith({});
    final seen = <ContinueListening?>[];
    container.listen(continueListeningProvider, (_, next) => seen.add(next));
    final notifier = container.read(continueListeningProvider.notifier);

    await notifier.listened(title: 'A', location: '/library/a');
    await notifier.listened(title: 'A', location: '/library/a');
    await notifier.listened(title: 'B', location: '/library/b');

    expect(seen.map((c) => c?.title), ['A', 'B']);
  });

  test('a medias —sin dirección— no cuenta como escuchado', () async {
    final container = await containerWith({
      'continue_listening.title': 'Sin lugar',
    });
    expect(container.read(continueListeningProvider), isNull);
  });
}
