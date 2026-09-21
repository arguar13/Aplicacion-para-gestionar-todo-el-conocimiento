import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/reference_codec.dart';
import 'package:sinapsis/features/vault/data/repositories/merge_conflict_repository_impl.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';

import '../../../../support/test_vault.dart';

/// La fusión de bóvedas (F11) con los datos bibliográficos de una fuente y sus
/// personas (F15): llegan con los elementos nuevos, se deciden por linaje en
/// los comunes como un campo más —UN campo, `reference`—, y las personas se
/// unen con las de acá por su identidad y no por su identificador.
///
/// Dos bóvedas de verdad, «tel» y «pc», llenadas por el camino de la app.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');
  const rabassa = PersonName(family: 'Rabassa', given: 'Gregory');
  const borges = PersonName(family: 'Borges', given: 'Jorge Luis');
  const cortazar = PersonName(family: 'Cortázar', given: 'Julio');

  ReferenceData reference({
    String publisher = 'Sudamericana',
    List<PersonName> authors = const [garcia],
    List<PersonName> translators = const [],
  }) => ReferenceData(
    type: ReferenceType.book,
    publisher: publisher,
    contributors: [
      for (final name in authors) Contributor(name: name),
      for (final name in translators)
        Contributor(name: name, role: ContributorRole.translator),
    ],
  );

  Future<ReferenceData> read(TestVault vault, String id) =>
      ReferenceReader(vault.db).read(id);

  Future<List<String>> people(TestVault vault, String id) async => [
    for (final c in (await read(vault, id)).contributors)
      '${c.role.name}:${c.name.label}',
  ];

  /// Las asignaciones de la obra en `item_property_values`, con su origen.
  Future<List<String>> mirror(TestVault vault, String id) async {
    final rows = await (vault.db.select(
      vault.db.itemPropertyValues,
    )..where((a) => a.itemId.equals(id))).get();
    final labels = {
      for (final v in await vault.db.select(vault.db.propertyValues).get())
        v.id: v.value,
    };
    return [
      for (final a in rows) '${a.origin.name}:${labels[a.propertyValueId]}',
    ]..sort();
  }

  /// «a» nace en tel a las 12:01 y pc la recibe a las 12:02.
  Future<void> shareItem() async {
    tel.at(1);
    await tel.saveSource('a', title: 'Cien años de soledad');
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  group('los elementos nuevos traen su referencia', () {
    test('con sus datos y sus personas, en su orden', () async {
      tel.at(1);
      await tel.saveSource('a');
      tel.at(2);
      await tel.writer.setReference(
        'a',
        reference(translators: const [rabassa]),
      );
      pc.at(3);

      final result = await pc.mergeFrom(tel);

      expect(result.itemsAdded, 1);
      final arrived = await read(pc, 'a');
      expect(arrived.type, ReferenceType.book);
      expect(arrived.publisher, 'Sudamericana');
      expect(await people(pc, 'a'), [
        'author:García Márquez, Gabriel',
        'translator:Rabassa, Gregory',
      ]);
    });

    test('con el nombre partido de cada persona', () async {
      tel.at(1);
      await tel.saveSource('a');
      await tel.writer.setReference('a', reference());
      pc.at(3);

      await pc.mergeFrom(tel);

      final name = (await read(pc, 'a')).contributors.single.name;
      expect((name.family, name.given), ('García Márquez', 'Gabriel'));
    });

    test('con su versión por campo, la de tel', () async {
      tel.at(1);
      await tel.saveSource('a');
      tel.at(2);
      await tel.writer.setReference('a', reference());
      pc.at(3);

      await pc.mergeFrom(tel);

      final version = await pc.version('a', EntryField.reference);
      expect(version!.deviceId, 'tel');
      expect(version.updatedAt, tel.now);
    });

    test('las personas quedan en «Autor» y el espejo las asigna', () async {
      tel.at(1);
      await tel.saveSource('a');
      await tel.writer.setReference('a', reference());
      pc.at(3);

      await pc.mergeFrom(tel);

      final autor = await (pc.db.select(
        pc.db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      final value = await (pc.db.select(
        pc.db.propertyValues,
      )..where((v) => v.value.equals('García Márquez, Gabriel'))).getSingle();
      expect(value.definitionId, autor.id);
      expect(await mirror(pc, 'a'), ['reference:García Márquez, Gabriel']);
    });

    test('una fuente sin referencia llega sin ella', () async {
      tel.at(1);
      await tel.saveSource('a');
      pc.at(3);

      await pc.mergeFrom(tel);

      expect((await read(pc, 'a')).isEmpty, isTrue);
      expect(await pc.count('source_reference'), 0);
    });

    test('la misma persona que ya hay acá no se duplica: se une por su '
        'etiqueta', () async {
      pc.at(1);
      await pc.saveSource('propia');
      await pc.writer.setReference('propia', reference());
      tel.at(2);
      await tel.saveSource('a');
      await tel.writer.setReference('a', reference(publisher: 'Otra'));

      await pc.mergeFrom(tel);

      final values = await (pc.db.select(
        pc.db.propertyValues,
      )..where((v) => v.value.equals('García Márquez, Gabriel'))).get();
      expect(values, hasLength(1));
      final own = (await read(pc, 'propia')).contributors.single.personId;
      final arrived = (await read(pc, 'a')).contributors.single.personId;
      expect(arrived, own);
    });
  });

  group('el nombre partido de la persona', () {
    test('uno que acá nadie había partido toma el de la copia', () async {
      final autor = await (pc.db.select(
        pc.db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await pc.db
          .into(pc.db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'suelto',
              definitionId: autor.id,
              value: 'Borges, Jorge Luis',
              createdAt: pc.now,
            ),
          );
      tel.at(1);
      await tel.saveSource('a');
      await tel.writer.setReference('a', reference(authors: const [borges]));

      await pc.mergeFrom(tel);

      final value = await (pc.db.select(
        pc.db.propertyValues,
      )..where((v) => v.id.equals('suelto'))).getSingle();
      expect((value.nameFamily, value.nameGiven), ('Borges', 'Jorge Luis'));
      expect(await pc.count('property_values'), 1);
    });

    test('uno que ya estaba partido acá no se pisa', () async {
      final autor = await (pc.db.select(
        pc.db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await pc.db
          .into(pc.db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'partido',
              definitionId: autor.id,
              value: 'A, B, C',
              createdAt: pc.now,
              nameFamily: const Value('A, B'),
              nameGiven: const Value('C'),
            ),
          );
      tel.at(1);
      await tel.saveSource('a');
      await tel.writer.setReference(
        'a',
        reference(
          authors: const [PersonName(family: 'A', given: 'B, C')],
        ),
      );

      await pc.mergeFrom(tel);

      final value = await (pc.db.select(
        pc.db.propertyValues,
      )..where((v) => v.id.equals('partido'))).getSingle();
      expect((value.nameFamily, value.nameGiven), ('A, B', 'C'));
    });
  });

  group('un elemento que las dos bóvedas tienen', () {
    test(
      'la que solo tiene una de las dos versiones gana, sin conflicto',
      () async {
        await shareItem();
        tel.at(5);
        await tel.writer.setReference('a', reference());
        pc.at(6);

        final result = await pc.mergeFrom(tel);

        expect(result.fieldsUpdated, 1);
        expect(result.conflictsRecorded, 0);
        expect((await read(pc, 'a')).publisher, 'Sudamericana');
        expect(await people(pc, 'a'), ['author:García Márquez, Gabriel']);
        expect(await pc.conflicts(), isEmpty);
      },
    );

    test('una edición que parte de la otra la reemplaza, aunque su reloj '
        'marque una hora anterior', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference());
      pc.at(6);
      await pc.mergeFrom(tel);
      // pc edita ENCIMA de la versión de tel, con un reloj atrasado.
      pc.at(3);
      await pc.writer.setReference('a', reference(publisher: 'Alfaguara'));
      tel.at(8);

      final result = await tel.mergeFrom(pc);

      expect(result.conflictsRecorded, 0);
      expect((await read(tel, 'a')).publisher, 'Alfaguara');
    });

    test('dos ediciones concurrentes: queda la más nueva y la otra se guarda '
        'como conflicto', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference(publisher: 'Desde tel'));
      pc.at(7);
      await pc.writer.setReference('a', reference(publisher: 'Desde pc'));
      tel.at(9);

      final result = await tel.mergeFrom(pc);

      expect(result.conflictsRecorded, 1);
      // La más nueva es la de pc.
      expect((await read(tel, 'a')).publisher, 'Desde pc');
      final conflict = (await tel.conflicts()).single;
      expect(conflict.fieldName, EntryField.reference);
      expect(decodeReference(conflict.localValue!)!.publisher, 'Desde tel');
      expect(decodeReference(conflict.incomingValue!)!.publisher, 'Desde pc');
    });

    test('la versión guardada lleva a las personas por su nombre', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference(
        'a',
        reference(translators: const [rabassa]),
      );
      pc.at(7);
      await pc.writer.setReference('a', reference(authors: const [borges]));
      tel.at(9);

      await tel.mergeFrom(pc);

      final conflict = (await tel.conflicts()).single;
      final saved = decodeReference(conflict.localValue!)!.contributors;
      expect(saved.map((c) => c.name.label), [
        'García Márquez, Gabriel',
        'Rabassa, Gregory',
      ]);
      expect(saved.map((c) => c.role), [
        ContributorRole.author,
        ContributorRole.translator,
      ]);
    });

    test('elegir la otra versión la pone de nuevo, con sus personas', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference(publisher: 'Desde tel'));
      pc.at(7);
      await pc.writer.setReference(
        'a',
        reference(publisher: 'Desde pc', authors: const [borges]),
      );
      tel.at(9);
      await tel.mergeFrom(pc);
      final conflict = (await tel.conflicts()).single;
      tel.at(12);
      final repository = MergeConflictRepositoryImpl(
        database: tel.db,
        clock: () => tel.now,
      );

      // En vivo quedó la de pc; se elige la de tel, que estaba guardada.
      final result = await repository.resolve(
        conflict.id,
        MergeConflictChoice.keepLocal,
      );

      expect(result.isRight(), isTrue);
      expect((await read(tel, 'a')).publisher, 'Desde tel');
      expect(await people(tel, 'a'), ['author:García Márquez, Gabriel']);
      expect(await mirror(tel, 'a'), ['reference:García Márquez, Gabriel']);
      // Es una edición como cualquier otra: una versión nueva de tel.
      final version = await tel.version('a', EntryField.reference);
      expect(version!.deviceId, 'tel');
      expect(version.updatedAt, tel.now);
    });

    test('las mismas referencias no cambian nada, ni cuentan', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference());
      pc.at(6);
      await pc.mergeFrom(tel);
      final before = await pc.counts();
      tel.at(9);

      final preview = await pc.previewFrom(tel);
      final result = await pc.mergeFrom(tel);

      expect(preview.fieldsToUpdate, 0);
      expect(result.fieldsUpdated, 0);
      expect(result.conflictsRecorded, 0);
      expect(await pc.counts(), before);
    });

    test('renombrar a una persona en una bóveda no cambia sus obras', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference());
      pc.at(6);
      await pc.mergeFrom(tel);
      // pc renombra a la persona: es el mismo valor, con otra etiqueta.
      await pc.db.customStatement(
        "UPDATE property_values SET value = 'García Márquez, Gabo', "
        "name_given = 'Gabo' WHERE value = 'García Márquez, Gabriel'",
      );
      tel.at(9);

      final preview = await pc.previewFrom(tel);
      final result = await pc.mergeFrom(tel);

      expect(preview.fieldsToUpdate, 0);
      expect(result.fieldsUpdated, 0);
      expect(result.conflictsRecorded, 0);
      expect(await people(pc, 'a'), ['author:García Márquez, Gabo']);
    });

    test('la vista previa cuenta lo mismo que hace la fusión', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference(publisher: 'Desde tel'));
      pc.at(7);
      await pc.writer.setReference('a', reference(publisher: 'Desde pc'));
      tel.at(9);

      final preview = await tel.previewFrom(pc);
      final result = await tel.mergeFrom(pc);

      expect(preview.fieldsToUpdate, result.fieldsUpdated);
      expect(preview.conflicts, result.conflictsRecorded);
      expect(preview.conflicts, 1);
    });

    test('la fuente que solo tiene la referencia de acá la conserva', () async {
      await shareItem();
      pc.at(5);
      await pc.writer.setReference('a', reference());
      tel.at(6);

      final result = await pc.mergeFrom(tel);

      expect(result.fieldsUpdated, 0);
      expect(result.conflictsRecorded, 0);
      expect((await read(pc, 'a')).publisher, 'Sudamericana');
    });

    test(
      'una referencia que la copia vació deja acá la de la copia: vacía',
      () async {
        await shareItem();
        tel.at(5);
        await tel.writer.setReference('a', reference());
        pc.at(6);
        await pc.mergeFrom(tel);
        tel.at(8);
        await tel.writer.setReference('a', const ReferenceData());
        pc.at(9);

        await pc.mergeFrom(tel);

        expect((await read(pc, 'a')).isEmpty, isTrue);
        expect(await pc.count('source_reference'), 0);
        expect(await pc.count('source_contributor'), 0);
      },
    );

    test('un borrado contra una edición de la referencia no esconde el '
        'trabajo: la fuente queda viva y el borrado, en conflicto', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.trash(['a']);
      pc.at(7);
      await pc.writer.setReference('a', reference());
      tel.at(9);

      final result = await tel.mergeFrom(pc);

      expect((await tel.entry('a')).deletedAt, isNull);
      expect((await read(tel, 'a')).publisher, 'Sudamericana');
      final fields = {for (final c in await tel.conflicts()) c.fieldName};
      expect(fields, {EntryField.deletedAt});
      expect(result.conflictsRecorded, 1);
    });
  });

  group('el espejo de las personas', () {
    test('se rehace con las personas que ganaron, aunque sean menos', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference(
        'a',
        reference(authors: const [garcia, borges]),
      );
      pc.at(6);
      await pc.mergeFrom(tel);
      expect(await mirror(pc, 'a'), [
        'reference:Borges, Jorge Luis',
        'reference:García Márquez, Gabriel',
      ]);
      tel.at(8);
      await tel.writer.setReference('a', reference(authors: const [cortazar]));
      pc.at(9);

      // Pasa las compuertas: el espejo es derivado y no cuenta como algo que
      // una fusión no puede achicar.
      final result = await pc.mergeFrom(tel);

      expect(result.fieldsUpdated, 1);
      expect(await people(pc, 'a'), ['author:Cortázar, Julio']);
      expect(await mirror(pc, 'a'), ['reference:Cortázar, Julio']);
    });

    test('una asignación manual de una persona que sale de la obra se '
        'respeta', () async {
      await shareItem();
      tel.at(5);
      await tel.writer.setReference('a', reference());
      pc.at(6);
      await pc.mergeFrom(tel);
      // pc la asigna a mano también.
      final gabo = await (pc.db.select(
        pc.db.propertyValues,
      )..where((v) => v.value.equals('García Márquez, Gabriel'))).getSingle();
      await (pc.db.update(pc.db.itemPropertyValues)..where(
            (a) => a.itemId.equals('a') & a.propertyValueId.equals(gabo.id),
          ))
          .write(
            const ItemPropertyValuesCompanion(
              origin: Value(ItemPropertyOrigin.manual),
            ),
          );
      tel.at(8);
      await tel.writer.setReference('a', reference(authors: const [borges]));
      pc.at(9);

      await pc.mergeFrom(tel);

      expect(await mirror(pc, 'a'), [
        'manual:García Márquez, Gabriel',
        'reference:Borges, Jorge Luis',
      ]);
    });

    test('el espejo de la copia no se copia: solo el de las personas que '
        'ganaron', () async {
      await shareItem();
      // pc gana: su referencia es la más nueva.
      tel.at(5);
      await tel.writer.setReference('a', reference());
      pc.at(8);
      await pc.writer.setReference('a', reference(authors: const [borges]));
      pc.at(9);

      await pc.mergeFrom(tel);

      // La de tel perdió: su espejo (García Márquez) no entra.
      expect(await people(pc, 'a'), ['author:Borges, Jorge Luis']);
      expect(await mirror(pc, 'a'), ['reference:Borges, Jorge Luis']);
    });
  });

  group('lo que no cambia', () {
    test('no quedan la copia adjuntada ni las tablas de trabajo', () async {
      tel.at(1);
      await tel.saveSource('a');
      await tel.writer.setReference('a', reference());
      pc.at(3);

      await pc.mergeFrom(tel);

      final attached = await pc.db.customSelect('PRAGMA database_list').get();
      expect(
        attached.map((r) => r.read<String>('name')),
        isNot(contains('incoming')),
      );
      expect(
        await pc.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });

    test('fusionar dos veces la misma copia da lo mismo', () async {
      tel.at(1);
      await tel.saveSource('a');
      await tel.writer.setReference(
        'a',
        reference(translators: const [rabassa]),
      );
      pc.at(3);
      await pc.mergeFrom(tel);
      final once = await pc.counts();

      await pc.mergeFrom(tel);

      expect(await pc.counts(), once);
      expect(await people(pc, 'a'), hasLength(2));
    });
  });
}
