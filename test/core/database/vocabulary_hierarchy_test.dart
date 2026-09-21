import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vocabulary_hierarchy.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';

/// Las reglas de la jerarquía del vocabulario (F13) las hace cumplir la BASE:
/// sin ciclos, el padre en la misma categoría, solo en categorías de texto y
/// hasta cinco niveles.
///
/// Todas las pruebas escriben con SQL crudo, no con el repositorio: es lo que
/// hace la fusión de bóvedas, y una regla que solo cumple un camino de
/// escritura no es una regla. Contra SQLite de verdad, porque lo que se
/// verifica son triggers y restricciones, no código Dart.
void main() {
  late AppDatabase db;
  const seconds = 1789000000;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Dos categorías de texto, una de fecha y una de número. Con nombres
    // propios: la base recién creada ya trae «Tema» y «Fecha del hecho».
    for (final (id, name, type) in [
      ('tema', 'Personajes', 'text'),
      ('epoca', 'Época', 'text'),
      ('fecha', 'Fechas de prueba', 'date'),
      ('numero', 'Peso', 'number'),
    ]) {
      await db.customStatement(
        'INSERT INTO property_definitions (id, name, created_at, type) '
        "VALUES ('$id', '$name', $seconds, '$type')",
      );
    }
  });

  tearDown(() => db.close());

  Future<void> value(
    String id, {
    String definition = 'tema',
    String? parent,
    int depth = 0,
  }) => db.customStatement(
    'INSERT INTO property_values '
    '(id, definition_id, value, created_at, parent_id, depth) VALUES '
    "('$id', '$definition', 'Valor $id', $seconds, "
    "${parent == null ? 'NULL' : "'$parent'"}, $depth)",
  );

  Future<void> setParent(String id, String? parent, {int? depth}) =>
      db.customStatement(
        'UPDATE property_values SET parent_id = '
        "${parent == null ? 'NULL' : "'$parent'"}"
        '${depth == null ? '' : ', depth = $depth'} '
        "WHERE id = '$id'",
      );

  Future<Map<String, (String?, int)>> tree() async => {
    for (final row
        in await db
            .customSelect(
              'SELECT id, parent_id, depth FROM property_values ORDER BY id',
            )
            .get())
      row.read<String>('id'): (
        row.readNullable<String>('parent_id'),
        row.read<int>('depth'),
      ),
  };

  Matcher rejects(String reason) => throwsA(
    isA<SqliteException>().having(
      (e) => e.message,
      'mensaje',
      contains(reason),
    ),
  );

  test('los triggers existen en una base recién creada', () async {
    final names = {
      for (final row
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'trigger'",
              )
              .get())
        row.read<String>('name'),
    };

    expect(names, containsAll(vocabularyHierarchyTriggerNames));
  });

  group('un valor sin padre es una raíz', () {
    test('por omisión: sin padre y en profundidad 0', () async {
      await value('a');

      expect(await tree(), {'a': (null, 0)});
    });
  });

  group('un padre válido', () {
    test(
      'se puede poner con una escritura cruda, en la misma categoría',
      () async {
        await value('roma');
        await value('republica');

        await setParent('republica', 'roma', depth: 1);

        expect(await tree(), {'roma': (null, 0), 'republica': ('roma', 1)});
      },
    );

    test('un padre que no existe lo rechaza la clave foránea', () async {
      await expectLater(
        value('republica', parent: 'no-existe', depth: 1),
        throwsA(isA<SqliteException>()),
      );
    });

    test('un valor nuevo puede nacer con padre', () async {
      await value('roma');

      await value('republica', parent: 'roma', depth: 1);

      expect((await tree())['republica'], ('roma', 1));
    });

    test('mover una rama a otro padre de la misma categoría', () async {
      await value('roma');
      await value('grecia');
      await value('republica', parent: 'roma', depth: 1);

      await setParent('republica', 'grecia');

      expect((await tree())['republica']!.$1, 'grecia');
    });
  });

  group('sin ciclos', () {
    test('un valor no puede ser su propio padre, al actualizar', () async {
      await value('a');

      await expectLater(setParent('a', 'a'), rejects('ciclos'));
      expect((await tree())['a']!.$1, isNull);
    });

    test('ni al insertarse', () async {
      await expectLater(value('a', parent: 'a'), rejects('ciclos'));
    });

    test('dos valores no pueden ser padre uno del otro', () async {
      await value('a');
      await value('b', parent: 'a', depth: 1);

      await expectLater(setParent('a', 'b'), rejects('ciclos'));
      expect((await tree())['a']!.$1, isNull);
    });

    test(
      'un valor no puede quedar bajo uno de sus descendientes lejanos',
      () async {
        // a > b > c > d > e: cinco niveles, el máximo.
        await value('a');
        await value('b', parent: 'a', depth: 1);
        await value('c', parent: 'b', depth: 2);
        await value('d', parent: 'c', depth: 3);
        await value('e', parent: 'd', depth: 4);

        for (final descendant in ['b', 'c', 'd', 'e']) {
          await expectLater(
            setParent('a', descendant),
            rejects('ciclos'),
            reason: 'a bajo $descendant cierra un ciclo',
          );
        }
        // Y una rama del medio tampoco puede quedar bajo su propia hoja.
        await expectLater(setParent('b', 'e'), rejects('ciclos'));
        expect((await tree())['a']!.$1, isNull);
        expect((await tree())['b']!.$1, 'a');
      },
    );

    test(
      'mover una rama a un lugar que no es suyo sigue funcionando',
      () async {
        await value('a');
        await value('b', parent: 'a', depth: 1);
        await value('x');

        // `b` sale de `a` y va bajo `x`: no hay ciclo.
        await setParent('b', 'x', depth: 1);

        expect((await tree())['b'], ('x', 1));
      },
    );
  });

  group('el padre es de la misma categoría', () {
    test('al actualizar', () async {
      await value('roma');
      await value('antigua', definition: 'epoca');

      await expectLater(
        setParent('antigua', 'roma', depth: 1),
        rejects('otra categoría'),
      );
    });

    test('al insertar', () async {
      await value('roma');

      await expectLater(
        value('antigua', definition: 'epoca', parent: 'roma', depth: 1),
        rejects('otra categoría'),
      );
    });

    test(
      'cambiar la categoría de un hijo lo deja con un padre ajeno',
      () async {
        await value('roma');
        await value('republica', parent: 'roma', depth: 1);

        await expectLater(
          db.customStatement(
            "UPDATE property_values SET definition_id = 'epoca' "
            "WHERE id = 'republica'",
          ),
          rejects('otra categoría'),
        );
      },
    );
  });

  group('solo las categorías de texto tienen jerarquía', () {
    for (final (definition, kind) in [
      ('fecha', 'fecha'),
      ('numero', 'número'),
    ]) {
      test('una categoría de $kind rechaza un padre, al insertar', () async {
        await value('padre', definition: definition);

        await expectLater(
          value('hijo', definition: definition, parent: 'padre', depth: 1),
          rejects('de texto'),
        );
      });

      test('y al actualizar', () async {
        await value('padre', definition: definition);
        await value('hijo', definition: definition);

        await expectLater(
          setParent('hijo', 'padre', depth: 1),
          rejects('de texto'),
        );
      });
    }
  });

  group('cinco niveles como máximo', () {
    test('el quinto nivel entra, en la profundidad que dice el tope', () async {
      expect(kVocabularyMaxDepth, 4);
      await value('a');
      await value('b', parent: 'a', depth: 1);
      await value('c', parent: 'b', depth: 2);
      await value('d', parent: 'c', depth: 3);

      await value('e', parent: 'd', depth: kVocabularyMaxDepth);

      expect((await tree())['e']!.$2, kVocabularyMaxDepth);
    });

    test('un sexto nivel lo rechaza la restricción de la columna', () async {
      await value('a');
      await value('b', parent: 'a', depth: 1);
      await value('c', parent: 'b', depth: 2);
      await value('d', parent: 'c', depth: 3);
      await value('e', parent: 'd', depth: 4);

      await expectLater(
        value('f', parent: 'e', depth: 5),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'y al mover una rama que pasaría del tope, no queda nada a medias',
      () async {
        // a > b > c y x > y > z > w: mover `a` bajo `w` deja `c` en el nivel 6.
        await value('a');
        await value('b', parent: 'a', depth: 1);
        await value('c', parent: 'b', depth: 2);
        await value('x');
        await value('y', parent: 'x', depth: 1);
        await value('z', parent: 'y', depth: 2);
        await value('w', parent: 'z', depth: 3);
        final before = await tree();

        // Lo que hace el repositorio: todo el subárbol en UNA transacción.
        await expectLater(
          db.transaction(() async {
            await setParent('a', 'w', depth: 4);
            await db.customStatement(
              "UPDATE property_values SET depth = 5 WHERE id = 'b'",
            );
            await db.customStatement(
              "UPDATE property_values SET depth = 6 WHERE id = 'c'",
            );
          }),
          throwsA(isA<Exception>()),
        );

        expect(await tree(), before);
      },
    );
  });

  group('borrar', () {
    test('un padre deja a sus hijos como raíces', () async {
      await value('roma');
      await value('republica', parent: 'roma', depth: 1);

      await db.customStatement("DELETE FROM property_values WHERE id = 'roma'");

      expect((await tree())['republica']!.$1, isNull);
    });

    test('la categoría entera se lleva todo su árbol', () async {
      await value('roma');
      await value('republica', parent: 'roma', depth: 1);

      await db.customStatement(
        "DELETE FROM property_definitions WHERE id = 'tema'",
      );

      expect(await tree(), isEmpty);
    });

    test('no queda ninguna clave que apunte a algo que no existe', () async {
      await value('roma');
      await value('republica', parent: 'roma', depth: 1);
      await db.customStatement("DELETE FROM property_values WHERE id = 'roma'");

      final broken = await db
          .customSelect('SELECT * FROM pragma_foreign_key_check')
          .get();

      expect(broken, isEmpty);
    });
  });
}
