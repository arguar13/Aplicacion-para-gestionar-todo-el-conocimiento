import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/reference_triggers.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Las tablas de las referencias bibliográficas (F15) en una base recién
/// creada: lo que guardan, lo que la base hace cumplir y lo que pasa con ellas
/// cuando se borra una obra o una persona.
///
/// Las reglas se prueban con SQL crudo, no con el escritor: la fusión de
/// bóvedas escribe así, y una regla que solo cumple un camino de escritura no
/// es una regla. Contra SQLite de verdad, porque lo que se verifica son
/// triggers, restricciones y claves foráneas.
void main() {
  late AppDatabase db;
  late String authorCategory;
  const seconds = 1789000000;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    authorCategory = (await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals('Autor'))).getSingle()).id;
    for (final (id, kind) in [
      ('obra', 'source'),
      ('otra', 'source'),
      ('nota', 'note'),
    ]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Elemento $id', '$kind', 'processed', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
  });

  tearDown(() => db.close());

  Future<void> person(String id, {String? category}) => db.customStatement(
    'INSERT INTO property_values (id, definition_id, value, created_at, '
    'name_family, name_given) VALUES '
    "('$id', '${category ?? authorCategory}', 'Persona $id', $seconds, "
    "'Apellido $id', 'Nombre')",
  );

  Future<void> contributor(
    String item,
    String person, {
    String role = 'author',
    int position = 0,
  }) => db.customStatement(
    'INSERT INTO source_contributor '
    '(item_id, property_value_id, role, position) VALUES '
    "('$item', '$person', '$role', $position)",
  );

  Future<int> count(String table, {String where = '1'}) async =>
      (await db
              .customSelect('SELECT COUNT(*) AS n FROM $table WHERE $where')
              .getSingle())
          .read<int>('n');

  Matcher rejects(String reason) => throwsA(
    isA<SqliteException>().having(
      (e) => e.message,
      'mensaje',
      contains(reason),
    ),
  );

  group('una base recién creada', () {
    test('trae la categoría «Autor», de sistema y de persona', () async {
      final row = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.id.equals(authorCategory))).getSingle();

      expect(row.name, 'Autor');
      expect(row.type, PropertyValueType.person);
      expect(row.isSystem, isTrue);
    });

    test('la siembra trae las tres de sistema, cada una una vez', () async {
      final names = [
        for (final d in await db.select(db.propertyDefinitions).get()) d.name,
      ]..sort();

      expect(names, ['Autor', 'Fecha del hecho', 'Tema']);
    });

    test('tiene los triggers de las referencias', () async {
      final names = {
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'trigger'",
                )
                .get())
          r.read<String>('name'),
      };

      expect(names, containsAll(referenceTriggerNames));
    });
  });

  group('lo que se guarda, con la API de drift', () {
    test('la referencia vuelve con sus tipos', () async {
      await db
          .into(db.sourceReferences)
          .insert(
            SourceReferencesCompanion.insert(
              itemId: 'obra',
              referenceType: const Value(ReferenceType.chapter),
              containerTitle: const Value('Historia de Roma'),
              doi: const Value('10.1000/xyz123'),
              isbn: const Value('9780306406157'),
              accessedAt: Value(DateTime(2026, 9, 21)),
              publicationPrecision: const Value(PublicationPrecision.month),
            ),
          );

      final row = await db.select(db.sourceReferences).getSingle();

      expect(row.referenceType, ReferenceType.chapter);
      expect(row.containerTitle, 'Historia de Roma');
      expect(row.doi, '10.1000/xyz123');
      expect(row.isbn, '9780306406157');
      expect(row.accessedAt, DateTime(2026, 9, 21));
      expect(row.publicationPrecision, PublicationPrecision.month);
      // Lo que no se dijo queda sin decir.
      expect(row.publisher, isNull);
      expect(row.citationKey, isNull);
    });

    test('«sin fecha» se guarda con su nombre', () async {
      await db
          .into(db.sourceReferences)
          .insert(
            SourceReferencesCompanion.insert(
              itemId: 'obra',
              publicationPrecision: const Value(PublicationPrecision.undated),
            ),
          );

      final raw = await db
          .customSelect(
            'SELECT publication_precision AS p FROM source_reference',
          )
          .getSingle();

      expect(raw.read<String>('p'), 'undated');
    });

    test('la persona guarda su apellido y su nombre por separado', () async {
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'gabo',
              definitionId: authorCategory,
              value: 'García Márquez, Gabriel',
              createdAt: DateTime(2026, 9, 21),
              nameFamily: const Value('García Márquez'),
              nameGiven: const Value('Gabriel'),
              isInstitution: const Value(false),
            ),
          );
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'oms',
              definitionId: authorCategory,
              value: 'Organización Mundial de la Salud',
              createdAt: DateTime(2026, 9, 21),
              nameFamily: const Value('Organización Mundial de la Salud'),
              isInstitution: const Value(true),
            ),
          );

      final rows = {
        for (final r in await db.select(db.propertyValues).get()) r.id: r,
      };

      expect(rows['gabo']!.nameFamily, 'García Márquez');
      expect(rows['gabo']!.nameGiven, 'Gabriel');
      expect(rows['gabo']!.nameSuffix, isNull);
      expect(rows['gabo']!.isInstitution, isFalse);
      expect(rows['oms']!.isInstitution, isTrue);
      expect(rows['oms']!.nameGiven, isNull);
    });

    test('las personas de una obra vuelven en su orden, con su rol', () async {
      await person('gabo');
      await person('rabassa');
      await db
          .into(db.sourceContributors)
          .insert(
            SourceContributorsCompanion.insert(
              itemId: 'obra',
              propertyValueId: 'rabassa',
              role: ContributorRole.translator,
              position: 1,
            ),
          );
      await db
          .into(db.sourceContributors)
          .insert(
            SourceContributorsCompanion.insert(
              itemId: 'obra',
              propertyValueId: 'gabo',
              role: ContributorRole.author,
              position: 0,
            ),
          );

      final rows =
          await (db.select(db.sourceContributors)
                ..where((c) => c.itemId.equals('obra'))
                ..orderBy([(c) => OrderingTerm.asc(c.position)]))
              .get();

      expect(
        [for (final r in rows) (r.propertyValueId, r.role)],
        [
          ('gabo', ContributorRole.author),
          ('rabassa', ContributorRole.translator),
        ],
      );
    });
  });

  group('las reglas', () {
    test('una fuente tiene una sola referencia', () async {
      await db.customStatement(
        "INSERT INTO source_reference (item_id) VALUES ('obra')",
      );

      await expectLater(
        db.customStatement(
          "INSERT INTO source_reference (item_id) VALUES ('obra')",
        ),
        rejects('UNIQUE'),
      );
    });

    test('una nota no tiene referencia', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO source_reference (item_id) VALUES ('nota')",
        ),
        rejects('solo una fuente tiene referencia'),
      );
    });

    test('una nota no tiene personas', () async {
      await person('gabo');

      await expectLater(
        contributor('nota', 'gabo'),
        rejects('solo una fuente tiene personas'),
      );
    });

    test('un valor de otra categoría no es un autor', () async {
      await db.customStatement(
        'INSERT INTO property_values (id, definition_id, value, created_at) '
        "SELECT 'roma', id, 'Roma', $seconds FROM property_definitions "
        "WHERE name = 'Tema'",
      );

      await expectLater(
        contributor('obra', 'roma'),
        rejects('solo las personas son autores'),
      );
    });

    test(
      'una persona puede ser autora y traductora de la misma obra',
      () async {
        await person('borges');

        await contributor('obra', 'borges');
        await contributor('obra', 'borges', role: 'translator', position: 1);

        expect(await count('source_contributor'), 2);
      },
    );

    test('una persona no figura dos veces con el mismo rol', () async {
      await person('borges');
      await contributor('obra', 'borges');

      await expectLater(
        contributor('obra', 'borges', position: 1),
        rejects('UNIQUE'),
      );
    });

    test('dos personas no comparten lugar en una obra', () async {
      await person('borges');
      await person('bioy');
      await contributor('obra', 'borges');

      await expectLater(contributor('obra', 'bioy'), rejects('UNIQUE'));
    });

    test('el mismo lugar en dos obras distintas sí', () async {
      await person('borges');
      await contributor('obra', 'borges');

      await contributor('otra', 'borges');

      expect(await count('source_contributor'), 2);
    });

    test('una persona no tiene jerarquía: el trigger de F13 lo impide, y por '
        'eso una categoría con árbol se aplana al pasar a personas', () async {
      await person('boom');
      await person('cortazar');

      await expectLater(
        db.customStatement(
          "UPDATE property_values SET parent_id = 'boom', depth = 1 "
          "WHERE id = 'cortazar'",
        ),
        rejects('solo las categorías de texto tienen jerarquía'),
      );
    });
  });

  group('al borrar', () {
    setUp(() async {
      await person('gabo');
      await person('rabassa');
      await db.customStatement(
        "INSERT INTO source_reference (item_id, doi) VALUES ('obra', 'x/y')",
      );
      await contributor('obra', 'gabo');
      await contributor('obra', 'rabassa', role: 'translator', position: 1);
      // Y lo de otra obra, que no debe moverse.
      await db.customStatement(
        "INSERT INTO source_reference (item_id) VALUES ('otra')",
      );
      await contributor('otra', 'gabo');
    });

    test('una obra se lleva su referencia y sus personas, no las personas '
        'mismas', () async {
      await db.customStatement("DELETE FROM item WHERE id = 'obra'");

      expect(await count('source_reference'), 1);
      expect(await count('source_contributor'), 1);
      expect(await count('source_contributor', where: "item_id = 'otra'"), 1);
      // Las personas siguen en el vocabulario.
      expect(await count('property_values', where: "id = 'gabo'"), 1);
      expect(await count('property_values', where: "id = 'rabassa'"), 1);
    });

    test(
      'una persona deja de figurar en sus obras, y las obras quedan',
      () async {
        await db.customStatement(
          "DELETE FROM property_values WHERE id = 'gabo'",
        );

        expect(await count('source_contributor'), 1);
        expect(
          await count(
            'source_contributor',
            where: "property_value_id = 'rabassa'",
          ),
          1,
        );
        expect(await count('source_reference'), 2);
        expect(await count('item', where: "kind = 'source'"), 2);
      },
    );

    test('borrar toda la categoría de personas vacía las personas de todas las '
        'obras', () async {
      // La categoría es de sistema y el repositorio no deja borrarla; se prueba
      // la base para que una cascada distinta no quede sin verse.
      await db.customStatement(
        "DELETE FROM property_definitions WHERE id = '$authorCategory'",
      );

      expect(await count('source_contributor'), 0);
      expect(await count('source_reference'), 2);
    });

    test('no queda ninguna clave que apunte a algo que no existe', () async {
      await db.customStatement("DELETE FROM item WHERE id = 'obra'");
      await db.customStatement("DELETE FROM property_values WHERE id = 'gabo'");

      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  group('los índices se usan', () {
    Future<String> planOf(String sql, List<Variable> variables) async {
      final rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: variables)
          .get();
      return rows.map((r) => r.read<String>('detail')).join(' | ');
    }

    test('buscar una referencia por su DOI', () async {
      final plan = await planOf(
        'SELECT item_id FROM source_reference WHERE doi = ?',
        [Variable.withString('10.1000/xyz')],
      );

      expect(plan, contains('idx_source_reference_doi'));
    });

    test('buscar una referencia por su ISBN', () async {
      final plan = await planOf(
        'SELECT item_id FROM source_reference WHERE isbn = ?',
        [Variable.withString('9780306406157')],
      );

      expect(plan, contains('idx_source_reference_isbn'));
    });

    test('las obras de una persona', () async {
      final plan = await planOf(
        'SELECT item_id FROM source_contributor WHERE property_value_id = ?',
        [Variable.withString('gabo')],
      );

      expect(plan, contains('idx_source_contributor_person'));
    });
  });
}
