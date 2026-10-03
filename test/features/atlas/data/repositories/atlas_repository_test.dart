import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/atlas/data/repositories/atlas_query_sql.dart';
import 'package:sinapsis/features/atlas/data/repositories/atlas_repository_impl.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_coverage.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';

import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Los agregados del Atlas (F13), contra SQLite de verdad: cuentan en cascada
/// por la jerarquía, sin repetir un elemento dentro de una rama, sin lo que
/// está en la papelera, y se recalculan solo cuando algo cambia.
void main() {
  late AppDatabase db;
  late AtlasRepositoryImpl repository;
  late String tema;
  final now = DateTime(2026, 9, 21, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = AtlasRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => now,
    );
    tema = await _definitionId(db, kTemaCategoryName);
  });

  tearDown(() async {
    await repository.dispose();
    await db.close();
  });

  Future<void> value(
    String id, {
    String? parent,
    int depth = 0,
    String? definitionId,
    String? label,
  }) => db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: definitionId ?? tema,
          value: label ?? 'Valor $id',
          createdAt: now,
          parentId: Value(parent),
          depth: Value(depth),
        ),
      );

  Future<void> assign(String itemId, String valueId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: valueId,
        ),
      );

  Future<void> source(
    String id,
    List<String> values, {
    DateTime? updatedAt,
  }) async {
    await insertItemRows(
      db,
      id: id,
      title: 'Fuente $id',
      createdAt: updatedAt ?? now,
    );
    for (final valueId in values) {
      await assign(id, valueId);
    }
  }

  Future<void> note(
    String id,
    NoteKind kind,
    List<String> values, {
    NoteMaturity maturity = NoteMaturity.seed,
    DateTime? updatedAt,
  }) async {
    await insertItemRows(
      db,
      id: id,
      title: 'Nota $id',
      createdAt: updatedAt ?? now,
      kind: SourceKind.manualNote,
    );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(noteKind: Value(kind), maturity: Value(maturity)),
    );
    for (final valueId in values) {
      await assign(id, valueId);
    }
  }

  /// Una «Fecha del hecho» de un solo año, asignada a [itemIds].
  Future<void> factDate(
    String id,
    int year,
    List<String> itemIds, {
    int? toYear,
  }) async {
    final fecha = await _definitionId(db, kFechaDelHechoCategoryName);
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: fecha,
            value: 'Año $year',
            createdAt: now,
            dateFromYear: Value(year),
            dateToYear: Value(toYear ?? year),
            datePrecision: const Value(DatePrecision.year),
          ),
        );
    for (final itemId in itemIds) {
      await assign(itemId, id);
    }
  }

  /// roma ─ república ─ gracos, roma ─ imperio, grecia sola y vacio sin nada.
  Future<void> seedTree() async {
    await value('roma');
    await value('republica', parent: 'roma', depth: 1);
    await value('gracos', parent: 'republica', depth: 2);
    await value('imperio', parent: 'roma', depth: 1);
    await value('grecia');
    await value('vacio');
  }

  Future<AtlasSnapshot> atlas() => repository.snapshot(tema);

  test(
    'cuenta en cascada: cada rama trae lo suyo y lo de sus subtemas',
    () async {
      await seedTree();
      await source('s-roma', ['roma']);
      await source('s-republica', ['republica']);
      await source('s-gracos', ['gracos']);
      await source('s-imperio', ['imperio']);
      await source('s-grecia', ['grecia']);

      final snapshot = await atlas();

      expect(snapshot.nodeOf('roma')!.sourceCount, 4);
      expect(snapshot.nodeOf('republica')!.sourceCount, 2);
      expect(snapshot.nodeOf('gracos')!.sourceCount, 1);
      expect(snapshot.nodeOf('imperio')!.sourceCount, 1);
      expect(snapshot.nodeOf('grecia')!.sourceCount, 1);
      expect(snapshot.nodeOf('vacio')!.itemCount, 0);
    },
  );

  test('un elemento asignado a varios valores de una rama cuenta una vez en '
      'ella', () async {
    await seedTree();
    await source('s-dos', ['roma', 'republica', 'gracos']);
    await source('s-otro', ['republica', 'imperio']);

    final snapshot = await atlas();

    expect(snapshot.nodeOf('roma')!.sourceCount, 2);
    expect(snapshot.nodeOf('republica')!.sourceCount, 2);
    expect(snapshot.nodeOf('gracos')!.sourceCount, 1);
    expect(snapshot.nodeOf('imperio')!.sourceCount, 1);
  });

  test('asignar el hijo no asigna el padre, pero el Atlas cuenta hacia '
      'abajo', () async {
    await seedTree();
    await source('s-gracos', ['gracos']);

    await atlas();

    final direct = await (db.select(
      db.itemPropertyValues,
    )..where((r) => r.propertyValueId.equals('roma'))).get();
    expect(direct, isEmpty);
    expect((await atlas()).nodeOf('roma')!.sourceCount, 1);
  });

  test('separa fuentes y notas, y las notas por subtipo y madurez', () async {
    await seedTree();
    await source('s1', ['roma']);
    await note('n-atomica', NoteKind.atomic, ['gracos']);
    await note('n-semilla', NoteKind.living, ['republica']);
    await note('n-desarrollo', NoteKind.living, [
      'republica',
    ], maturity: NoteMaturity.developing);
    await note('n-madura', NoteKind.living, [
      'imperio',
    ], maturity: NoteMaturity.mature);
    await note('n-mapa', NoteKind.map, ['roma']);

    final snapshot = await atlas();

    final roma = snapshot.nodeOf('roma')!;
    expect(roma.sourceCount, 1);
    expect(roma.atomicCount, 1);
    expect(roma.growingLivingCount, 2);
    expect(roma.matureLivingCount, 1);
    expect(roma.mapCount, 1);
    expect(roma.itemCount, 6);
    final republica = snapshot.nodeOf('republica')!;
    expect(republica.growingLivingCount, 2);
    expect(republica.matureLivingCount, 0);
    expect(republica.atomicCount, 1);
  });

  test(
    'el estado de cobertura de cada rama sale de lo que hay debajo',
    () async {
      await seedTree();
      await source('s-grecia', ['grecia']);
      await source('s-gracos', ['gracos']);
      await note('n-atomica', NoteKind.atomic, ['gracos']);
      await note('n-viva', NoteKind.living, ['republica']);
      await note('n-madura', NoteKind.living, [
        'imperio',
      ], maturity: NoteMaturity.mature);

      final snapshot = await atlas();

      Map<String, AtlasCoverage> coverage() => {
        for (final n in snapshot.nodes) n.valueId: n.coverage,
      };
      expect(coverage(), {
        'roma': AtlasCoverage.mature,
        'republica': AtlasCoverage.growing,
        'gracos': AtlasCoverage.fragments,
        'imperio': AtlasCoverage.mature,
        'grecia': AtlasCoverage.sourcesOnly,
        'vacio': AtlasCoverage.empty,
      });
    },
  );

  test(
    'lo que está en la papelera no cuenta, y al restaurarlo vuelve',
    () async {
      await seedTree();
      await source('s-vivo', ['roma']);
      await source('s-borrado', ['roma']);
      await note('n-borrada', NoteKind.living, ['roma']);
      await trashItemRows(db, 's-borrado');
      await trashItemRows(db, 'n-borrada');

      final afterTrash = await atlas();
      expect(afterTrash.nodeOf('roma')!.sourceCount, 1);
      expect(afterTrash.nodeOf('roma')!.livingCount, 0);

      await restoreItemRows(db, 's-borrado');
      await pumpEventQueue();
      final restored = await atlas();
      expect(restored.nodeOf('roma')!.sourceCount, 2);
    },
  );

  test('las notas mapa se listan en su rama y en las de arriba, sin las '
      'borradas', () async {
    await seedTree();
    await note('m-gracos', NoteKind.map, ['gracos']);
    await note('m-roma', NoteKind.map, ['roma']);
    await note('m-borrado', NoteKind.map, ['roma']);
    await trashItemRows(db, 'm-borrado');

    final snapshot = await atlas();

    List<String> maps(String id) => [
      for (final m in snapshot.nodeOf(id)!.mapNotes) m.id,
    ];
    expect(maps('gracos'), ['m-gracos']);
    expect(maps('republica'), ['m-gracos']);
    expect(maps('roma'), unorderedEquals(['m-gracos', 'm-roma']));
    expect(maps('grecia'), isEmpty);
    expect(snapshot.nodeOf('roma')!.mapNotes.first.title, startsWith('Nota'));
  });

  group('eje temporal', () {
    test('el rango de «Fecha del hecho» de lo que hay en la rama', () async {
      await seedTree();
      await source('s1', ['roma']);
      await source('s2', ['republica']);
      await source('s3', ['gracos']);
      await factDate('f-antiguo', -753, ['s1']);
      await factDate('f-tardio', 476, ['s3'], toYear: 480);

      final snapshot = await atlas();

      expect(snapshot.nodeOf('roma')!.firstYear, -753);
      expect(snapshot.nodeOf('roma')!.lastYear, 480);
      // República solo alcanza a s2 (sin fecha) y a s3.
      expect(snapshot.nodeOf('republica')!.firstYear, 476);
      expect(snapshot.nodeOf('republica')!.lastYear, 480);
      expect(snapshot.nodeOf('gracos')!.firstYear, 476);
      expect(snapshot.nodeOf('imperio')!.firstYear, isNull);
      expect(snapshot.nodeOf('imperio')!.lastYear, isNull);
    });

    test('un elemento con varias fechas aporta el rango entero', () async {
      await seedTree();
      await source('s1', ['grecia']);
      await factDate('f1', -490, ['s1']);
      await factDate('f2', -404, ['s1']);

      final grecia = (await atlas()).nodeOf('grecia')!;

      expect(grecia.firstYear, -490);
      expect(grecia.lastYear, -404);
    });

    test('un valor de fecha no cuenta como elemento ni como rama', () async {
      await seedTree();
      await source('s1', ['roma']);
      await factDate('f1', 44, ['s1']);

      final snapshot = await atlas();

      expect(snapshot.nodes.map((n) => n.valueId), isNot(contains('f1')));
      expect(snapshot.nodeOf('roma')!.itemCount, 1);
    });
  });

  test(
    '«última vez que se tocó» es la más reciente de la rama entera',
    () async {
      await seedTree();
      final viejo = now.subtract(const Duration(days: 300));
      final reciente = now.subtract(const Duration(days: 2));
      await source('s-viejo', ['roma'], updatedAt: viejo);
      await source('s-reciente', ['gracos'], updatedAt: reciente);

      final snapshot = await atlas();

      // Los instantes se guardan en segundos: se compara sin fracciones.
      bool sameInstant(DateTime? a, DateTime b) =>
          a != null && a.difference(b).abs() < const Duration(seconds: 1);
      expect(
        sameInstant(snapshot.nodeOf('roma')!.lastTouched, reciente),
        isTrue,
      );
      expect(
        sameInstant(snapshot.nodeOf('republica')!.lastTouched, reciente),
        isTrue,
      );
      expect(snapshot.nodeOf('imperio')!.lastTouched, isNull);
    },
  );

  test('los vacíos salen de los agregados', () async {
    await seedTree();
    for (var i = 0; i < 5; i++) {
      await source('s-grecia-$i', ['grecia']);
    }
    await source('s-imperio', ['imperio']);

    final snapshot = await atlas();

    expect(
      snapshot.gaps,
      contains(_gap(AtlasGapKind.manySourcesNoLivingNote, 'grecia')),
    );
    // Un solo elemento en toda la rama de Roma —el de Imperio—: se avisa en la
    // rama más alta, no en Imperio.
    expect(snapshot.gaps, contains(_gap(AtlasGapKind.singleItem, 'roma')));
    expect(
      snapshot.gaps,
      isNot(contains(_gap(AtlasGapKind.singleItem, 'imperio'))),
    );
  });

  test('una categoría no mezcla los valores de otra', () async {
    await seedTree();
    const otra = 'def-otra';
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: otra,
            name: 'Personaje',
            createdAt: now,
            type: const Value(PropertyValueType.text),
          ),
        );
    await value('cesar', definitionId: otra, label: 'César');
    await source('s1', ['roma', 'cesar']);

    final temaAtlas = await atlas();
    final otraAtlas = await repository.snapshot(otra);

    expect(temaAtlas.definitionName, 'Tema');
    expect(temaAtlas.nodeOf('cesar'), isNull);
    expect(temaAtlas.nodeOf('roma')!.sourceCount, 1);
    expect(otraAtlas.definitionName, 'Personaje');
    expect([for (final n in otraAtlas.nodes) n.valueId], ['cesar']);
    expect(otraAtlas.nodeOf('cesar')!.sourceCount, 1);
  });

  test('una categoría que no existe da un Atlas vacío', () async {
    final snapshot = await repository.snapshot('no-existe');

    expect(snapshot.nodes, isEmpty);
    expect(snapshot.gaps, isEmpty);
    expect(snapshot.definitionId, 'no-existe');
  });

  group('los temas (F28)', () {
    Future<void> space(String id, String name) => db
        .into(db.spaces)
        .insert(SpacesCompanion.insert(id: id, name: name, createdAt: now));

    Future<void> moveTo(String itemId, String spaceId) =>
        (db.update(db.knowledgeEntries)..where((e) => e.id.equals(itemId)))
            .write(KnowledgeEntriesCompanion(spaceId: Value(spaceId)));

    Future<AtlasSnapshot> spacesAtlas() =>
        repository.snapshot(kSpacesDimensionId);

    test('cada tema es una rama del primer nivel, sin subtemas, con lo que '
        'está en él contado como en una rama de etiquetas', () async {
      await space('historia', 'Historia');
      await space('arte', 'Arte');
      await source('s1', const []);
      await source('s2', const []);
      await note('n1', NoteKind.living, const []);
      await source('suelto', const []);
      for (final id in ['s1', 's2', 'n1']) {
        await moveTo(id, 'historia');
      }

      final snapshot = await spacesAtlas();

      expect([for (final n in snapshot.nodes) n.label], ['Arte', 'Historia']);
      expect(snapshot.nodes.every((n) => n.depth == 0), isTrue);
      final historia = snapshot.nodeOf('historia')!;
      expect(historia.sourceCount, 2);
      expect(historia.growingLivingCount, 1);
      expect(historia.hasChildren, isFalse);
      expect(snapshot.nodeOf('arte')!.coverage, AtlasCoverage.empty);
    });

    test('las notas mapa de un tema son las que están en él', () async {
      await space('historia', 'Historia');
      await note('m1', NoteKind.map, const []);
      await moveTo('m1', 'historia');

      final snapshot = await spacesAtlas();

      expect(
        [for (final n in snapshot.nodeOf('historia')!.mapNotes) n.id],
        ['m1'],
      );
    });

    test('lo que está en la papelera no cuenta', () async {
      await space('historia', 'Historia');
      await source('s1', const []);
      await moveTo('s1', 'historia');
      await trashItemRows(db, 's1');

      final snapshot = await spacesAtlas();

      expect(snapshot.nodeOf('historia')!.itemCount, 0);
    });

    test('crear un tema descarta la caché de los temas', () async {
      await spacesAtlas();
      await space('historia', 'Historia');

      final snapshot = await spacesAtlas();

      expect(snapshot.nodes, hasLength(1));
      expect(repository.computations, 2);
    });
  });

  group('caché', () {
    test('sin ninguna escritura en medio no se recalcula', () async {
      await seedTree();
      await source('s1', ['roma']);

      final first = await atlas();
      final second = await atlas();

      expect(repository.computations, 1);
      expect(identical(first, second), isTrue);
    });

    test('cada categoría tiene la suya', () async {
      await seedTree();

      await atlas();
      await repository.snapshot('otra-cosa');
      await atlas();

      expect(repository.computations, 2);
    });

    test('asignar una propiedad la descarta y el Atlas lo refleja', () async {
      await seedTree();
      await source('s1', ['roma']);
      expect((await atlas()).nodeOf('roma')!.sourceCount, 1);

      await source('s2', ['gracos']);

      final after = await atlas();
      expect(repository.computations, 2);
      expect(after.nodeOf('roma')!.sourceCount, 2);
    });

    test('mover un valor en el vocabulario la descarta', () async {
      await seedTree();
      await source('s-gracos', ['gracos']);
      expect((await atlas()).nodeOf('imperio')!.sourceCount, 0);

      // Gracos pasa de República a Imperio: el subárbol se mueve entero.
      await (db.update(db.propertyValues)..where((v) => v.id.equals('gracos')))
          .write(const PropertyValuesCompanion(parentId: Value('imperio')));

      final after = await atlas();
      expect(repository.computations, 2);
      expect(after.nodeOf('imperio')!.sourceCount, 1);
      expect(after.nodeOf('republica')!.sourceCount, 0);
    });

    test('mandar un elemento a la papelera la descarta', () async {
      await seedTree();
      await source('s1', ['roma']);
      expect((await atlas()).nodeOf('roma')!.sourceCount, 1);

      await trashItemRows(db, 's1');

      expect((await atlas()).nodeOf('roma')!.sourceCount, 0);
    });

    test('lo que no toca al Atlas no la descarta', () async {
      await seedTree();
      await source('s1', ['roma']);
      await atlas();

      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: 'c1',
              mode: ChatConversationMode.vault,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await atlas();
      expect(repository.computations, 1);
    });
  });

  group('reactividad', () {
    test('emite lo que hay al suscribirse y vuelve a emitir cuando se asigna '
        'una propiedad', () async {
      await seedTree();
      await source('s1', ['roma']);
      final emitted = <AtlasSnapshot>[];
      final subscription = repository.watchAtlas(tema).listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emitted, hasLength(1));
      expect(emitted.last.nodeOf('roma')!.sourceCount, 1);

      await source('s2', ['gracos']);
      await pumpEventQueue();

      expect(emitted.last.nodeOf('roma')!.sourceCount, 2);
      expect(emitted.last.nodeOf('gracos')!.sourceCount, 1);
    });

    test(
      'un segundo observador con el Atlas ya calculado no recalcula',
      () async {
        await seedTree();
        await source('s1', ['roma']);
        final first = <AtlasSnapshot>[];
        final one = repository.watchAtlas(tema).listen(first.add);
        addTearDown(one.cancel);
        await pumpEventQueue();
        final computedOnce = repository.computations;

        final second = <AtlasSnapshot>[];
        final two = repository.watchAtlas(tema).listen(second.add);
        addTearDown(two.cancel);
        await pumpEventQueue();

        expect(second, hasLength(1));
        expect(repository.computations, computedOnce);
      },
    );
  });

  group('el plan de las consultas', () {
    Future<List<String>> planOf(String sql, List<Variable> args) async {
      final rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: args)
          .get();
      return [for (final r in rows) r.read<String>('detail')];
    }

    test('los elementos se recorren UNA vez, y sus valores y sus notas se '
        'buscan por clave: nada se recorre por cada rama', () async {
      await seedTree();

      final plan = await planOf(atlasItemsSql, [
        Variable.withString(tema),
        Variable.withString(kFechaDelHechoCategoryName),
      ]);
      final reason = plan.join('\n');

      // Cada elemento una vez —no una por cada rama en que está—.
      expect(
        plan.where((line) => RegExp(r'\bSCAN item\b').hasMatch(line)),
        hasLength(1),
        reason: reason,
      );
      // Las asignaciones nunca se recorren enteras: las de un elemento por su
      // clave, las de las fechas por el índice del valor.
      expect(
        plan.where((line) => RegExp(r'\bSCAN ipv\b').hasMatch(line)),
        isEmpty,
        reason: reason,
      );
      expect(
        plan.where(
          (line) =>
              line.startsWith('SEARCH ipv') && line.contains('(item_id=?)'),
        ),
        hasLength(1),
        reason: reason,
      );
      expect(
        plan.where(
          (line) =>
              line.startsWith('SEARCH note') && line.contains('(item_id=?)'),
        ),
        hasLength(1),
        reason: reason,
      );
    });

    test('el Atlas de los temas también recorre los elementos UNA vez: el '
        'tema es una columna del elemento (F28)', () async {
      final plan = await planOf(atlasSpaceItemsSql, [
        Variable.withString(kFechaDelHechoCategoryName),
      ]);
      final reason = plan.join('\n');

      expect(
        plan.where((line) => RegExp(r'\bSCAN item\b').hasMatch(line)),
        hasLength(1),
        reason: reason,
      );
      expect(
        plan.where((line) => RegExp(r'\bSCAN ipv\b').hasMatch(line)),
        isEmpty,
        reason: reason,
      );
    });

    test('las notas mapa empiezan por las notas mapa: no por las '
        'asignaciones de toda la categoría', () async {
      await seedTree();

      final plan = await planOf(atlasMapNotesSql, [Variable.withString(tema)]);
      final reason = plan.join('\n');

      // Se recorren las notas —unas pocas— y de cada una, por su clave, el
      // elemento, sus asignaciones y el valor.
      expect(
        plan.where((line) => RegExp(r'\bSCAN note\b').hasMatch(line)),
        hasLength(1),
        reason: reason,
      );
      expect(
        plan.where((line) => RegExp(r'\bSCAN (item|ipv|pv)\b').hasMatch(line)),
        isEmpty,
        reason: reason,
      );
    });
  });
}

AtlasGap _gap(AtlasGapKind kind, String valueId) =>
    AtlasGap(kind: kind, valueId: valueId);

Future<String> _definitionId(AppDatabase db, String name) async =>
    (await (db.select(db.propertyDefinitions)..where(
              (d) =>
                  d.isSystem.equals(true) &
                  d.name.lower().equals(name.toLowerCase()),
            ))
            .getSingle())
        .id;
