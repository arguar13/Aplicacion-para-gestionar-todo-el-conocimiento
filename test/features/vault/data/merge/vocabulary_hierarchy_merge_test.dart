import 'package:flutter_test/flutter_test.dart';

import '../../../../support/test_vault.dart';

/// La jerarquía del vocabulario en la fusión de bóvedas (F13).
///
/// El vocabulario se une por conjuntos: el valor que ya está acá conserva SU
/// padre, y uno sin padre adopta el que le da la copia si eso no cierra un
/// ciclo ni pasa de cinco niveles. Lo que no entra se cuenta en el resultado y
/// no deshace la fusión.
void main() {
  late TestVault tel;
  late TestVault pc;
  late String telTema;
  late String pcTema;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
    telTema = await tel.temaId();
    pcTema = await pc.temaId();
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  /// Pone [child] bajo [parent] en [vault], con su nivel.
  Future<void> setParent(
    TestVault vault,
    String child,
    String parent,
    int depth,
  ) => vault.db.customStatement(
    "UPDATE property_values SET parent_id = '$parent', depth = $depth "
    "WHERE id = '$child'",
  );

  Future<Map<String, (String?, int)>> tree(TestVault vault) async => {
    for (final r
        in await vault.db
            .customSelect('SELECT id, parent_id, depth FROM property_values')
            .get())
      r.read<String>('id'): (
        r.readNullable<String>('parent_id'),
        r.read<int>('depth'),
      ),
  };

  /// Un valor con el mismo id en las dos bóvedas —el mismo valor—.
  Future<void> both(String id, String label) async {
    await tel.addPropertyValue(id, telTema, label);
    await pc.addPropertyValue(id, pcTema, label);
  }

  test('un valor sin padre acá adopta el que le da la copia', () async {
    await both('roma', 'Roma');
    await both('republica', 'Roma republicana');
    await setParent(pc, 'republica', 'roma', 1);
    await pc.saveSource('a');

    final result = await tel.mergeFrom(pc);

    expect((await tree(tel))['republica'], ('roma', 1));
    expect(result.valueParentsAdopted, 1);
    expect(result.valueParentsIgnored, 0);
  });

  test('un valor NUEVO de la copia entra con su padre y su nivel', () async {
    await both('roma', 'Roma');
    await pc.addPropertyValue('gracos', pcTema, 'Los Gracos');
    await setParent(pc, 'gracos', 'roma', 1);
    await pc.saveSource('a');

    final result = await tel.mergeFrom(pc);

    expect((await tree(tel))['gracos'], ('roma', 1));
    expect(result.propertyValuesAdded, 1);
    expect(result.valueParentsAdopted, 1);
  });

  test('una rama entera de la copia llega con los niveles de acá', () async {
    await both('roma', 'Roma');
    await pc.addPropertyValue('republica', pcTema, 'República');
    await pc.addPropertyValue('gracos', pcTema, 'Gracos');
    await setParent(pc, 'republica', 'roma', 1);
    await setParent(pc, 'gracos', 'republica', 2);
    await pc.saveSource('a');

    await tel.mergeFrom(pc);

    final merged = await tree(tel);
    expect(merged['republica'], ('roma', 1));
    expect(merged['gracos'], ('republica', 2));
  });

  test('el valor que ya tiene padre acá conserva el suyo', () async {
    await both('roma', 'Roma');
    await both('grecia', 'Grecia');
    await both('republica', 'Roma republicana');
    await setParent(tel, 'republica', 'grecia', 1);
    await setParent(pc, 'republica', 'roma', 1);
    await pc.saveSource('a');

    final result = await tel.mergeFrom(pc);

    expect((await tree(tel))['republica'], ('grecia', 1));
    expect(result.valueParentsAdopted, 0);
    expect(result.valueParentsIgnored, 1);
  });

  test(
    'el mismo padre en las dos bóvedas no es un conflicto ni se cuenta',
    () async {
      await both('roma', 'Roma');
      await both('republica', 'Roma republicana');
      await setParent(tel, 'republica', 'roma', 1);
      await setParent(pc, 'republica', 'roma', 1);
      await pc.saveSource('a');

      final result = await tel.mergeFrom(pc);

      expect(result.valueParentsAdopted, 0);
      expect(result.valueParentsIgnored, 0);
    },
  );

  test(
    'A bajo B en una bóveda y B bajo A en la otra: no se forma un ciclo',
    () async {
      await both('a', 'Alfa');
      await both('b', 'Beta');
      await setParent(tel, 'a', 'b', 1);
      await setParent(pc, 'b', 'a', 1);
      await pc.saveSource('x');

      final result = await tel.mergeFrom(pc);

      final merged = await tree(tel);
      expect(merged['a'], ('b', 1));
      expect(merged['b'], (null, 0));
      expect(result.valueParentsIgnored, 1);
    },
  );

  test('una relación que pasaría de cinco niveles no entra, y la fusión '
      'sigue', () async {
    // Acá: a > b > c > d > e (los cinco niveles). En la copia, `x` bajo `e`.
    for (final id in ['a', 'b', 'c', 'd', 'e', 'x']) {
      await both(id, 'Valor $id');
    }
    for (final (child, parent, depth) in [
      ('b', 'a', 1),
      ('c', 'b', 2),
      ('d', 'c', 3),
      ('e', 'd', 4),
    ]) {
      await setParent(tel, child, parent, depth);
    }
    await setParent(pc, 'x', 'e', 1);
    await pc.saveSource('s');

    final result = await tel.mergeFrom(pc);

    expect((await tree(tel))['x'], (null, 0));
    expect(result.valueParentsIgnored, 1);
  });

  test('lo asignado a un valor no cambia por venir con jerarquía', () async {
    await both('roma', 'Roma');
    await both('republica', 'Roma republicana');
    await setParent(pc, 'republica', 'roma', 1);
    await pc.saveSource('a');
    await pc.assignValue('a', 'republica');

    await tel.mergeFrom(pc);

    final assigned = await tel.db
        .customSelect(
          'SELECT property_value_id AS v FROM item_property_values '
          "WHERE item_id = 'a'",
        )
        .get();
    expect(assigned.map((r) => r.read<String>('v')), ['republica']);
  });

  test('sin jerarquía en la copia, el resultado no cuenta nada', () async {
    await both('roma', 'Roma');
    await pc.saveSource('a');

    final result = await tel.mergeFrom(pc);

    expect(result.valueParentsAdopted, 0);
    expect(result.valueParentsIgnored, 0);
  });
}
