import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/organize/presentation/providers/last_spaces.dart';

/// Los temas de la última vez (F37, decisión B), en el teléfono.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin nada guardado todavía, no hay ninguno', () async {
    final notifier = LastSpacesNotifier(
      prefs: await SharedPreferences.getInstance(),
    );

    expect(notifier.state, isEmpty);
  });

  test('recuerda los temas de lo último que se guardó, también al volver a '
      'abrir la app', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = LastSpacesNotifier(prefs: prefs);

    await notifier.remember({'historia', 'arte'});

    expect(notifier.state, {'historia', 'arte'});
    expect(LastSpacesNotifier(prefs: prefs).state, {'historia', 'arte'});
  });

  test('algo guardado sin temas no borra los de la última vez', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = LastSpacesNotifier(prefs: prefs);
    await notifier.remember({'historia'});

    await notifier.remember(const {});

    expect(notifier.state, {'historia'});
    expect(LastSpacesNotifier(prefs: prefs).state, {'historia'});
  });

  test('lo nuevo reemplaza entero a lo anterior', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = LastSpacesNotifier(prefs: prefs);
    await notifier.remember({'historia', 'arte'});

    await notifier.remember({'cocina'});

    expect(LastSpacesNotifier(prefs: prefs).state, {'cocina'});
  });
}
