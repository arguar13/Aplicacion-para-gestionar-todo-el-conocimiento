import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_query_sql.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Lo que el mapa lee (F14), contra SQLite de verdad: los temas de una
/// categoría, lo que los une, sin lo que está en la papelera, y respetando el
/// filtro de la biblioteca.
void main() {
  late AppDatabase db;
  late KnowledgeMapRepositoryImpl repository;
  late String tema;
  final now = DateTime(2026, 9, 21, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = KnowledgeMapRepositoryImpl(
      database: db,
      library: LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: InMemoryFileStore(),
      ),
    );
    tema = await _definitionId(db, kTemaCategoryName);
  });

  tearDown(() => db.close());

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
    SourceKind kind = SourceKind.webPage,
  }) async {
    await insertItemRows(db, id: id, title: 'Fuente $id', kind: kind);
    for (final valueId in values) {
      await assign(id, valueId);
    }
  }

  Future<void> note(String id, List<String> values) async {
    await insertItemRows(
      db,
      id: id,
      title: 'Nota $id',
      kind: SourceKind.manualNote,
    );
    for (final valueId in values) {
      await assign(id, valueId);
    }
  }

  var relationCounter = 0;
  Future<void> relate(
    String from,
    String to, {
    RelationKind kind = RelationKind.relatedTo,
    DateTime? reviewedAt,
  }) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'r${relationCounter++}',
          fromItemId: from,
          toItemId: to,
          kind: kind,
          createdAt: now,
          reviewedAt: Value(reviewedAt),
        ),
      );

  Future<TopicGraph> graph({
    LibraryQuery filter = const LibraryQuery(),
  }) async =>
      buildTopicGraph(await repository.readTopicInput(tema, filter: filter));

  TopicEdge? edgeBetween(TopicGraph g, String x, String y) {
    final a = g.indexOf(x)!;
    final b = g.indexOf(y)!;
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    for (final edge in g.edges) {
      if (edge.a == low && edge.b == high) return edge;
    }
    return null;
  }

  /// roma ─ república, grecia, egipto.
  Future<void> seedTopics() async {
    await value('roma', label: 'Roma');
    await value('republica', label: 'República', parent: 'roma', depth: 1);
    await value('grecia', label: 'Grecia');
    await value('egipto', label: 'Egipto');
  }

  test('arma los temas con su jerarquía, su tamaño y lo que los une', () async {
    await seedTopics();
    await source('s1', ['roma', 'grecia']);
    await source('s2', ['republica', 'grecia']);
    await source('s3', ['egipto']);
    await relate('s2', 's3');

    final g = await graph();

    expect(g.definitionName, kTemaCategoryName);
    expect(
      [for (final n in g.nodes) n.valueId],
      ['egipto', 'grecia', 'republica', 'roma'],
    );
    expect(g.nodes[g.indexOf('republica')!].parentId, 'roma');
    expect(g.nodes[g.indexOf('republica')!].depth, 1);
    expect(g.nodes[g.indexOf('grecia')!].itemCount, 2);
    expect(edgeBetween(g, 'roma', 'grecia')!.cooccurrence, 1);
    expect(edgeBetween(g, 'republica', 'grecia')!.cooccurrence, 1);
    // La relación de s2 a s3 une a los temas de uno con los del otro.
    expect(edgeBetween(g, 'republica', 'egipto')!.relations, 1);
    expect(edgeBetween(g, 'grecia', 'egipto')!.relations, 1);
    expect(edgeBetween(g, 'roma', 'egipto'), isNull);
  });

  test(
    'las notas y las fuentes cuentan por igual: el mapa es de temas',
    () async {
      await seedTopics();
      await source('s1', ['roma']);
      await note('n1', ['grecia']);
      await relate('n1', 's1', kind: RelationKind.cites);

      final g = await graph();

      expect(edgeBetween(g, 'roma', 'grecia')!.relations, 1);
      expect(g.nodes[g.indexOf('grecia')!].itemCount, 1);
    },
  );

  test('las contradicciones marcan la tensión, y las abiertas son las que '
      'no se revisaron', () async {
    await seedTopics();
    await source('s1', ['roma']);
    await source('s2', ['grecia']);
    await source('s3', ['grecia']);
    await relate('s1', 's2', kind: RelationKind.contradicts);
    await relate('s1', 's3', kind: RelationKind.contradicts, reviewedAt: now);

    final g = await graph();

    final edge = edgeBetween(g, 'roma', 'grecia')!;
    expect(edge.isTension, isTrue);
    expect(edge.contradictions, 2);
    expect(edge.openContradictions, 1);
  });

  test('solo cuentan los valores de la categoría pedida', () async {
    await seedTopics();
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: 'region',
            name: 'Región',
            createdAt: now,
          ),
        );
    await value('lacio', definitionId: 'region', label: 'Lacio');
    await source('s1', ['roma', 'lacio']);
    await source('s2', ['grecia', 'lacio']);

    final g = await graph();

    expect(g.indexOf('lacio'), isNull);
    // Comparten «Lacio», que no es un tema: no los une.
    expect(g.edges, isEmpty);
    expect(g.nodes[g.indexOf('roma')!].itemCount, 1);
  });

  test('una categoría sin valores da un grafo vacío; una que no existe, una '
      'entrada vacía', () async {
    final empty = await graph();
    expect(empty.nodes, isEmpty);
    expect(empty.definitionName, kTemaCategoryName);

    final missing = await repository.readTopicInput('no-existe');
    expect(missing.values, isEmpty);
    expect(buildTopicGraph(missing).nodes, isEmpty);
  });

  group('la papelera (F11)', () {
    test('un elemento en la papelera no cuenta ni une nada', () async {
      await seedTopics();
      await source('s1', ['roma', 'grecia']);
      await source('s2', ['roma']);
      await trashItemRows(db, 's1');

      final g = await graph();

      expect(g.nodes[g.indexOf('roma')!].itemCount, 1);
      expect(g.nodes[g.indexOf('grecia')!].itemCount, 0);
      expect(g.edges, isEmpty);
    });

    test('una relación con un extremo en la papelera no cuenta', () async {
      await seedTopics();
      await source('s1', ['roma']);
      await source('s2', ['grecia']);
      await relate('s1', 's2', kind: RelationKind.contradicts);
      await trashItemRows(db, 's2');

      expect((await graph()).edges, isEmpty);
    });

    test('al restaurarlo, vuelve todo tal cual estaba', () async {
      await seedTopics();
      await source('s1', ['roma']);
      await source('s2', ['grecia']);
      await relate('s1', 's2');
      final before = await graph();

      await trashItemRows(db, 's2');
      expect((await graph()).edges, isEmpty);
      await restoreItemRows(db, 's2');
      final after = await graph();

      expect(after.edges, hasLength(before.edges.length));
      expect(edgeBetween(after, 'roma', 'grecia')!.relations, 1);
    });
  });

  group('el filtro de la biblioteca (D8)', () {
    test(
      'el grafo se calcula sobre los elementos que pasan el filtro',
      () async {
        await seedTopics();
        await source('s1', ['roma', 'grecia']);
        await source('s2', ['grecia', 'egipto']);
        await source('s3', ['egipto'], kind: SourceKind.document);

        final g = await graph(
          filter: const LibraryQuery(sourceKinds: {SourceKind.webPage}),
        );

        expect(edgeBetween(g, 'roma', 'grecia')!.cooccurrence, 1);
        expect(edgeBetween(g, 'grecia', 'egipto')!.cooccurrence, 1);
        expect(g.nodes[g.indexOf('egipto')!].itemCount, 1);
      },
    );

    test('filtrar por un valor incluye a los de sus subtemas (F13)', () async {
      await seedTopics();
      await source('s-roma', ['roma', 'grecia']);
      await source('s-republica', ['republica', 'egipto']);
      await source('s-otro', ['grecia', 'egipto']);

      final g = await graph(
        filter: const LibraryQuery(propertyValueIds: {'roma'}),
      );

      expect(g.nodes[g.indexOf('roma')!].itemCount, 1);
      expect(g.nodes[g.indexOf('republica')!].itemCount, 1);
      expect(edgeBetween(g, 'republica', 'egipto')!.cooccurrence, 1);
      // `s-otro` no tiene Roma ni un subtema: no cuenta.
      expect(edgeBetween(g, 'grecia', 'egipto'), isNull);
    });

    test(
      'una relación con un extremo que el filtro dejó afuera no cuenta',
      () async {
        await seedTopics();
        await source('s1', ['roma']);
        await source('s2', ['grecia'], kind: SourceKind.document);
        await relate('s1', 's2');

        final g = await graph(
          filter: const LibraryQuery(sourceKinds: {SourceKind.webPage}),
        );

        expect(g.edges, isEmpty);
      },
    );

    test(
      'un filtro que no deja pasar nada da los temas, sin aristas',
      () async {
        await seedTopics();
        await source('s1', ['roma', 'grecia']);

        final g = await graph(filter: const LibraryQuery(ids: <String>{}));

        expect(g.nodes, hasLength(4));
        expect(g.nodes.map((n) => n.itemCount), everyElement(0));
        expect(g.edges, isEmpty);
      },
    );
  });

  group('el tablero', () {
    Future<void> setMaturity(String noteId, NoteMaturity maturity) =>
        (db.update(db.knowledgeNotes)..where((n) => n.itemId.equals(noteId)))
            .write(KnowledgeNotesCompanion(maturity: Value(maturity)));

    test('cuenta los elementos vivos, el crecimiento y la madurez', () async {
      await insertItemRows(
        db,
        id: 's1',
        title: 'Fuente 1',
        createdAt: DateTime(2026, 1, 10),
      );
      await insertItemRows(
        db,
        id: 's2',
        title: 'Fuente 2',
        createdAt: DateTime(2026, 2, 10),
      );
      await insertItemRows(
        db,
        id: 'n1',
        title: 'Nota 1',
        kind: SourceKind.manualNote,
        createdAt: DateTime(2026, 2, 12),
      );
      await insertItemRows(
        db,
        id: 'n2',
        title: 'Nota 2',
        kind: SourceKind.manualNote,
        createdAt: DateTime(2026, 4),
      );
      await setMaturity('n2', NoteMaturity.mature);

      final dashboard = await repository.readDashboard();

      expect(dashboard.itemCount, 4);
      expect(dashboard.sourceCount, 2);
      expect(dashboard.noteCount, 2);
      expect(dashboard.maturity, {
        NoteMaturity.seed: 1,
        NoteMaturity.mature: 1,
      });
      expect(
        [for (final p in dashboard.growth) (p.month, p.added, p.total)],
        [(1, 1, 1), (2, 2, 3), (3, 0, 3), (4, 1, 4)],
      );
    });

    test('las contradicciones abiertas traen los títulos; las revisadas no '
        'están', () async {
      await source('s1', const []);
      await source('s2', const []);
      await source('s3', const []);
      await relate('s1', 's2', kind: RelationKind.contradicts);
      await relate('s1', 's3', kind: RelationKind.contradicts, reviewedAt: now);
      await relate('s2', 's3', kind: RelationKind.cites);

      final dashboard = await repository.readDashboard();

      expect(dashboard.openContradictionCount, 1);
      final open = dashboard.openContradictions.single;
      expect((open.fromTitle, open.toTitle), ('Fuente s1', 'Fuente s2'));
    });

    test(
      'lo que está en la papelera no cuenta, ni sus contradicciones',
      () async {
        await source('s1', const []);
        await source('s2', const []);
        await relate('s1', 's2', kind: RelationKind.contradicts);
        await trashItemRows(db, 's2');

        final dashboard = await repository.readDashboard();

        expect(dashboard.itemCount, 1);
        expect(dashboard.openContradictionCount, 0);
      },
    );

    test('el filtro de la biblioteca también rige acá', () async {
      await source('s1', const []);
      await source('s2', const [], kind: SourceKind.document);
      await source('s3', const [], kind: SourceKind.document);
      await relate('s2', 's3', kind: RelationKind.contradicts);
      await relate('s1', 's2', kind: RelationKind.contradicts);

      final dashboard = await repository.readDashboard(
        filter: const LibraryQuery(sourceKinds: {SourceKind.document}),
      );

      expect(dashboard.itemCount, 2);
      // La de s1 a s2 tiene un extremo que el filtro dejó afuera.
      expect(dashboard.openContradictionCount, 1);
    });

    test('una bóveda sin nada da un tablero vacío', () async {
      final dashboard = await repository.readDashboard();

      expect(dashboard.itemCount, 0);
      expect(dashboard.growth, isEmpty);
    });
  });

  group('el esquema', () {
    Future<void> noteOf(
      String id,
      String title,
      NoteKind kind,
      List<String> values,
    ) async {
      await insertItemRows(
        db,
        id: id,
        title: title,
        kind: SourceKind.manualNote,
      );
      await (db.update(db.knowledgeNotes)..where((n) => n.itemId.equals(id)))
          .write(KnowledgeNotesCompanion(noteKind: Value(kind)));
      for (final valueId in values) {
        await assign(id, valueId);
      }
    }

    test('las notas mapa de un tema, por título, y solo esas', () async {
      await seedTopics();
      await noteOf('m2', 'Zama', NoteKind.map, ['roma']);
      await noteOf('m1', 'Ágora', NoteKind.map, ['roma']);
      await noteOf('v1', 'Viva', NoteKind.living, ['roma']);
      await noteOf('m3', 'De otro tema', NoteKind.map, ['grecia']);
      await source('s1', ['roma']);

      final links = await repository.schemaLinks(const SchemaRef.topic('roma'));

      expect([for (final l in links) l.title], ['Ágora', 'Zama']);
      expect(links.every((l) => l.edge == SchemaEdgeKind.mapNote), isTrue);
      expect(links.every((l) => l.isNote), isTrue);
      expect(links.first.target, const SchemaRef.item('m1'));
    });

    test('una nota mapa en la papelera no sale', () async {
      await seedTopics();
      await noteOf('m1', 'Mapa', NoteKind.map, ['roma']);
      await trashItemRows(db, 'm1');

      expect(
        await repository.schemaLinks(const SchemaRef.topic('roma')),
        isEmpty,
      );
    });

    test(
      'los vínculos de un elemento, en los dos sentidos, con su tipo',
      () async {
        await noteOf('n1', 'Mapa de Roma', NoteKind.map, const []);
        await source('s1', const []);
        await source('s2', const []);
        await noteOf('n2', 'Nota viva', NoteKind.living, const []);
        await relate('n1', 's1', kind: RelationKind.indexes);
        await relate('s2', 'n1', kind: RelationKind.contradicts);
        await relate('n1', 'n2');

        final links = await repository.schemaLinks(const SchemaRef.item('n1'));

        final byTitle = {for (final l in links) l.title: l};
        expect(byTitle.keys, {'Fuente s1', 'Fuente s2', 'Nota viva'});
        final s1 = byTitle['Fuente s1']!;
        expect(s1.relation, RelationKind.indexes);
        expect(s1.outgoing, isTrue);
        expect(s1.isNote, isFalse);
        final s2 = byTitle['Fuente s2']!;
        expect(s2.relation, RelationKind.contradicts);
        expect(s2.outgoing, isFalse);
        expect(byTitle['Nota viva']!.isNote, isTrue);
        expect(links.every((l) => l.edge == SchemaEdgeKind.relation), isTrue);
      },
    );

    test('lo que está en la papelera no sale, y hay un tope', () async {
      await source('centro', const []);
      for (var i = 0; i < 5; i++) {
        await source('o$i', const []);
        await relate('centro', 'o$i');
      }
      await trashItemRows(db, 'o0');

      final all = await repository.schemaLinks(const SchemaRef.item('centro'));
      expect(all, hasLength(4));
      expect(all.map((l) => l.target.id), isNot(contains('o0')));

      final some = await repository.schemaLinks(
        const SchemaRef.item('centro'),
        limit: 2,
      );
      expect(some, hasLength(2));
    });
  });

  group('los elementos de un tema', () {
    Future<void> at(
      String id,
      DateTime when,
      List<String> values, {
      SourceKind kind = SourceKind.webPage,
    }) async {
      await insertItemRows(
        db,
        id: id,
        title: 'Fuente $id',
        createdAt: when,
        kind: kind,
      );
      for (final valueId in values) {
        await assign(id, valueId);
      }
    }

    test(
      'los del tema y los de sus subtemas, los más recientes primero',
      () async {
        await seedTopics();
        await at('viejo', DateTime(2026), ['roma']);
        await at('medio', DateTime(2026, 2), ['republica']);
        await at('nuevo', DateTime(2026, 3), ['roma', 'republica']);
        await at('de-grecia', DateTime(2026, 4), ['grecia']);
        await at('sin-tema', DateTime(2026, 5), const []);

        final graph = await repository.readTopicItems('roma');

        expect(
          [for (final i in graph.items) i.id],
          ['nuevo', 'medio', 'viejo'],
        );
        expect(graph.truncated, isFalse);
        expect(graph.valueId, 'roma');
      },
    );

    test('un subtema solo trae lo suyo', () async {
      await seedTopics();
      await at('de-roma', DateTime(2026), ['roma']);
      await at('de-republica', DateTime(2026, 2), ['republica']);

      final graph = await repository.readTopicItems('republica');

      expect([for (final i in graph.items) i.id], ['de-republica']);
    });

    test('las notas se distinguen de las fuentes', () async {
      await seedTopics();
      await at('s', DateTime(2026), ['roma']);
      await at('n', DateTime(2026, 2), ['roma'], kind: SourceKind.manualNote);

      final graph = await repository.readTopicItems('roma');

      final byId = {for (final i in graph.items) i.id: i};
      expect(byId['s']!.isNote, isFalse);
      expect(byId['n']!.isNote, isTrue);
    });

    test('los vínculos son solo los que unen dos de sus elementos', () async {
      await seedTopics();
      await at('a', DateTime(2026), ['roma']);
      await at('b', DateTime(2026, 2), ['roma']);
      await at('afuera', DateTime(2026, 3), ['grecia']);
      await relate('a', 'b', kind: RelationKind.cites);
      await relate('a', 'afuera');

      final graph = await repository.readTopicItems('roma');

      expect(graph.edges, hasLength(1));
      final edge = graph.edges.single;
      expect(graph.items[edge.a].id, 'a');
      expect(graph.items[edge.b].id, 'b');
      expect(edge.kind, RelationKind.cites);
    });

    test('lo que está en la papelera no sale, ni sus vínculos', () async {
      await seedTopics();
      await at('a', DateTime(2026), ['roma']);
      await at('b', DateTime(2026, 2), ['roma']);
      await relate('a', 'b');
      await trashItemRows(db, 'b');

      final graph = await repository.readTopicItems('roma');

      expect([for (final i in graph.items) i.id], ['a']);
      expect(graph.edges, isEmpty);
    });

    test(
      'con más elementos que el tope, trae los más recientes y avisa',
      () async {
        await seedTopics();
        for (var i = 0; i < 6; i++) {
          await at('i$i', DateTime(2026, 1, 1 + i), ['roma']);
        }

        final graph = await repository.readTopicItems('roma', limit: 4);

        expect([for (final i in graph.items) i.id], ['i5', 'i4', 'i3', 'i2']);
        expect(graph.truncated, isTrue);
      },
    );

    test('un tema sin elementos da un grafo vacío', () async {
      await seedTopics();

      final graph = await repository.readTopicItems('egipto');

      expect(graph.items, isEmpty);
      expect(graph.edges, isEmpty);
      expect(graph.truncated, isFalse);
    });
  });

  group('los avisos de cambio', () {
    /// Si dentro de un rato llegó un aviso, mientras se hace [write].
    Future<bool> notifies(
      Future<void> Function() write, {
      LibraryQuery filter = const LibraryQuery(),
    }) async {
      var notified = false;
      final subscription = repository.changes(filter: filter).listen((_) {
        notified = true;
      });
      await write();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      return notified;
    }

    test(
      'avisan al escribir una relación, una asignación o un valor',
      () async {
        await seedTopics();
        await source('s1', ['roma']);
        await source('s2', ['grecia']);

        expect(await notifies(() => relate('s1', 's2')), isTrue);
        expect(await notifies(() => assign('s2', 'egipto')), isTrue);
        expect(await notifies(() => value('nuevo')), isTrue);
      },
    );

    test('avisan al mandar un elemento a la papelera', () async {
      await seedTopics();
      await source('s1', ['roma']);

      expect(await notifies(() => trashItemRows(db, 's1')), isTrue);
    });

    test('no avisan por lo que el mapa no lee', () async {
      final changed = await notifies(
        () => db
            .into(db.spaces)
            .insert(
              SpacesCompanion.insert(id: 'sp', name: 'Espacio', createdAt: now),
            ),
      );

      expect(changed, isFalse);
    });

    test('con un filtro, también avisan por lo que el filtro mira', () async {
      await seedTopics();
      await source('s1', ['roma']);
      Future<void> retype() =>
          (db.update(
            db.knowledgeSources,
          )..where((s) => s.itemId.equals('s1'))).write(
            const KnowledgeSourcesCompanion(
              sourceType: Value(SourceKind.document),
            ),
          );

      expect(await notifies(retype), isFalse);
      expect(
        await notifies(
          retype,
          filter: const LibraryQuery(sourceKinds: {SourceKind.webPage}),
        ),
        isTrue,
      );
    });
  });

  group('el plan de las consultas', () {
    Future<List<String>> planOf(String sql, List<Variable> args) async {
      final rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: args)
          .get();
      return [for (final r in rows) r.read<String>('detail')];
    }

    test('los elementos se recorren UNA vez y sus valores se buscan por '
        'clave: nada se recorre por cada tema', () async {
      await seedTopics();

      final plan = await planOf(mapItemsSql, [Variable.withString(tema)]);
      final reason = plan.join('\n');

      expect(
        plan.where((line) => RegExp(r'\bSCAN item\b').hasMatch(line)),
        hasLength(1),
        reason: reason,
      );
      expect(
        plan.where((line) => RegExp(r'\bSCAN (ipv|pv)\b').hasMatch(line)),
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
    });

    test('el tablero recorre los elementos una vez, y las contradicciones '
        'buscan sus extremos por clave', () async {
      final items = await planOf(mapDashboardItemsSql, const []);
      expect(
        items.where((line) => line.startsWith('SCAN item')),
        hasLength(1),
        reason: items.join('\n'),
      );

      final contradictions = await planOf(mapOpenContradictionsSql, [
        Variable.withString(RelationKind.contradicts.name),
      ]);
      final reason = contradictions.join('\n');
      expect(
        contradictions.where((line) => line.startsWith('SCAN')),
        hasLength(1),
        reason: reason,
      );
      expect(
        contradictions.where(
          (line) => line.startsWith('SEARCH') && line.contains('(id=?)'),
        ),
        hasLength(2),
        reason: reason,
      );
    });

    test('el esquema busca por clave: las notas de un tema por el índice de '
        'sus asignaciones, y los vínculos de un elemento por los dos '
        'índices de vínculos', () async {
      final notes = await planOf(mapTopicNotesSql, [
        Variable.withString('roma'),
        Variable.withInt(24),
      ]);
      final notesReason = notes.join('\n');
      expect(
        notes.where((line) => line.startsWith('SCAN')),
        isEmpty,
        reason: notesReason,
      );
      expect(
        notes.where(
          (line) =>
              line.startsWith('SEARCH ipv') &&
              line.contains('property_value_id'),
        ),
        hasLength(1),
        reason: notesReason,
      );

      final links = await planOf(mapItemLinksSql, [
        Variable.withString('n1'),
        Variable.withInt(24),
      ]);
      final linksReason = links.join('\n');
      expect(
        links.where(
          (line) => line.startsWith('SCAN') && !line.contains('USING INDEX'),
        ),
        // La única lectura completa es la de la lista de resultados que se
        // ordena, que ya está acotada por las dos búsquedas por clave.
        everyElement(anyOf(contains('SUBQUERY'), contains('COMPOUND'))),
        reason: linksReason,
      );
      expect(
        links.where((line) => line.contains('idx_relations_from')),
        hasLength(1),
        reason: linksReason,
      );
      expect(
        links.where((line) => line.contains('idx_relations_to')),
        hasLength(1),
        reason: linksReason,
      );
    });

    test('los elementos de un tema: las asignaciones del valor por su índice '
        'y los vínculos por el índice del origen', () async {
      final items = await planOf(mapTopicItemsSql, [
        Variable.withString('roma'),
        Variable.withInt(201),
      ]);
      final itemsReason = items.join('\n');
      expect(
        items.where(
          (line) => RegExp(
            r'\bSCAN (item_property_values|property_values)\b',
          ).hasMatch(line),
        ),
        isEmpty,
        reason: itemsReason,
      );
      expect(
        items.where(
          (line) =>
              line.startsWith('SEARCH item_property_values') &&
              line.contains('property_value_id'),
        ),
        hasLength(1),
        reason: itemsReason,
      );

      final relations = await planOf(mapItemsRelationsSql(3), [
        Variable.withString('a'),
        Variable.withString('b'),
        Variable.withString('c'),
      ]);
      expect(
        relations.where(
          (line) =>
              line.startsWith('SEARCH relations') &&
              line.contains('(from_item_id=?)'),
        ),
        hasLength(1),
        reason: relations.join('\n'),
      );
      expect(
        relations.where((line) => line.startsWith('SCAN')),
        isEmpty,
        reason: relations.join('\n'),
      );
    });

    test('las relaciones se recorren una vez y nada más', () async {
      final plan = await planOf(mapRelationsSql, const []);
      final reason = plan.join('\n');

      expect(plan, hasLength(1), reason: reason);
      expect(plan.single, startsWith('SCAN relations'), reason: reason);
    });
  });

  test('las notas de cualquier subtipo son elementos del mapa', () async {
    await seedTopics();
    await insertItemRows(
      db,
      id: 'n-mapa',
      title: 'Mapa de Roma',
      kind: SourceKind.manualNote,
    );
    await (db.update(db.knowledgeNotes)
          ..where((n) => n.itemId.equals('n-mapa')))
        .write(const KnowledgeNotesCompanion(noteKind: Value(NoteKind.map)));
    await assign('n-mapa', 'roma');
    await assign('n-mapa', 'grecia');

    final g = await graph();

    expect(edgeBetween(g, 'roma', 'grecia')!.cooccurrence, 1);
  });
}

Future<String> _definitionId(AppDatabase db, String name) async =>
    (await (db.select(db.propertyDefinitions)..where(
              (d) =>
                  d.isSystem.equals(true) &
                  d.name.lower().equals(name.toLowerCase()),
            ))
            .getSingle())
        .id;
