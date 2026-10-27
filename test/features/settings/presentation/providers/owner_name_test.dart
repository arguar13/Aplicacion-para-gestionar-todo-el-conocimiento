import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';

/// «Cómo te llamo» (F42): opcional, local y nunca deducido de una cuenta.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('sin nada guardado, no hay nombre', () {
    final owner = OwnerNameNotifier(prefs: prefs);
    addTearDown(owner.dispose);
    expect(owner.state, isNull);
  });

  test('lo guardado se lee al arrancar, limpio', () async {
    SharedPreferences.setMockInitialValues({
      OwnerNameNotifier.prefsKey: '  Armando  ',
    });
    prefs = await SharedPreferences.getInstance();
    final owner = OwnerNameNotifier(prefs: prefs);
    addTearDown(owner.dispose);
    expect(owner.state, 'Armando');
  });

  test('ponerlo lo guarda; vacío lo quita', () async {
    final owner = OwnerNameNotifier(prefs: prefs);
    addTearDown(owner.dispose);

    await owner.rename('  Ana   María ');
    expect(owner.state, 'Ana María');
    expect(prefs.getString(OwnerNameNotifier.prefsKey), 'Ana María');

    await owner.rename('   ');
    expect(owner.state, isNull);
    expect(prefs.containsKey(OwnerNameNotifier.prefsKey), isFalse);

    await owner.rename('Ana');
    await owner.rename(null);
    expect(owner.state, isNull);
    expect(prefs.containsKey(OwnerNameNotifier.prefsKey), isFalse);
  });

  group('normalize', () {
    test('recorta lo largo sin partir letras ni dejar espacios al final', () {
      final long = '${'a' * 39} bcd';
      expect(OwnerNameNotifier.normalize(long), 'a' * 39);
      expect(OwnerNameNotifier.normalize('😀' * 45), '😀' * 40);
      final exact = 'b' * OwnerNameNotifier.maxLength;
      expect(OwnerNameNotifier.normalize(exact), exact);
    });

    test('sin nada, null', () {
      expect(OwnerNameNotifier.normalize(null), isNull);
      expect(OwnerNameNotifier.normalize(''), isNull);
      expect(OwnerNameNotifier.normalize(' \n\t '), isNull);
    });
  });
}
