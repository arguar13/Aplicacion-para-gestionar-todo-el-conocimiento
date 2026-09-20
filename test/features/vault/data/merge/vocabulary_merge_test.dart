import 'package:flutter_test/flutter_test.dart';

import '../../../../support/test_vault.dart';

/// El vocabulario en la fusión (F11): propiedades, valores, alias y lo que cada
/// elemento tiene asignado.
///
/// «Mismo identificador = mismo objeto» no alcanza: cada bóveda siembra su
/// «Tema» con un identificador propio, y los nombres y las etiquetas son únicos
/// sin distinguir mayúsculas. Unir por id dejaría dos «Tema» o chocaría con la
/// restricción.
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

  Future<Map<String, String>> valuesOf(TestVault vault) async => {
    for (final r
        in await vault.db
            .customSelect('SELECT id, definition_id FROM property_values')
            .get())
      r.read<String>('id'): r.read<String>('definition_id'),
  };

  Future<Set<String>> assignedTo(TestVault vault, String itemId) async => {
    for (final r
        in await vault.db
            .customSelect(
              'SELECT property_value_id AS v FROM item_property_values '
              "WHERE item_id = '$itemId'",
            )
            .get())
      r.read<String>('v'),
  };

  Future<Set<String>> aliasesOf(TestVault vault) async => {
    for (final r
        in await vault.db
            .customSelect('SELECT alias FROM property_aliases')
            .get())
      r.read<String>('alias'),
  };

  test('la premisa: cada bóveda siembra su «Tema» con un id propio', () {
    expect(telTema, isNot(pcTema));
  });

  group('las categorías', () {
    test('«Tema» de las dos es la misma: no queda duplicada', () async {
      final before = await tel.count('property_definitions');
      await pc.saveSource('a');

      final result = await tel.mergeFrom(pc);

      expect(result.propertyDefinitionsAdded, 0);
      expect(await tel.count('property_definitions'), before);
    });

    test('una que acá no hay entra, con su id y sus valores', () async {
      await pc.addDefinition('d-epoca', 'Época');
      await pc.addPropertyValue('v-antigua', 'd-epoca', 'Antigua');
      pc.at(3);
      await pc.saveSource('a');
      await pc.assignValue('a', 'v-antigua');

      final result = await tel.mergeFrom(pc);

      expect(result.propertyDefinitionsAdded, 1);
      expect(result.propertyValuesAdded, 1);
      expect(result.propertyAssignmentsAdded, 1);
      expect(await valuesOf(tel), {'v-antigua': 'd-epoca'});
      expect(await assignedTo(tel, 'a'), {'v-antigua'});
    });

    test('el nombre se compara sin distinguir mayúsculas', () async {
      await tel.addDefinition('d-tel', 'Lugar');
      await pc.addDefinition('d-pc', 'LUGAR');
      await pc.addPropertyValue('v-roma', 'd-pc', 'Roma');

      final result = await tel.mergeFrom(pc);

      expect(result.propertyDefinitionsAdded, 0);
      // Su valor cae en la categoría de acá.
      expect(await valuesOf(tel), {'v-roma': 'd-tel'});
    });

    test('con un id que acá usa OTRA categoría: entra con uno nuevo', () async {
      await tel.addDefinition('mismo-id', 'Lugar');
      await pc.addDefinition('mismo-id', 'Época');
      await pc.addPropertyValue('v-antigua', 'mismo-id', 'Antigua');
      pc.at(3);
      await pc.saveSource('a');
      await pc.assignValue('a', 'v-antigua');

      final result = await tel.mergeFrom(pc);

      expect(result.propertyDefinitionsAdded, 1);
      final epoca = await tel.db
          .customSelect(
            "SELECT id FROM property_definitions WHERE name = 'Época'",
          )
          .getSingle();
      expect(epoca.read<String>('id'), isNot('mismo-id'));
      // El valor y la asignación siguen a la categoría nueva.
      expect(await valuesOf(tel), {'v-antigua': epoca.read<String>('id')});
      expect(await assignedTo(tel, 'a'), {'v-antigua'});
      // Y la de acá no se tocó.
      final lugar = await tel.db
          .customSelect(
            "SELECT name FROM property_definitions WHERE id = 'mismo-id'",
          )
          .getSingle();
      expect(lugar.read<String>('name'), 'Lugar');
    });
  });

  group('los valores', () {
    test('uno con la misma etiqueta en la misma categoría es el mismo: la '
        'asignación va al de acá', () async {
      await tel.addPropertyValue('v-roma-tel', telTema, 'Roma');
      await pc.addPropertyValue('v-roma-pc', pcTema, 'roma'); // otra caja
      await pc.addPropertyValue('v-grecia', pcTema, 'Grecia'); // nuevo
      pc.at(3);
      await pc.saveSource('a');
      await pc.assignValue('a', 'v-roma-pc');
      await pc.assignValue('a', 'v-grecia');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.propertyValuesAdded, 1);
      expect(result.propertyAssignmentsAdded, 2);
      expect(await valuesOf(tel), {'v-roma-tel': telTema, 'v-grecia': telTema});
      // La asignación de «roma» cayó en «Roma»: no se creó un valor de más.
      expect(await assignedTo(tel, 'a'), {'v-roma-tel', 'v-grecia'});
    });

    test(
      'con el mismo id y otra etiqueta: la de la copia queda como alias',
      () async {
        // Se le cambió el nombre en una de las bóvedas.
        await tel.addPropertyValue('v1', telTema, 'Roma antigua');
        await pc.addPropertyValue('v1', pcTema, 'Roma');
        pc.at(3);
        await pc.saveSource('a');
        await pc.assignValue('a', 'v1');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        // Es el mismo valor: no se duplica; y se sigue encontrando por «Roma».
        expect(result.propertyValuesAdded, 0);
        expect(result.propertyAliasesAdded, 1);
        expect(await valuesOf(tel), {'v1': telTema});
        expect(await aliasesOf(tel), {'Roma'});
        expect(await assignedTo(tel, 'a'), {'v1'});
        final alias = await tel.db
            .customSelect(
              'SELECT property_value_id AS v, definition_id AS d '
              'FROM property_aliases',
            )
            .getSingle();
        expect(alias.read<String>('v'), 'v1');
        expect(alias.read<String>('d'), telTema);
      },
    );

    test('no crea un alias que ya es la etiqueta de otro valor', () async {
      await tel.addPropertyValue('v1', telTema, 'Roma antigua');
      await tel.addPropertyValue('v-roma', telTema, 'Roma');
      await pc.addPropertyValue('v1', pcTema, 'Roma');

      final result = await tel.mergeFrom(pc);

      expect(result.propertyAliasesAdded, 0);
      expect(await aliasesOf(tel), isEmpty);
    });

    test('las cifras y las fechas de un valor nuevo viajan', () async {
      await pc.addPropertyValue('v-num', pcTema, '3,5');
      await pc.db.customStatement(
        'UPDATE property_values SET number_value = 3.5, date_from_year = 1999, '
        "date_from_month = 4, date_to_year = 2001, date_precision = 'year', "
        "date_is_circa = 1 WHERE id = 'v-num'",
      );

      await tel.mergeFrom(pc);

      final row = await tel.db
          .customSelect("SELECT * FROM property_values WHERE id = 'v-num'")
          .getSingle();
      expect(row.read<double>('number_value'), 3.5);
      expect(row.read<int>('date_from_year'), 1999);
      expect(row.read<int>('date_from_month'), 4);
      expect(row.read<int>('date_to_year'), 2001);
      expect(row.read<String>('date_precision'), 'year');
      expect(row.read<int>('date_is_circa'), 1);
      expect(row.read<String>('definition_id'), telTema);
    });
  });

  group('los alias y las asignaciones', () {
    test(
      'los alias de la copia van con el valor de acá que les corresponde',
      () async {
        await tel.addPropertyValue('v-roma-tel', telTema, 'Roma');
        await pc.addPropertyValue('v-roma-pc', pcTema, 'Roma');
        await pc.addAlias('al', 'v-roma-pc', pcTema, 'Roma imperial');

        final result = await tel.mergeFrom(pc);

        expect(result.propertyAliasesAdded, 1);
        final alias = await tel.db
            .customSelect(
              'SELECT property_value_id AS v, alias FROM property_aliases',
            )
            .getSingle();
        expect(alias.read<String>('v'), 'v-roma-tel');
        expect(alias.read<String>('alias'), 'Roma imperial');
      },
    );

    test('un alias que choca con uno de acá no rompe la fusión', () async {
      await tel.addPropertyValue('v-a', telTema, 'Roma');
      await tel.addPropertyValue('v-b', telTema, 'Atenas');
      await tel.addAlias('al-tel', 'v-b', telTema, 'La ciudad');
      await pc.addPropertyValue('v-roma-pc', pcTema, 'Roma');
      await pc.addAlias('al-pc', 'v-roma-pc', pcTema, 'la ciudad');

      final result = await tel.mergeFrom(pc);

      expect(result.propertyAliasesAdded, 0);
      expect(await aliasesOf(tel), {'La ciudad'});
    });

    test('una asignación que acá ya está no se duplica', () async {
      tel.at(1);
      await tel.saveSource('a');
      await tel.addPropertyValue('v-roma', telTema, 'Roma');
      await tel.assignValue('a', 'v-roma');
      pc.at(2);
      await pc.mergeFrom(tel);
      // pc ya la tiene, por la fusión: es la misma asignación.
      expect(await pc.count('item_property_values'), 1);

      final result = await tel.mergeFrom(pc);

      expect(result.propertyAssignmentsAdded, 0);
      expect(await tel.count('item_property_values'), 1);
    });

    test(
      'un elemento que acá está en la papelera recibe las asignaciones',
      () async {
        tel.at(1);
        await tel.saveSource('a');
        pc.at(2);
        await pc.mergeFrom(tel);
        await pc.addPropertyValue('v-roma', pcTema, 'Roma');
        await pc.assignValue('a', 'v-roma');
        tel.at(3);
        await tel.library.delete('a');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        expect(result.propertyAssignmentsAdded, 1);
        expect(await assignedTo(tel, 'a'), {'v-roma'});
      },
    );

    test('el origen de la asignación viaja', () async {
      await pc.addPropertyValue('v-roma', pcTema, 'Roma');
      pc.at(3);
      await pc.saveSource('a');
      await pc.assignValue('a', 'v-roma');
      await pc.db.customStatement(
        "UPDATE item_property_values SET origin = 'suggested'",
      );

      await tel.mergeFrom(pc);

      final row = await tel.db
          .customSelect('SELECT origin FROM item_property_values')
          .getSingle();
      expect(row.read<String>('origin'), 'suggested');
    });
  });

  group('en general', () {
    test('fusionar dos veces no cambia nada', () async {
      await tel.addPropertyValue('v1', telTema, 'Roma antigua');
      await pc.addPropertyValue('v1', pcTema, 'Roma');
      await pc.addPropertyValue('v-grecia', pcTema, 'Grecia');
      await pc.addDefinition('d-epoca', 'Época');
      await pc.addAlias('al', 'v-grecia', pcTema, 'Hélade');
      pc.at(3);
      await pc.saveSource('a');
      await pc.assignValue('a', 'v1');
      await pc.assignValue('a', 'v-grecia');
      tel.at(9);
      await tel.mergeFrom(pc);
      final counts = await tel.counts();

      tel.at(12);
      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(await tel.counts(), counts);
    });

    test('la vista previa cuenta los valores que se agregan', () async {
      await tel.addPropertyValue('v-roma-tel', telTema, 'Roma');
      await pc.addPropertyValue('v-roma-pc', pcTema, 'roma');
      await pc.addPropertyValue('v-grecia', pcTema, 'Grecia');
      await pc.addDefinition('d-epoca', 'Época');
      await pc.addPropertyValue('v-antigua', 'd-epoca', 'Antigua');

      final preview = await tel.backup.previewMerge(await pc.zip());
      final result = await tel.mergeFrom(pc);

      expect(preview.newPropertyValues, result.propertyValuesAdded);
      expect(result.propertyValuesAdded, 2);
      expect(preview.hasNothingNew, isFalse);
    });

    test('la copia solo suma: lo de acá no se quita ni se cambia', () async {
      await tel.addDefinition('d-mia', 'Mía');
      await tel.addPropertyValue('v-mio', 'd-mia', 'Mío');
      tel.at(1);
      await tel.saveSource('a');
      await tel.assignValue('a', 'v-mio');
      final before = await tel.counts();

      await tel.mergeFrom(pc);

      expect(await tel.counts(), before);
      expect(await valuesOf(tel), {'v-mio': 'd-mia'});
      expect(await assignedTo(tel, 'a'), {'v-mio'});
    });
  });
}
