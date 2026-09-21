import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Either;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Las personas en el vocabulario de autores (F15): alta y edición con apellido
/// y nombre, fusión de dos personas con sus obras, y las obras de cada una.
///
/// Contra SQLite real, en memoria.
void main() {
  late AppDatabase db;
  late VocabularyRepositoryImpl repository;
  var clockNow = DateTime(2026, 9, 21, 10);

  setUp(() {
    clockNow = DateTime(2026, 9, 21, 10);
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'tel');
    repository = VocabularyRepositoryImpl(
      database: db,
      telemetry: _MockTelemetry(),
      ids: FakeIdGenerator(prefix: 'gen'),
      clock: () => clockNow,
    );
  });

  tearDown(() => db.close());

  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');

  Future<String> authorCategory() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Autor'))).getSingle()).id;

  Future<String> temaCategory() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Tema'))).getSingle()).id;

  /// Una persona ya guardada, con su nombre partido (o sin partir).
  Future<void> person(
    String id,
    String label, {
    String? family,
    String? given,
  }) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: await authorCategory(),
            value: label,
            createdAt: clockNow,
            nameFamily: Value(family),
            nameGiven: Value(given),
          ),
        );
  }

  Future<void> work(String id, {String? title}) => insertItemRows(
    db,
    id: id,
    title: title ?? 'Obra $id',
    createdAt: clockNow,
  );

  /// La obra [workId] nombra a [personId], con su espejo en las asignaciones.
  Future<void> names(
    String workId,
    String personId, {
    ContributorRole role = ContributorRole.author,
    int position = 0,
    bool mirror = true,
  }) async {
    await db
        .into(db.sourceReferences)
        .insert(
          SourceReferencesCompanion.insert(itemId: workId),
          mode: InsertMode.insertOrIgnore,
        );
    await db
        .into(db.sourceContributors)
        .insert(
          SourceContributorsCompanion.insert(
            itemId: workId,
            propertyValueId: personId,
            role: role,
            position: position,
          ),
        );
    if (mirror) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: workId,
              propertyValueId: personId,
              origin: const Value(ItemPropertyOrigin.reference),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<List<String>> contributorsOf(String workId) async => [
    for (final c
        in await (db.select(db.sourceContributors)
              ..where((c) => c.itemId.equals(workId))
              ..orderBy([(c) => OrderingTerm.asc(c.position)]))
            .get())
      '${c.position}:${c.propertyValueId}:${c.role.name}',
  ];

  Future<PropertyValueRow?> valueRow(String id) => (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<int> referenceRev(String workId) async {
    final row = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(workId))).getSingle();
    return row.rev;
  }

  Future<FieldVersionRow?> referenceVersion(String workId) =>
      (db.select(db.fieldVersions)..where(
            (f) =>
                f.itemId.equals(workId) &
                f.fieldName.equals(EntryField.reference),
          ))
          .getSingleOrNull();

  Failure failureOf<T>(Either<Failure, T> result) =>
      result.getLeft().toNullable()!;

  group('agregar una persona', () {
    test('se crea en «Autor», con su apellido y su nombre', () async {
      final result = await repository.addPerson(garcia);

      final operation = result.getRight().toNullable()!;
      expect(operation.kind, VocabularyOperationKind.add);
      expect(operation.label, 'García Márquez, Gabriel');
      final value = await db.select(db.propertyValues).getSingle();
      expect(value.definitionId, await authorCategory());
      expect(value.value, 'García Márquez, Gabriel');
      expect(
        (value.nameFamily, value.nameGiven),
        ('García Márquez', 'Gabriel'),
      );
      expect(value.nameSuffix, isNull);
      expect(value.isInstitution, isFalse);
    });

    test('una institución no se parte', () async {
      await repository.addPerson(
        const PersonName.institution('Real Academia Española'),
      );

      final value = await db.select(db.propertyValues).getSingle();
      expect(value.value, 'Real Academia Española');
      expect(value.isInstitution, isTrue);
      expect(value.nameGiven, isNull);
    });

    test('con sufijo', () async {
      await repository.addPerson(
        const PersonName(family: 'King', given: 'Martin Luther', suffix: 'Jr.'),
      );

      final value = await db.select(db.propertyValues).getSingle();
      expect(value.value, 'King, Martin Luther Jr.');
      expect(value.nameSuffix, 'Jr.');
    });

    test('sin apellido no se crea', () async {
      final result = await repository.addPerson(
        const PersonName(family: '  ', given: 'Gabriel'),
      );

      expect(result.isLeft(), isTrue);
      expect(failureOf(result), isA<ValidationFailure>());
      expect(await db.select(db.propertyValues).get(), isEmpty);
    });

    test('uno que ya existe —con otras mayúsculas, sin acentos o por un '
        'alias— no se duplica', () async {
      await repository.addPerson(garcia);
      final existing = await db.select(db.propertyValues).getSingle();
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-1',
              propertyValueId: existing.id,
              definitionId: existing.definitionId,
              alias: 'Gabo',
              createdAt: clockNow,
            ),
          );

      for (final name in const [
        PersonName(family: 'GARCÍA MÁRQUEZ', given: 'GABRIEL'),
        PersonName(family: 'Garcia Marquez', given: 'Gabriel'),
        PersonName(family: 'Gabo'),
      ]) {
        final result = await repository.addPerson(name);

        expect(result.isLeft(), isTrue, reason: name.label);
        expect(failureOf(result), isA<ValidationFailure>());
      }
      expect(await db.select(db.propertyValues).get(), hasLength(1));
    });

    test('se puede deshacer, mientras ninguna obra la nombre', () async {
      final operation = (await repository.addPerson(
        garcia,
      )).getRight().toNullable()!;

      final undone = await repository.undo(operation);

      expect(undone.isRight(), isTrue);
      expect(await db.select(db.propertyValues).get(), isEmpty);
    });

    test('no se deshace si una obra ya la nombra', () async {
      final operation = (await repository.addPerson(
        garcia,
      )).getRight().toNullable()!;
      final value = await db.select(db.propertyValues).getSingle();
      await work('libro');
      await names('libro', value.id, mirror: false);

      final undone = await repository.undo(operation);

      expect(undone.isLeft(), isTrue);
      expect(await db.select(db.propertyValues).get(), hasLength(1));
      expect(await db.select(db.sourceContributors).get(), hasLength(1));
    });
  });

  group('editar una persona', () {
    test('cambia la etiqueta y el nombre partido, conservando la persona '
        'y sus obras', () async {
      await person(
        'gabo',
        'García Márquez, G.',
        family: 'García Márquez',
        given: 'G.',
      );
      await work('libro');
      await names('libro', 'gabo');

      final result = await repository.editPerson(id: 'gabo', name: garcia);

      final operation = result.getRight().toNullable()!;
      expect(operation.kind, VocabularyOperationKind.rename);
      expect(operation.label, 'García Márquez, Gabriel');
      expect(operation.affectedItems, 1);
      final value = (await valueRow('gabo'))!;
      expect(value.value, 'García Márquez, Gabriel');
      expect(value.nameGiven, 'Gabriel');
      expect(await contributorsOf('libro'), ['0:gabo:author']);
    });

    test('una persona sin partir se parte', () async {
      await person('gabo', 'Gabriel García Márquez');

      await repository.editPerson(id: 'gabo', name: garcia);

      final value = (await valueRow('gabo'))!;
      expect(value.value, 'García Márquez, Gabriel');
      expect(value.nameFamily, 'García Márquez');
    });

    test(
      'corregir un acento de su propio nombre no choca consigo misma',
      () async {
        await person(
          'gabo',
          'Garcia Marquez, Gabriel',
          family: 'Garcia Marquez',
          given: 'Gabriel',
        );

        final result = await repository.editPerson(id: 'gabo', name: garcia);

        expect(result.isRight(), isTrue);
        expect((await valueRow('gabo'))!.value, 'García Márquez, Gabriel');
      },
    );

    test('con el nombre de OTRA persona o de un alias, no', () async {
      await person('gabo', 'Gabo, X', family: 'Gabo', given: 'X');
      await person(
        'otra',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-1',
              propertyValueId: 'otra',
              definitionId: await authorCategory(),
              alias: 'Marquez, G.',
              createdAt: clockNow,
            ),
          );

      final byLabel = await repository.editPerson(id: 'gabo', name: garcia);
      final byAlias = await repository.editPerson(
        id: 'gabo',
        name: const PersonName(family: 'Marquez', given: 'G.'),
      );

      expect(byLabel.isLeft(), isTrue);
      expect(byAlias.isLeft(), isTrue);
      expect((await valueRow('gabo'))!.value, 'Gabo, X');
    });

    test('un valor que no es una persona no se edita como tal', () async {
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'roma',
              definitionId: await temaCategory(),
              value: 'Roma',
              createdAt: clockNow,
            ),
          );

      final result = await repository.editPerson(id: 'roma', name: garcia);

      expect(failureOf(result), isA<ValidationFailure>());
      expect((await valueRow('roma'))!.value, 'Roma');
    });

    test('uno que ya no existe falla', () async {
      final result = await repository.editPerson(id: 'fantasma', name: garcia);

      expect(result.isLeft(), isTrue);
    });

    test('sin apellido falla', () async {
      await person('gabo', 'Gabo, X', family: 'Gabo', given: 'X');

      final result = await repository.editPerson(
        id: 'gabo',
        name: const PersonName(family: ''),
      );

      expect(failureOf(result), isA<ValidationFailure>());
    });

    test(
      'se deshace, con el nombre partido de antes —también sin partir—',
      () async {
        await person('gabo', 'Gabriel García Márquez');
        final operation = (await repository.editPerson(
          id: 'gabo',
          name: garcia,
        )).getRight().toNullable()!;

        final undone = await repository.undo(operation);

        expect(undone.isRight(), isTrue);
        final value = (await valueRow('gabo'))!;
        expect(value.value, 'Gabriel García Márquez');
        expect(value.nameFamily, isNull);
        expect(value.nameGiven, isNull);
      },
    );

    test('no se deshace si la persona cambió de nombre otra vez', () async {
      await person('gabo', 'Gabo, X', family: 'Gabo', given: 'X');
      final operation = (await repository.editPerson(
        id: 'gabo',
        name: garcia,
      )).getRight().toNullable()!;
      await repository.editPerson(
        id: 'gabo',
        name: const PersonName(family: 'Otro', given: 'Nombre'),
      );

      final undone = await repository.undo(operation);

      expect(undone.isLeft(), isTrue);
      expect((await valueRow('gabo'))!.value, 'Otro, Nombre');
    });
  });

  group('renombrar con una etiqueta', () {
    test('una persona no se renombra así: cambiaría la etiqueta y no el nombre '
        'partido', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );

      final result = await repository.renameValue(id: 'gabo', label: 'Otro');

      expect(failureOf(result), isA<ValidationFailure>());
      expect((await valueRow('gabo'))!.value, 'García Márquez, Gabriel');
    });

    test('un valor de texto sí', () async {
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'roma',
              definitionId: await temaCategory(),
              value: 'Roma',
              createdAt: clockNow,
            ),
          );

      final result = await repository.renameValue(
        id: 'roma',
        label: 'Roma antigua',
      );

      expect(result.isRight(), isTrue);
    });
  });

  group('fusionar dos personas', () {
    setUp(() async {
      await person(
        'gabo',
        'García Márquez, G.',
        family: 'García Márquez',
        given: 'G.',
      );
      await person(
        'gabriel',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('a', title: 'Cien años de soledad');
      await work('b', title: 'El otoño del patriarca');
      await work('c', title: 'Sin tocar');
    });

    test('las obras de la descartada pasan a la que se conserva, con su rol y '
        'su lugar', () async {
      await names('a', 'gabo');
      await names('b', 'gabo', role: ContributorRole.translator, position: 1);

      final result = await repository.mergeValues(
        keepId: 'gabriel',
        discardIds: ['gabo'],
      );

      expect(result.isRight(), isTrue);
      expect(await valueRow('gabo'), isNull);
      expect(await contributorsOf('a'), ['0:gabriel:author']);
      expect(await contributorsOf('b'), ['1:gabriel:translator']);
      // Nada se perdió en cascada.
      expect(await db.select(db.sourceContributors).get(), hasLength(2));
    });

    test('el espejo de las asignaciones pasa también', () async {
      await names('a', 'gabo');

      await repository.mergeValues(keepId: 'gabriel', discardIds: ['gabo']);

      final assigned = await db.select(db.itemPropertyValues).get();
      expect(assigned.map((a) => a.propertyValueId), ['gabriel']);
    });

    test(
      'la etiqueta de la descartada queda como alias de la que se conserva',
      () async {
        await names('a', 'gabo');

        await repository.mergeValues(keepId: 'gabriel', discardIds: ['gabo']);

        final aliases = await db.select(db.propertyAliases).get();
        expect(aliases.single.alias, 'García Márquez, G.');
        expect(aliases.single.propertyValueId, 'gabriel');
      },
    );

    test('una obra que ya nombraba a la que se conserva, con el mismo rol, '
        'queda con una sola', () async {
      await names('a', 'gabo');
      await names('a', 'gabriel', position: 1);

      await repository.mergeValues(keepId: 'gabriel', discardIds: ['gabo']);

      expect(await contributorsOf('a'), ['1:gabriel:author']);
    });

    test('con otro rol es otra entrada: no se junta', () async {
      await names('a', 'gabo');
      await names(
        'a',
        'gabriel',
        role: ContributorRole.translator,
        position: 1,
      );

      await repository.mergeValues(keepId: 'gabriel', discardIds: ['gabo']);

      expect(await contributorsOf('a'), [
        '0:gabriel:author',
        '1:gabriel:translator',
      ]);
    });

    test(
      'anota la referencia de cada obra tocada como editada, y solo esas',
      () async {
        await names('a', 'gabo');
        await names('b', 'gabriel');
        final revA = await referenceRev('a');
        final revC = await referenceRev('c');
        clockNow = clockNow.add(const Duration(minutes: 5));

        await repository.mergeValues(keepId: 'gabriel', discardIds: ['gabo']);

        expect(await referenceRev('a'), revA + 1);
        final version = await referenceVersion('a');
        expect(version!.deviceId, 'tel');
        expect(version.updatedAt, clockNow);
        // La de b ya nombraba a la que se conserva: no cambió.
        expect(await referenceVersion('b'), isNull);
        expect(await referenceRev('c'), revC);
        expect(await referenceVersion('c'), isNull);
      },
    );

    test(
      'se deshace: las obras vuelven a nombrar a la persona de antes',
      () async {
        await names('a', 'gabo');
        await names('b', 'gabo', role: ContributorRole.translator, position: 1);
        await names('b', 'gabriel');
        final operation = (await repository.mergeValues(
          keepId: 'gabriel',
          discardIds: ['gabo'],
        )).getRight().toNullable()!;
        clockNow = clockNow.add(const Duration(minutes: 5));

        final undone = await repository.undo(operation);

        expect(undone.isRight(), isTrue);
        expect(await contributorsOf('a'), ['0:gabo:author']);
        expect(await contributorsOf('b'), [
          '0:gabriel:author',
          '1:gabo:translator',
        ]);
        // Y la referencia de cada una, otra vez editada.
        expect((await referenceVersion('a'))!.updatedAt, clockNow);
      },
    );

    test('se deshace también la obra que sobraba por duplicada', () async {
      await names('a', 'gabo');
      await names('a', 'gabriel', position: 1);
      final operation = (await repository.mergeValues(
        keepId: 'gabriel',
        discardIds: ['gabo'],
      )).getRight().toNullable()!;

      await repository.undo(operation);

      expect(await contributorsOf('a'), ['0:gabo:author', '1:gabriel:author']);
    });

    test(
      'no se deshace si una obra ya no nombra a la que se conservó',
      () async {
        await names('a', 'gabo');
        final operation = (await repository.mergeValues(
          keepId: 'gabriel',
          discardIds: ['gabo'],
        )).getRight().toNullable()!;
        await db.delete(db.sourceContributors).go();

        final undone = await repository.undo(operation);

        expect(undone.isLeft(), isTrue);
        // Y no dejó nada a medias: la descartada sigue sin existir.
        expect(await valueRow('gabo'), isNull);
      },
    );

    test('no se deshace si el lugar de una obra que sobraba ya lo ocupa otra '
        'persona', () async {
      await names('a', 'gabo');
      await names('a', 'gabriel', position: 1);
      final operation = (await repository.mergeValues(
        keepId: 'gabriel',
        discardIds: ['gabo'],
      )).getRight().toNullable()!;
      await person(
        'borges',
        'Borges, Jorge Luis',
        family: 'Borges',
        given: 'Jorge Luis',
      );
      await names('a', 'borges', mirror: false);

      final undone = await repository.undo(operation);

      expect(undone.isLeft(), isTrue);
    });

    test('un valor de texto no toca ninguna referencia', () async {
      final tema = await temaCategory();
      for (final (id, label) in [('r1', 'Roma'), ('r2', 'Roma antigua')]) {
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: id,
                definitionId: tema,
                value: label,
                createdAt: clockNow,
              ),
            );
      }
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: 'a',
              propertyValueId: 'r2',
            ),
          );

      await repository.mergeValues(keepId: 'r1', discardIds: ['r2']);

      expect(await referenceVersion('a'), isNull);
    });
  });

  group('las obras de una persona', () {
    test('con su rol, por título', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('b', title: 'El otoño del patriarca');
      await work('a', title: 'cien años de soledad');
      await names('b', 'gabo', role: ContributorRole.translator, position: 1);
      await names('a', 'gabo');

      final works = await repository.watchWorksOf('gabo').first;

      expect(
        [for (final w in works) (w.title, w.role)],
        [
          ('cien años de soledad', ContributorRole.author),
          ('El otoño del patriarca', ContributorRole.translator),
        ],
      );
      expect(works.map((w) => w.itemId), ['a', 'b']);
    });

    test('sin las que están en la papelera', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('a');
      await work('b');
      await names('a', 'gabo');
      await names('b', 'gabo');
      await KnowledgeEntryWriter(db, clock: () => clockNow).trash(['b']);

      final works = await repository.watchWorksOf('gabo').first;

      expect(works.map((w) => w.itemId), ['a']);
    });

    test('la misma obra con dos roles sale dos veces', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('a');
      await names('a', 'gabo');
      await names('a', 'gabo', role: ContributorRole.translator, position: 1);

      final works = await repository.watchWorksOf('gabo').first;

      expect(works.map((w) => w.role), [
        ContributorRole.author,
        ContributorRole.translator,
      ]);
    });

    test('una persona sin obras no tiene ninguna', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );

      expect(await repository.watchWorksOf('gabo').first, isEmpty);
    });
  });

  group('borrar lo que no se usa', () {
    test('una persona que una obra nombra no está «sin uso», aunque el espejo '
        'se haya perdido', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await work('a');
      await names('a', 'gabo', mirror: false);

      final result = await repository.deleteUnusedValues(['gabo']);

      expect(result.isLeft(), isTrue);
      expect(await valueRow('gabo'), isNotNull);
      expect(await db.select(db.sourceContributors).get(), hasLength(1));
    });

    test('una sin obras sí se borra', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );

      final result = await repository.deleteUnusedValues(['gabo']);

      expect(result.isRight(), isTrue);
      expect(await valueRow('gabo'), isNull);
    });
  });

  group('las estadísticas', () {
    test('una persona trae su nombre partido; un valor de texto, no', () async {
      await person(
        'gabo',
        'García Márquez, Gabriel',
        family: 'García Márquez',
        given: 'Gabriel',
      );
      await person('suelto', 'Gabriel García Márquez');
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'roma',
              definitionId: await temaCategory(),
              value: 'Roma',
              createdAt: clockNow,
            ),
          );

      final stats = {
        for (final s in await repository.watchValueStats().first) s.id: s,
      };

      expect(stats['gabo']!.person, garcia);
      expect(stats['gabo']!.isPerson, isTrue);
      // Sin partir: entero como apellido, sin adivinar.
      expect(stats['suelto']!.person!.family, 'Gabriel García Márquez');
      expect(stats['suelto']!.person!.given, isEmpty);
      expect(stats['roma']!.person, isNull);
      expect(stats['roma']!.isPerson, isFalse);
    });
  });
}
