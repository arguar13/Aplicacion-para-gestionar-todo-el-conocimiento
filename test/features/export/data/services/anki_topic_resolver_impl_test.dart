import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/export/data/services/anki_topic_resolver_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// El árbol de Temas y el primer tema de cada elemento (F17, D1/D2), contra
/// SQLite real.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late AnkiTopicResolverImpl resolver;

  final now = DateTime(2026, 9, 25, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'lib'),
      clock: () => now,
    );
    resolver = AnkiTopicResolverImpl(database: db);
  });

  tearDown(() => db.close());

  Future<String> seedItem(String id) async {
    final result = await library.save(
      KnowledgeItem(
        id: id,
        title: 'Elemento $id',
        source: Source(
          id: 'src-$id',
          kind: SourceKind.webPage,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return result.getRight().toNullable()!.id;
  }

  /// Un valor de la categoría Tema.
  Future<String> addTema(String id, String label, {String? parentId}) async {
    final definitionId = await temaDefinitionId(db);
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: definitionId,
            value: label,
            parentId: Value(parentId),
            createdAt: now,
          ),
        );
    return id;
  }

  Future<void> assignTema(String itemId, String temaId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: temaId,
        ),
      );

  test('un elemento sin ningún tema resuelve null', () async {
    final id = await seedItem('a');

    final resolution = await resolver.resolve({id});

    expect(resolution.firstTopicByItem[id], isNull);
  });

  test('un elemento con un solo tema lo resuelve', () async {
    final id = await seedItem('a');
    await addTema('historia', 'Historia');
    await assignTema(id, 'historia');

    final resolution = await resolver.resolve({id});

    expect(resolution.firstTopicByItem[id], 'historia');
    expect(resolution.labelOf['historia'], 'Historia');
  });

  test(
    'con varios temas, resuelve el PRIMERO asignado, no el último (D1)',
    () async {
      final id = await seedItem('a');
      await addTema('historia', 'Historia');
      await addTema('biologia', 'Biología');
      await assignTema(id, 'historia');
      await assignTema(id, 'biologia');

      final resolution = await resolver.resolve({id});

      expect(resolution.firstTopicByItem[id], 'historia');
    },
  );

  test('el árbol trae el padre de un tema anidado', () async {
    final id = await seedItem('a');
    await addTema('historia', 'Historia');
    await addTema('roma', 'Roma', parentId: 'historia');
    await assignTema(id, 'roma');

    final resolution = await resolver.resolve({id});

    expect(resolution.firstTopicByItem[id], 'roma');
    expect(resolution.tree.parentOf('roma'), 'historia');
    expect(resolution.labelOf['historia'], 'Historia');
  });

  test('resuelve varios elementos de una sola vez, sin mezclarlos', () async {
    final a = await seedItem('a');
    final b = await seedItem('b');
    await addTema('historia', 'Historia');
    await addTema('biologia', 'Biología');
    await assignTema(a, 'historia');
    await assignTema(b, 'biologia');

    final resolution = await resolver.resolve({a, b});

    expect(resolution.firstTopicByItem[a], 'historia');
    expect(resolution.firstTopicByItem[b], 'biologia');
  });

  test('un conjunto vacío no pide nada ni rompe', () async {
    final resolution = await resolver.resolve(const {});

    expect(resolution.firstTopicByItem, isEmpty);
  });
}
