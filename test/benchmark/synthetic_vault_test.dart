import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/vocabulary_hierarchy.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';

import 'synthetic_vault.dart';

/// La bóveda sintética tiene que ser una bóveda VÁLIDA —claves foráneas al
/// día, los dos modelos con los mismos elementos, chunks que reconstruyen el
/// texto— y repetible: si no, ninguna medición sobre ella vale.
void main() {
  const profile = VaultProfile(items: 120);
  late AppDatabase db;
  late SyntheticVault vault;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vault = await buildSyntheticVault(db, profile: profile);
  });

  tearDown(() => db.close());

  test('tiene la forma que pide el perfil', () {
    expect(vault.counts['item'], profile.items);
    expect(vault.counts['renditions'], profile.items);
    expect(vault.counts['note'], profile.notes);
    expect(
      vault.counts['source'],
      profile.items - profile.notes,
      reason: 'una fila de source por cada elemento que no es una nota',
    );
    // Los chunks caen donde caen los cortes: cerca de lo esperado, no igual.
    final chunks = vault.counts['chunks']!;
    expect(chunks, greaterThan(profile.expectedChunks * 0.6));
    expect(chunks, lessThan(profile.expectedChunks * 1.6));
    for (final table in [
      'relations',
      'item_property_values',
      'property_values',
      'highlights',
      'flashcards',
      'inline_link',
    ]) {
      expect(vault.counts[table], greaterThan(0), reason: table);
    }
  });

  test('las claves foráneas están todas al día', () async {
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
  });

  test('cada elemento es una fuente o una nota, no las dos', () async {
    final both = await db
        .customSelect(
          'SELECT id FROM item WHERE id IN (SELECT item_id FROM source) '
          'AND id IN (SELECT item_id FROM note)',
        )
        .get();
    final neither = await db
        .customSelect(
          'SELECT id FROM item WHERE id NOT IN (SELECT item_id FROM source) '
          'AND id NOT IN (SELECT item_id FROM note)',
        )
        .get();
    expect(both, isEmpty);
    expect(neither, isEmpty);
  });

  test('los chunks reconstruyen el texto de cada fuente', () async {
    final report = await verifyChunkInvariant(db);
    expect(report.holds, isTrue, reason: report.violations.join('\n'));
    expect(report.sourcesChecked, vault.counts['source']);
  });

  test('las fuentes puntuales existen', () async {
    for (final id in [
      vault.largestSourceId,
      vault.hubItemId,
      vault.noteWithLinksId,
    ]) {
      final row = await db
          .customSelect(
            'SELECT id FROM item WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .get();
      expect(row, hasLength(1), reason: id);
    }
  });

  test('el índice de texto quedó poblado y sus triggers de vuelta', () async {
    final indexed = await db
        .customSelect('SELECT COUNT(*) AS n FROM item_search')
        .getSingle();
    expect(indexed.read<int>('n'), profile.items);

    final hits = await db
        .customSelect(
          'SELECT item_id FROM item_search WHERE item_search MATCH ?',
          variables: [Variable.withString(vault.commonTerm)],
        )
        .get();
    expect(hits, isNotEmpty);

    // Los triggers se apartaron durante la carga: tienen que estar todos.
    final triggers = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'trigger' "
          "AND name LIKE '%_search_%'",
        )
        .getSingle();
    // Seis del índice de elementos y tres del de chunks.
    expect(triggers.read<int>('n'), 9);

    final chunkIndexed = await db
        .customSelect('SELECT COUNT(*) AS n FROM chunk_search_docsize')
        .getSingle();
    expect(chunkIndexed.read<int>('n'), vault.counts['chunks']);
  });

  test('armarla dos veces da exactamente lo mismo', () async {
    // Dos bases a la vez es justo lo que la prueba necesita, cada una sobre
    // su propia conexión en memoria: la advertencia no aplica.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );
    final again = AppDatabase(NativeDatabase.memory());
    addTearDown(again.close);
    final second = await buildSyntheticVault(again, profile: profile);

    expect(second.counts, vault.counts);
    expect(second.largestSourceId, vault.largestSourceId);
    expect(second.hubItemId, vault.hubItemId);
    expect(second.rareTerm, vault.rareTerm);
    expect(second.bigRootValueId, vault.bigRootValueId);
    expect(second.leafValueId, vault.leafValueId);
  });

  group('«Tema» es una jerarquía (F13, v5 del generador)', () {
    Future<int> count(String sql) async =>
        (await db.customSelect(sql).getSingle()).read<int>('n');

    test(
      'los niveles son coherentes: uno más que el padre, y el primero es 0',
      () async {
        expect(
          await count(
            'SELECT COUNT(*) AS n FROM property_values c '
            'JOIN property_values p ON p.id = c.parent_id '
            'WHERE c.depth <> p.depth + 1',
          ),
          0,
        );
        expect(
          await count(
            'SELECT COUNT(*) AS n FROM property_values '
            'WHERE parent_id IS NULL AND depth <> 0',
          ),
          0,
        );
        // Sin ciclos: a lo largo de un padre el nivel sube estrictamente.
        expect(
          await count(
            'SELECT COUNT(*) AS n FROM property_values '
            'WHERE depth > $kVocabularyMaxDepth',
          ),
          0,
        );
      },
    );

    test('cada valor cuelga de otro de su misma categoría', () async {
      expect(
        await count(
          'SELECT COUNT(*) AS n FROM property_values c '
          'JOIN property_values p ON p.id = c.parent_id '
          'WHERE c.definition_id <> p.definition_id',
        ),
        0,
      );
    });

    test('solo «Tema» tiene jerarquía', () async {
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM property_values '
            'WHERE parent_id IS NOT NULL AND definition_id <> ?',
            variables: [Variable.withString(vault.temaDefinitionId)],
          )
          .getSingle();
      expect(rows.read<int>('n'), 0);
    });

    test(
      '«Tema» tiene una quinta parte de valores y llega a varios niveles',
      () async {
        final tema = await db
            .customSelect(
              'SELECT COUNT(*) AS n, MAX(depth) AS deepest, '
              'SUM(parent_id IS NULL) AS roots FROM property_values '
              'WHERE definition_id = ?',
              variables: [Variable.withString(vault.temaDefinitionId)],
            )
            .getSingle();

        expect(
          tema.read<int>('n'),
          greaterThanOrEqualTo(profile.tagValues ~/ 2),
        );
        expect(tema.read<int>('deepest'), greaterThanOrEqualTo(2));
        expect(
          tema.read<int>('roots'),
          greaterThanOrEqualTo(profile.temaRoots),
        );
      },
    );

    test(
      'el tema raíz grande es el del primer nivel con más subtemas',
      () async {
        final sizes = await db
            .customSelect(
              'WITH RECURSIVE branch(root, id) AS ('
              ' SELECT id, id FROM property_values '
              '  WHERE definition_id = ? AND parent_id IS NULL '
              ' UNION ALL '
              ' SELECT branch.root, pv.id FROM property_values pv '
              '  JOIN branch ON pv.parent_id = branch.id) '
              'SELECT root, COUNT(*) AS n FROM branch GROUP BY root',
              variables: [Variable.withString(vault.temaDefinitionId)],
            )
            .get();
        final bySize = {
          for (final row in sizes) row.read<String>('root'): row.read<int>('n'),
        };

        final biggest = bySize.values.reduce((a, b) => a > b ? a : b);
        expect(bySize[vault.bigRootValueId], biggest);
        // Y es una rama grande de verdad: se lleva una parte considerable.
        expect(biggest, greaterThan(bySize.length));
      },
    );

    test('la hoja no tiene hijos y sí padre', () async {
      final row = await db
          .customSelect(
            'SELECT parent_id, (SELECT COUNT(*) FROM property_values '
            'WHERE parent_id = ?1) AS kids '
            'FROM property_values WHERE id = ?1',
            variables: [Variable.withString(vault.leafValueId)],
          )
          .getSingle();

      expect(row.read<String?>('parent_id'), isNotNull);
      expect(row.read<int>('kids'), 0);
    });

    test(
      'los triggers de la jerarquía volvieron después de la carga',
      () async {
        for (final name in vocabularyHierarchyTriggerNames) {
          expect(
            await count(
              'SELECT COUNT(*) AS n FROM sqlite_master '
              "WHERE type = 'trigger' AND name = '$name'",
            ),
            1,
            reason: name,
          );
        }
      },
    );
  });
}
