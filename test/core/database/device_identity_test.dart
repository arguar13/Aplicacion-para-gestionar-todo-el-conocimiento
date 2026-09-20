import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/device_identity.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';

import '../../support/fake_id_generator.dart';

/// Quién es esta instalación (F11): un identificador que se crea una vez, vive
/// en las preferencias del dispositivo y no viaja con la base.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la primera vez crea un identificador y lo guarda', () async {
    final prefs = await SharedPreferences.getInstance();

    final identity = await DeviceIdentity.loadOrCreate(
      prefs,
      ids: FakeIdGenerator(prefix: 'dev'),
    );

    expect(identity.id, 'dev-0');
    expect(prefs.getString(DeviceIdentity.preferencesKey), 'dev-0');
  });

  test('las siguientes veces devuelve el mismo, no uno nuevo', () async {
    final prefs = await SharedPreferences.getInstance();
    final ids = FakeIdGenerator(prefix: 'dev');

    final first = await DeviceIdentity.loadOrCreate(prefs, ids: ids);
    final second = await DeviceIdentity.loadOrCreate(prefs, ids: ids);

    expect(second.id, first.id);
    // Y no consumió un identificador de más.
    expect(ids.next(), 'dev-1');
  });

  test('un identificador vacío guardado se reemplaza', () async {
    SharedPreferences.setMockInitialValues({DeviceIdentity.preferencesKey: ''});
    final prefs = await SharedPreferences.getInstance();

    final identity = await DeviceIdentity.loadOrCreate(
      prefs,
      ids: FakeIdGenerator(prefix: 'dev'),
    );

    expect(identity.id, 'dev-0');
    expect(prefs.getString(DeviceIdentity.preferencesKey), 'dev-0');
  });

  test('sin generador propio usa un UUID real, distinto cada vez', () async {
    final first = await DeviceIdentity.loadOrCreate(
      await SharedPreferences.getInstance(),
    );
    SharedPreferences.setMockInitialValues({});
    final second = await DeviceIdentity.loadOrCreate(
      await SharedPreferences.getInstance(),
    );

    expect(first.id, isNot(second.id));
    expect(first.id, matches(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-')));
  });

  group('lo escrito antes de F11', () {
    test('el texto fijo del espejo y `legacy` son de origen desconocido', () {
      expect(isLegacyDevice(kMirrorDeviceIdPlaceholder), isTrue);
      expect(isLegacyDevice(kLegacyDeviceId), isTrue);
    });

    test('un dispositivo real no lo es', () {
      expect(isLegacyDevice('0198a3f2-1c2d-7e11-9a55-5b1c0d1e2f30'), isFalse);
      // Ni el de una base que nadie configuró: es de una prueba, no de antes.
      expect(isLegacyDevice(kUnspecifiedDeviceId), isFalse);
    });
  });
}
