import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/duplicates/data/services/duplicate_candidate_selector_impl.dart';

import '../../support/fake_id_generator.dart';

/// Guardar los datos bibliográficos de una fuente por el escritor único (F15):
/// lo que escribe, lo que versiona, cómo resuelve a las personas contra el
/// vocabulario y cómo deja el espejo de sus autores.
///
/// Contra SQLite real, en memoria.
void main() {
  const me = 'telefono';
  const other = 'computadora';

  late AppDatabase db;
  late KnowledgeEntryWriter writer;
  late ReferenceReader reader;
  var clockNow = DateTime(2026, 9, 21, 9);

  setUp(() async {
    clockNow = DateTime(2026, 9, 21, 9);
    db = AppDatabase(NativeDatabase.memory(), deviceId: me);
    writer = KnowledgeEntryWriter(
      db,
      clock: () => clockNow,
      ids: FakeIdGenerator(prefix: 'persona'),
    );
    reader = ReferenceReader(db);
    await writer.upsert(_source('libro'));
  });

  tearDown(() => db.close());

  void tick() => clockNow = clockNow.add(const Duration(minutes: 5));

  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');
  const rabassa = PersonName(family: 'Rabassa', given: 'Gregory');

  Future<KnowledgeEntryRow> entry(String id) => (db.select(
    db.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle();

  Future<FieldVersionRow?> version(String id) =>
      (db.select(db.fieldVersions)..where(
            (f) =>
                f.itemId.equals(id) & f.fieldName.equals(EntryField.reference),
          ))
          .getSingleOrNull();

  Future<List<PropertyValueRow>> people() async =>
      (await db.select(db.propertyValues).get())
          .where((v) => v.nameFamily != null || v.value.contains(','))
          .toList();

  Future<List<ItemPropertyValueRow>> mirror(String id) => (db.select(
    db.itemPropertyValues,
  )..where((a) => a.itemId.equals(id))).get();

  group('guardar', () {
    test('los datos vuelven tal como se guardaron', () async {
      final saved = await writer.setReference(
        'libro',
        ReferenceData(
          type: ReferenceType.book,
          publisher: 'Sudamericana',
          publisherPlace: 'Buenos Aires',
          edition: '1.ª ed.',
          pages: '45-67',
          isbn: '0-306-40615-2',
          accessedAt: DateTime(2026, 9, 20),
          citationKey: 'garcia1967',
          publicationPrecision: PublicationPrecision.year,
          contributors: const [Contributor(name: garcia)],
        ),
      );

      final read = await reader.read('libro');

      expect(saved, isTrue);
      expect(read.type, ReferenceType.book);
      expect(read.publisher, 'Sudamericana');
      expect(read.publisherPlace, 'Buenos Aires');
      expect(read.edition, '1.ª ed.');
      expect(read.pages, '45-67');
      // Normalizado: es lo que hace que dos referencias al mismo libro se
      // encuentren.
      expect(read.isbn, '9780306406157');
      expect(read.accessedAt, DateTime(2026, 9, 20));
      expect(read.citationKey, 'garcia1967');
      expect(read.publicationPrecision, PublicationPrecision.year);
      expect(read.contributors.single.name, garcia);
      expect(read.contributors.single.role, ContributorRole.author);
    });

    test('lo que no es válido no se guarda, y lo demás sí', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          doi: 'https://doi.org/10.1000/XYZ',
          isbn: '978-0-306-40615-8',
          issn: '1234',
          volume: '  12 ',
        ),
      );

      final read = await reader.read('libro');

      expect(read.doi, '10.1000/xyz');
      expect(read.isbn, isNull);
      expect(read.issn, isNull);
      expect(read.volume, '12');
    });

    test('reemplaza lo que había: un dato que no viene se borra', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(publisher: 'Sudamericana', volume: '2'),
      );

      await writer.setReference('libro', const ReferenceData(volume: '2'));

      final read = await reader.read('libro');
      expect(read.publisher, isNull);
      expect(read.volume, '2');
    });

    test('una obra que no existe, o una nota, no se toca', () async {
      await writer.upsert(_note('nota'));

      expect(
        await writer.setReference('fantasma', const ReferenceData(pages: '1')),
        isFalse,
      );
      expect(
        await writer.setReference('nota', const ReferenceData(pages: '1')),
        isFalse,
      );
      expect(await db.select(db.sourceReferences).get(), isEmpty);
    });

    test('sin ningún dato borra la fila y las personas', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          pages: '1',
          contributors: [Contributor(name: garcia)],
        ),
      );

      await writer.setReference('libro', const ReferenceData());

      expect(await db.select(db.sourceReferences).get(), isEmpty);
      expect(await db.select(db.sourceContributors).get(), isEmpty);
      expect(await reader.read('libro').then((r) => r.isEmpty), isTrue);
    });

    test('el año y su exactitud se leen juntos', () async {
      await writer.upsert(_source('libro', publishedAt: DateTime(1967, 5, 30)));
      await writer.setReference(
        'libro',
        const ReferenceData(publicationPrecision: PublicationPrecision.year),
      );

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('libro'))).getSingle();
      final read = await reader.read('libro');
      final date = PublicationDate.fromStored(
        source.publishedAt,
        read.publicationPrecision,
      );

      expect(date.year, 1967);
      expect(date.month, isNull);
    });
  });

  group('el linaje', () {
    test('sube el rev una vez y registra UN campo, «reference»', () async {
      final before = (await entry('libro')).rev;
      tick();

      await writer.setReference(
        'libro',
        const ReferenceData(
          publisher: 'Sudamericana',
          pages: '1',
          contributors: [
            Contributor(name: garcia),
            Contributor(name: rabassa),
          ],
        ),
      );

      expect((await entry('libro')).rev, before + 1);
      final row = await version('libro');
      expect(row!.deviceId, me);
      expect(row.updatedAt, clockNow);
      expect(row.baseUpdatedAt, isNull);
      // Nada más se versionó por esto: ni los textos ni las personas por
      // separado.
      final fields = {
        for (final f in await db.select(db.fieldVersions).get()) f.fieldName,
      };
      expect(fields, contains(EntryField.reference));
      expect(fields, isNot(contains('publisher')));
      expect(fields, isNot(contains('contributors')));
    });

    test('guardar lo mismo no cambia ni el rev ni la versión', () async {
      const reference = ReferenceData(
        publisher: 'Sudamericana',
        contributors: [Contributor(name: garcia)],
      );
      await writer.setReference('libro', reference);
      final rev = (await entry('libro')).rev;
      final first = await version('libro');
      tick();

      final again = await writer.setReference('libro', reference);

      expect(again, isTrue);
      expect((await entry('libro')).rev, rev);
      expect((await version('libro'))!.updatedAt, first!.updatedAt);
    });

    test('lo mismo escrito distinto —espacios, prefijos— tampoco cambia '
        'nada', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(doi: '10.1000/xyz', volume: '2'),
      );
      final rev = (await entry('libro')).rev;
      tick();

      await writer.setReference(
        'libro',
        const ReferenceData(doi: 'DOI: 10.1000/XYZ', volume: ' 2 '),
      );

      expect((await entry('libro')).rev, rev);
    });

    test('un cambio renueva la versión y conserva el linaje propio', () async {
      await writer.setReference('libro', const ReferenceData(volume: '1'));
      final first = await version('libro');
      tick();

      await writer.setReference('libro', const ReferenceData(volume: '2'));

      final second = await version('libro');
      expect(second!.updatedAt, isNot(first!.updatedAt));
      expect(second.baseUpdatedAt, isNull);
      expect(second.baseDeviceId, isNull);
    });

    test(
      'editar encima de la versión de otro dispositivo parte de ella',
      () async {
        final theirs = DateTime(2026, 9, 20, 18);
        await db
            .into(db.fieldVersions)
            .insert(
              FieldVersionsCompanion.insert(
                itemId: 'libro',
                fieldName: EntryField.reference,
                updatedAt: theirs,
                deviceId: other,
              ),
            );

        await writer.setReference('libro', const ReferenceData(volume: '2'));

        final row = await version('libro');
        expect(row!.deviceId, me);
        expect(row.baseDeviceId, other);
        expect(row.baseUpdatedAt, theirs);
      },
    );

    test(
      'cambiar solo el orden de las personas cuenta como un cambio',
      () async {
        await writer.setReference(
          'libro',
          const ReferenceData(
            contributors: [
              Contributor(name: garcia),
              Contributor(name: rabassa),
            ],
          ),
        );
        final rev = (await entry('libro')).rev;
        tick();

        await writer.setReference(
          'libro',
          const ReferenceData(
            contributors: [
              Contributor(name: rabassa),
              Contributor(name: garcia),
            ],
          ),
        );

        expect((await entry('libro')).rev, rev + 1);
        final read = await reader.read('libro');
        expect(read.contributors.map((c) => c.name.family), [
          'Rabassa',
          'García Márquez',
        ]);
      },
    );
  });

  group('las personas', () {
    test(
      'se crean en el vocabulario, en «Autor», con el nombre partido',
      () async {
        await writer.setReference(
          'libro',
          const ReferenceData(contributors: [Contributor(name: garcia)]),
        );

        final category = await (db.select(
          db.propertyDefinitions,
        )..where((d) => d.name.equals('Autor'))).getSingle();
        final value = (await people()).single;

        expect(value.definitionId, category.id);
        expect(value.value, 'García Márquez, Gabriel');
        expect(value.nameFamily, 'García Márquez');
        expect(value.nameGiven, 'Gabriel');
        expect(value.nameSuffix, isNull);
        expect(value.isInstitution, isFalse);
      },
    );

    test('una institución y un nombre de una sola palabra', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName.institution('Organización Mundial de la Salud'),
            ),
            Contributor(name: PersonName(family: 'Tucídides')),
          ],
        ),
      );

      final read = await reader.read('libro');

      expect(read.contributors[0].name.isInstitution, isTrue);
      expect(
        read.contributors[0].name.family,
        'Organización Mundial de la Salud',
      );
      expect(read.contributors[1].name.family, 'Tucídides');
      expect(read.contributors[1].name.given, isEmpty);
    });

    test('con sufijo', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(
                family: 'King',
                given: 'Martin Luther',
                suffix: 'Jr.',
              ),
            ),
          ],
        ),
      );

      final name = (await reader.read('libro')).contributors.single.name;

      expect(name.suffix, 'Jr.');
      expect(name.label, 'King, Martin Luther Jr.');
    });

    test('dos obras de la misma persona comparten UN valor', () async {
      await writer.upsert(_source('otro'));

      await writer.setReference(
        'libro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );
      await writer.setReference(
        'otro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );

      expect(await people(), hasLength(1));
      final first = (await reader.read('libro')).contributors.single;
      final second = (await reader.read('otro')).contributors.single;
      expect(first.personId, second.personId);
    });

    test('sin distinguir mayúsculas, como el resto del vocabulario', () async {
      await writer.upsert(_source('otro'));
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'Borges', given: 'Jorge Luis'),
            ),
          ],
        ),
      );

      await writer.setReference(
        'otro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'BORGES', given: 'JORGE LUIS'),
            ),
          ],
        ),
      );

      expect(await people(), hasLength(1));
    });

    test('un alias del valor resuelve al mismo valor', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );
      final value = (await people()).single;
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-1',
              propertyValueId: value.id,
              definitionId: value.definitionId,
              alias: 'Marquez, Gabriel',
              createdAt: clockNow,
            ),
          );
      await writer.upsert(_source('otro'));

      await writer.setReference(
        'otro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'Marquez', given: 'Gabriel'),
            ),
          ],
        ),
      );

      expect(await people(), hasLength(1));
      expect(
        (await reader.read('otro')).contributors.single.personId,
        value.id,
      );
    });

    test(
      'la identidad guardada manda sobre el nombre con que llegue',
      () async {
        await writer.setReference(
          'libro',
          const ReferenceData(contributors: [Contributor(name: garcia)]),
        );
        final id = (await people()).single.id;
        await writer.upsert(_source('otro'));

        await writer.setReference(
          'otro',
          ReferenceData(
            contributors: [
              Contributor(
                name: const PersonName(family: 'Otro Nombre'),
                personId: id,
              ),
            ],
          ),
        );

        final saved = (await reader.read('otro')).contributors.single;
        expect(saved.personId, id);
        expect(saved.name, garcia);
        expect(await people(), hasLength(1));
      },
    );

    test('una identidad que ya no existe se resuelve por el nombre; sin '
        'nombre se descarta', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(name: garcia, personId: 'borrado'),
            Contributor(
              name: PersonName(family: ''),
              personId: 'borrado-2',
            ),
          ],
        ),
      );

      final read = await reader.read('libro');

      expect(read.contributors, hasLength(1));
      expect(read.contributors.single.name, garcia);
      expect(read.contributors.single.personId, isNot('borrado'));
    });

    test('un valor sin el nombre partido se parte al reconocerlo', () async {
      final category = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'viejo',
              definitionId: category.id,
              value: 'Borges, Jorge Luis',
              createdAt: clockNow,
            ),
          );

      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'Borges', given: 'Jorge Luis'),
            ),
          ],
        ),
      );

      final value = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals('viejo'))).getSingle();
      expect(value.nameFamily, 'Borges');
      expect(value.nameGiven, 'Jorge Luis');
      expect(await db.select(db.propertyValues).get(), hasLength(1));
    });

    test('un valor ya partido no se pisa', () async {
      final category = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'partido',
              definitionId: category.id,
              value: 'A, B, C',
              createdAt: clockNow,
              nameFamily: const Value('A, B'),
              nameGiven: const Value('C'),
            ),
          );

      // Misma etiqueta, otra forma de partirla.
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'A', given: 'B, C'),
            ),
          ],
        ),
      );

      final value = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals('partido'))).getSingle();
      expect((value.nameFamily, value.nameGiven), ('A, B', 'C'));
    });

    test('un valor sin partir se lee entero, como un apellido', () async {
      final category = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'suelto',
              definitionId: category.id,
              value: 'Gabriel García Márquez',
              createdAt: clockNow,
            ),
          );
      await db
          .into(db.sourceReferences)
          .insert(SourceReferencesCompanion.insert(itemId: 'libro'));
      await db
          .into(db.sourceContributors)
          .insert(
            SourceContributorsCompanion.insert(
              itemId: 'libro',
              propertyValueId: 'suelto',
              role: ContributorRole.author,
              position: 0,
            ),
          );

      final name = (await reader.read('libro')).contributors.single.name;

      // No se adivina dónde termina el apellido.
      expect(name.family, 'Gabriel García Márquez');
      expect(name.given, isEmpty);
      expect(name.label, 'Gabriel García Márquez');
    });

    test('y guardarla de vuelta no crea otra persona', () async {
      final category = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'suelto',
              definitionId: category.id,
              value: 'Gabriel García Márquez',
              createdAt: clockNow,
            ),
          );
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'Gabriel García Márquez'),
              personId: 'suelto',
            ),
          ],
        ),
      );
      final read = await reader.read('libro');

      await writer.setReference('libro', read);

      expect(await db.select(db.propertyValues).get(), hasLength(1));
      expect(
        (await reader.read('libro')).contributors.single.personId,
        'suelto',
      );
    });

    test('los roles y su orden se conservan', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(name: garcia),
            Contributor(name: rabassa, role: ContributorRole.translator),
            Contributor(
              name: PersonName(family: 'Ed', given: 'Itor'),
              role: ContributorRole.editor,
            ),
            Contributor(name: garcia, role: ContributorRole.director),
          ],
        ),
      );

      final read = await reader.read('libro');

      expect(read.contributors.map((c) => c.role), [
        ContributorRole.author,
        ContributorRole.translator,
        ContributorRole.editor,
        ContributorRole.director,
      ]);
      expect(read.byRole(ContributorRole.author).single.name, garcia);
      // La misma persona, con otro rol, sigue siendo la misma persona.
      expect(await people(), hasLength(3));
    });
  });

  group('el espejo en item_property_values', () {
    test('cada persona de la obra queda asignada, con su origen', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(name: garcia),
            Contributor(name: rabassa),
          ],
        ),
      );

      final assigned = await mirror('libro');

      expect(assigned, hasLength(2));
      for (final a in assigned) {
        expect(a.origin, ItemPropertyOrigin.reference);
      }
      expect(
        {for (final a in assigned) a.propertyValueId},
        {for (final v in await people()) v.id},
      );
    });

    test('la misma persona con dos roles se asigna una vez', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(name: garcia),
            Contributor(name: garcia, role: ContributorRole.translator),
          ],
        ),
      );

      expect(await mirror('libro'), hasLength(1));
    });

    test('quitar una persona de la obra la quita del espejo, no del '
        'vocabulario', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(name: garcia),
            Contributor(name: rabassa),
          ],
        ),
      );

      await writer.setReference(
        'libro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );

      final assigned = await mirror('libro');
      expect(assigned, hasLength(1));
      expect(await people(), hasLength(2));
    });

    test('una asignación manual de la misma persona no se degrada ni se '
        'borra', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );
      final id = (await people()).single.id;
      // Alguien la puso a mano, desde el editor de propiedades.
      await (db.update(db.itemPropertyValues)..where(
            (a) => a.itemId.equals('libro') & a.propertyValueId.equals(id),
          ))
          .write(
            const ItemPropertyValuesCompanion(
              origin: Value(ItemPropertyOrigin.manual),
            ),
          );

      // Ni al guardar lo mismo, ni al quitarla de la obra.
      await writer.setReference(
        'libro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );
      await writer.setReference('libro', const ReferenceData(pages: '1'));

      final assigned = await mirror('libro');
      expect(assigned.single.origin, ItemPropertyOrigin.manual);
    });

    test('una asignación manual que ya estaba antes se respeta', () async {
      final category = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Autor'))).getSingle();
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'viejo',
              definitionId: category.id,
              value: 'Borges, Jorge Luis',
              createdAt: clockNow,
            ),
          );
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: 'libro',
              propertyValueId: 'viejo',
            ),
          );

      await writer.setReference(
        'libro',
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: 'Borges', given: 'Jorge Luis'),
            ),
          ],
        ),
      );
      await writer.setReference('libro', const ReferenceData());

      final assigned = await mirror('libro');
      expect(assigned.single.propertyValueId, 'viejo');
      expect(assigned.single.origin, ItemPropertyOrigin.manual);
    });

    test(
      'un espejo que alguien borró se repone sin tocar la versión',
      () async {
        const reference = ReferenceData(
          contributors: [Contributor(name: garcia)],
        );
        await writer.setReference('libro', reference);
        final rev = (await entry('libro')).rev;
        await db.delete(db.itemPropertyValues).go();
        tick();

        await writer.setReference('libro', reference);

        expect(await mirror('libro'), hasLength(1));
        expect((await entry('libro')).rev, rev);
      },
    );

    test('lo asignado a otros elementos no se toca', () async {
      await writer.upsert(_source('otro'));
      await writer.setReference(
        'otro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );

      await writer.setReference(
        'libro',
        const ReferenceData(contributors: [Contributor(name: garcia)]),
      );
      await writer.setReference('libro', const ReferenceData());

      expect(await mirror('otro'), hasLength(1));
      expect(await mirror('libro'), isEmpty);
    });
  });

  group('al borrar', () {
    test('la obra se lleva su referencia y sus personas, no las personas '
        'del vocabulario', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          pages: '1',
          contributors: [Contributor(name: garcia)],
        ),
      );
      await writer.trash(['libro']);
      expect(await db.select(db.sourceReferences).get(), hasLength(1));

      await writer.purge('libro');

      expect(await db.select(db.sourceReferences).get(), isEmpty);
      expect(await db.select(db.sourceContributors).get(), isEmpty);
      expect(await people(), hasLength(1));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('mandarla a la papelera y restaurarla conserva todo', () async {
      await writer.setReference(
        'libro',
        const ReferenceData(
          pages: '1',
          contributors: [Contributor(name: garcia)],
        ),
      );

      await writer.trash(['libro']);
      await writer.restore(['libro']);

      final read = await reader.read('libro');
      expect(read.pages, '1');
      expect(read.contributors.single.name, garcia);
    });
  });

  group('una referencia sin texto', () {
    KnowledgeItem reference({String title = 'Cien años de soledad'}) =>
        _source('ref', kind: SourceKind.reference, title: title);

    test('nace triada: no inunda la Bandeja', () async {
      await writer.upsert(reference());

      final row = await entry('ref');

      expect(row.kind, ItemKind.source);
      expect(row.state, ItemState.triaged);
    });

    test('una edición posterior no le cambia el estado', () async {
      await writer.upsert(reference());
      await writer.setState('ref', ItemState.distilled);

      await writer.upsert(reference(title: 'Otro título'));

      expect((await entry('ref')).state, ItemState.distilled);
    });

    test('las demás fuentes siguen naciendo como siempre', () async {
      expect((await entry('libro')).state, ItemState.processed);
    });

    test(
      'el invariante de chunking la cuenta aparte: ni pasa ni falla',
      () async {
        await writer.upsert(reference());

        final report = await verifyChunkInvariant(db);

        expect(report.holds, isTrue, reason: report.violations.join('; '));
        expect(report.sourcesWithoutText, 2);
      },
    );

    test('puede tener referencia y personas', () async {
      await writer.upsert(reference());

      await writer.setReference(
        'ref',
        const ReferenceData(
          type: ReferenceType.book,
          contributors: [Contributor(name: garcia)],
        ),
      );

      expect((await reader.read('ref')).type, ReferenceType.book);
    });

    test('F7 la ignora: no tiene huella de texto, ni es candidata ni '
        'candidata de nadie', () async {
      await writer.upsert(reference());
      // Dos fuentes con texto y la MISMA huella: F7 sí las junta.
      await writer.upsert(_source('gemelo'));
      for (final id in ['libro', 'gemelo']) {
        await (db.update(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals(id))).write(
          const KnowledgeSourcesCompanion(
            dedupHash: Value('abc'),
            simhash: Value('0000000000000001'),
          ),
        );
      }
      final selector = DuplicateCandidateSelectorImpl(database: db);

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('ref'))).getSingle();
      final ofLibro = await selector.selectCandidates(seedItemId: 'libro');

      expect(source.dedupHash, isNull);
      // El control: el selector funciona, y solo trae a la otra fuente.
      expect([for (final c in ofLibro) c.itemId], ['gemelo']);
      expect(await selector.selectCandidates(seedItemId: 'ref'), isEmpty);
    });
  });

  group('la lectura por lotes', () {
    test('trae varias obras a la vez, sin las que no tienen nada', () async {
      await writer.upsert(_source('b'));
      await writer.upsert(_source('vacio'));
      await writer.setReference(
        'libro',
        const ReferenceData(
          pages: '1',
          contributors: [Contributor(name: garcia)],
        ),
      );
      await writer.setReference(
        'b',
        const ReferenceData(publisher: 'Editorial'),
      );

      final byId = await reader.readMany(['libro', 'b', 'vacio', 'fantasma']);

      expect(byId.keys, unorderedEquals(['libro', 'b']));
      expect(byId['libro']!.contributors.single.name, garcia);
      expect(byId['b']!.publisher, 'Editorial');
    });

    test('pasa el tope de una consulta sin perder ninguna', () async {
      // Más ids de los que entran en una consulta (400).
      const total = 950;
      await db.batch((batch) {
        batch
          ..insertAll(db.knowledgeEntries, [
            for (var i = 0; i < total; i++)
              KnowledgeEntriesCompanion.insert(
                id: 'masivo-$i',
                title: 'Obra $i',
                kind: ItemKind.source,
                state: ItemState.triaged,
                createdAt: clockNow,
                updatedAt: clockNow,
                deviceId: me,
              ),
          ])
          ..insertAll(db.sourceReferences, [
            for (var i = 0; i < total; i += 2)
              SourceReferencesCompanion.insert(
                itemId: 'masivo-$i',
                volume: Value('$i'),
              ),
          ]);
      });

      final byId = await reader.readMany([
        for (var i = 0; i < total; i++) 'masivo-$i',
      ]);

      expect(byId, hasLength(475));
      expect(byId['masivo-0']!.volume, '0');
      expect(byId['masivo-948']!.volume, '948');
      expect(byId.containsKey('masivo-1'), isFalse);
    });

    test(
      'una obra con personas y sin fila de referencia se lee igual',
      () async {
        await writer.setReference(
          'libro',
          const ReferenceData(contributors: [Contributor(name: garcia)]),
        );
        // Una fusión que escribió con SQL crudo pudo dejarla así.
        await db.delete(db.sourceReferences).go();

        final read = await reader.read('libro');

        expect(read.contributors.single.name, garcia);
      },
    );

    test('sin ids no consulta nada', () async {
      expect(await reader.readMany(const []), isEmpty);
    });
  });
}

KnowledgeItem _source(
  String id, {
  String title = 'Un libro',
  SourceKind kind = SourceKind.webPage,
  DateTime? publishedAt,
}) => KnowledgeItem(
  id: id,
  title: title,
  source: Source(
    id: 'src-$id',
    kind: kind,
    capturedAt: DateTime(2026, 9, 11, 10),
    publishedAt: publishedAt,
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 9, 11, 10),
  updatedAt: DateTime(2026, 9, 11, 10),
);

KnowledgeItem _note(String id) => KnowledgeItem(
  id: id,
  title: 'Una nota',
  source: Source(
    id: 'src-$id',
    kind: SourceKind.manualNote,
    capturedAt: DateTime(2026, 9, 11, 10),
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 9, 11, 10),
  updatedAt: DateTime(2026, 9, 11, 10),
);
