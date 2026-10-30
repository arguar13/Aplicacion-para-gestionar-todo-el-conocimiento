import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/data/repositories/board_facts_source_impl.dart';
import 'package:sinapsis/features/map/data/repositories/board_facts_sql.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Lo que el Resumen lee (F44, paso 3), contra SQLite de verdad: los
/// documentos procesados vivos con sus valores y sus vínculos, respetando el
/// filtro, y las tarjetas de cada uno —con las de su fuente— que tocan hoy.
/// Y la forma de las consultas: nada se recorre por cada tema ni por cada
/// tarjeta de la bóveda.
void main() {
  late AppDatabase db;
  late BoardFactsSourceImpl source;
  late String tema;
  final now = DateTime(2026, 10, 30, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    source = BoardFactsSourceImpl(
      database: db,
      library: LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: InMemoryFileStore(),
      ),
    );
    tema = await temaDefinitionId(db);
  });

  tearDown(() => db.close());

  Future<void> value(String id) => db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: tema,
          value: 'Valor $id',
          createdAt: now,
        ),
      );

  Future<void> processed(
    String id, {
    List<String> values = const [],
    String? sourceItemId,
    DateTime? createdAt,
    SourceKind kind = SourceKind.webPage,
  }) async {
    await insertProcessedRows(
      db,
      id: id,
      title: 'Procesado $id',
      sourceItemId: sourceItemId,
      sourceKind: kind,
      createdAt: createdAt ?? DateTime(2026, 10, 20),
    );
    for (final valueId in values) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: id,
              propertyValueId: valueId,
            ),
          );
    }
  }

  var relationCounter = 0;
  Future<void> relate(String from, String to, DateTime at) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'r${relationCounter++}',
          fromItemId: from,
          toItemId: to,
          kind: RelationKind.relatedTo,
          createdAt: at,
        ),
      );

  var cardCounter = 0;
  Future<void> card(
    String itemId, {
    required DateTime dueAt,
    bool suspended = false,
    DateTime? buriedUntil,
  }) => db
      .into(db.flashcards)
      .insert(
        FlashcardsCompanion.insert(
          id: 'f${cardCounter++}',
          itemId: itemId,
          front: '¿?',
          back: '!',
          dueAt: dueAt,
          createdAt: DateTime(2026, 10, 2),
          suspended: Value(suspended),
          buriedUntil: Value(buriedUntil),
        ),
      );

  Future<void> trash(String id) =>
      (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
        KnowledgeEntriesCompanion(deletedAt: Value(now)),
      );

  group('los documentos y sus vínculos', () {
    test('trae cada documento procesado vivo con su título, su fecha y sus '
        'valores, y nada de la Biblioteca', () async {
      await value('roma');
      await value('grecia');
      await processed(
        'p1',
        values: ['roma', 'grecia'],
        createdAt: DateTime(2026, 10, 28, 9),
      );
      await processed('p2');
      await processed('borrado', values: ['roma']);
      await trash('borrado');
      await insertItemRows(db, id: 'fuente', title: 'De la Biblioteca');

      final facts = await source.readFacts(tema);

      final byId = {for (final item in facts.items) item.id: item};
      expect(byId.keys, unorderedEquals(['p1', 'p2']));
      expect(byId['p1']!.title, 'Procesado p1');
      expect(byId['p1']!.createdAt, DateTime(2026, 10, 28, 9));
      expect(byId['p1']!.valueIds, unorderedEquals(['roma', 'grecia']));
      expect(byId['p2']!.valueIds, isEmpty);
    });

    test('con los temas (F28), los valores son sus espacios', () async {
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(id: 'e1', name: 'Uno', createdAt: now),
          );
      await processed('p1');
      await db
          .into(db.itemSpaces)
          .insert(ItemSpacesCompanion.insert(itemId: 'p1', spaceId: 'e1'));

      final facts = await source.readFacts(kSpacesDimensionId);

      expect(facts.items.single.valueIds, ['e1']);
    });

    test('los vínculos, con su fecha, solo entre documentos que pasan el '
        'filtro', () async {
      await processed('web');
      await processed('web2');
      await processed('libro', kind: SourceKind.document);
      await relate('web', 'web2', DateTime(2026, 10, 29));
      await relate('web', 'libro', DateTime(2026, 10, 29));

      final all = await source.readFacts(tema);
      final webOnly = await source.readFacts(
        tema,
        filter: const LibraryQuery(sourceKinds: {SourceKind.webPage}),
      );

      expect(all.links, hasLength(2));
      expect(all.links.first.createdAt, DateTime(2026, 10, 29));
      expect([
        for (final i in webOnly.items) i.id,
      ], unorderedEquals(['web', 'web2']));
      expect(webOnly.links.single.toId, 'web2');
    });
  });

  group('las tarjetas', () {
    test('cuenta las del documento y las de su fuente, y «para hoy» es lo '
        'que vence antes de que termine el día de estudio', () async {
      await insertItemRows(db, id: 'fuente', title: 'Fuente');
      await processed('p1', sourceItemId: 'fuente');
      await processed('p2');
      // Vencida, y una que vence esta noche (antes de las 4:00): para hoy.
      await card('p1', dueAt: DateTime(2026, 10, 29));
      await card('fuente', dueAt: DateTime(2026, 10, 31, 3));
      // Mañana, pausada y pospuesta hasta mañana: no.
      await card('fuente', dueAt: DateTime(2026, 11, 2));
      await card('p1', dueAt: DateTime(2026, 10, 29), suspended: true);
      await card(
        'p1',
        dueAt: DateTime(2026, 10, 29),
        buriedUntil: DateTime(2026, 10, 31, 4),
      );

      final cards = await source.readCards(now);

      expect(cards.keys, ['p1']);
      expect(cards['p1']!.cards, 5);
      expect(cards['p1']!.dueToday, 2);
    });

    test('una fuente en la papelera se lleva sus tarjetas', () async {
      await insertItemRows(db, id: 'fuente', title: 'Fuente');
      await processed('p1', sourceItemId: 'fuente');
      await card('fuente', dueAt: DateTime(2026, 10, 29));
      await trash('fuente');

      expect(await source.readCards(now), isEmpty);
    });

    test('avisa cuando cambia una tarjeta', () async {
      await processed('p1');
      final changes = source.cardChanges().first;

      await card('p1', dueAt: now);

      await expectLater(changes, completes);
    });

    test('un documento sin tarjetas no está', () async {
      await processed('p1');

      expect(await source.readCards(now), const <String, BoardCardFact>{});
    });
  });

  group('la forma de las consultas', () {
    Future<List<String>> planOf(String sql, List<Variable<Object>> args) async {
      final rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: args)
          .get();
      return [for (final r in rows) r.read<String>('detail')];
    }

    test('los documentos se recorren UNA vez y sus valores se buscan por '
        'clave', () async {
      final plan = await planOf(boardItemsSql, [Variable.withString(tema)]);
      final reason = plan.join('\n');

      // Lo único que se recorre entero es `item`.
      final scans = plan.where((d) => d.startsWith('SCAN')).toList();
      expect(scans, hasLength(1), reason: reason);
      expect(scans.single, contains('item'), reason: reason);
      expect(
        plan.any(
          (d) => d.contains('item_property_values') && d.startsWith('SEARCH'),
        ),
        isTrue,
        reason: reason,
      );
    });

    test('las tarjetas se buscan por documento con el índice de su elemento, '
        'sin recorrer las de toda la bóveda', () async {
      final plan = await planOf(boardCardsSql, [
        Variable.withDateTime(now),
        Variable.withDateTime(now),
      ]);
      final reason = plan.join('\n');

      expect(
        plan.any(
          (d) =>
              d.contains('SEARCH f USING INDEX idx_flashcards_item') ||
              d.contains('SEARCH f USING COVERING INDEX idx_flashcards_item'),
        ),
        isTrue,
        reason: reason,
      );
      expect(
        plan.where((d) => d.startsWith('SCAN f')),
        isEmpty,
        reason: reason,
      );
    });
  });
}
