import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notebooks/data/services/notebook_topic_reader_impl.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/processed_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria (F30). Lo que se cuenta son documentos
/// procesados (F41, paso 5): un cuaderno sugerido se llena con ellos.
void main() {
  late AppDatabase db;
  late NotebookTopicReaderImpl reader;
  late OrganizeRepositoryImpl organize;
  late LibraryRepositoryImpl library;
  final now = DateTime(2026, 10, 8, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    reader = NotebookTopicReaderImpl(
      database: db,
      telemetry: MockTelemetryService(),
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'org'),
      clock: () => now,
    );
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
  });

  tearDown(() => db.close());

  Future<void> item(String id, {DateTime? createdAt}) => insertProcessedRows(
    db,
    id: id,
    title: 'Título $id',
    createdAt: createdAt,
  );

  Future<String> tag(String name, {String? parent}) async {
    final created = (await organize.getOrCreateTag(
      name,
    )).getRight().toNullable()!;
    if (parent != null) {
      await (db.update(
        db.propertyValues,
      )..where((v) => v.id.equals(created.id))).write(
        PropertyValuesCompanion(parentId: Value(parent), depth: const Value(1)),
      );
    }
    return created.id;
  }

  Future<void> label(String itemId, String tagName) async {
    await organize.assignProperty(
      itemId: itemId,
      definitionId: await temaDefinitionId(db),
      value: tagName,
    );
  }

  Future<List<NotebookTopic>> topics() => reader.watchTopics().first;

  test('los temas, con cuántos elementos vivos tiene cada uno; sin los vacíos '
      'ni lo que está en la papelera', () async {
    final roma = (await organize.createSpace('Roma')).getRight().toNullable()!;
    await organize.createSpace('Vacío');
    for (final id in ['a', 'b', 'c']) {
      await item(id);
      await library.setSpaces(itemIds: [id], spaceIds: {roma.id});
    }
    await library.delete('c');

    final found = await topics();

    expect(found, [
      NotebookTopic(
        kind: NotebookTopicKind.space,
        id: roma.id,
        name: 'Roma',
        itemCount: 2,
      ),
    ]);
  });

  test('lo que está en dos temas cuenta en cada uno, y sale entre los títulos '
      'de los dos (F37)', () async {
    final roma = (await organize.createSpace('Roma')).getRight().toNullable()!;
    final arte = (await organize.createSpace('Arte')).getRight().toNullable()!;
    await item('a');
    await item('b');
    await library.setSpaces(itemIds: ['a'], spaceIds: {roma.id, arte.id});
    await library.setSpaces(itemIds: ['b'], spaceIds: {roma.id});

    final byName = {for (final t in await topics()) t.name: t};

    expect(byName['Roma']!.itemCount, 2);
    expect(byName['Arte']!.itemCount, 1);
    expect(
      await reader.sampleTitles(NotebookSuggestion(topic: byName['Arte']!)),
      ['Título a'],
    );
  });

  test('una etiqueta cuenta lo suyo y lo de todas sus ramas, sin repetir un '
      'elemento que tiene dos', () async {
    final historia = await tag('Historia');
    await tag('Roma', parent: historia);
    await tag('Grecia', parent: historia);
    await tag('Sin elementos');
    for (final id in ['a', 'b', 'c', 'd']) {
      await item(id);
    }
    await label('a', 'Historia');
    await label('b', 'Roma');
    await label('c', 'Roma');
    await label('c', 'Grecia');
    await label('d', 'Grecia');
    await library.delete('d');

    final byName = {for (final t in await topics()) t.name: t};

    expect(byName['Historia']!.itemCount, 3);
    expect(byName['Historia']!.parentId, isNull);
    expect(byName['Roma']!.itemCount, 2);
    expect(byName['Roma']!.parentId, historia);
    expect(byName['Grecia']!.itemCount, 1);
    expect(byName.containsKey('Sin elementos'), isFalse);
    expect(byName.values.every((t) => t.kind == NotebookTopicKind.tag), isTrue);
  });

  test('las fuentes de la Biblioteca no cuentan: solo lo procesado', () async {
    final roma = (await organize.createSpace('Roma')).getRight().toNullable()!;
    await tag('Imperio');
    for (final id in ['f1', 'f2', 'f3']) {
      await insertItemRows(db, id: id, title: 'Fuente $id');
      await library.setSpaces(itemIds: [id], spaceIds: {roma.id});
      await label(id, 'Imperio');
    }
    await item('p1');
    await library.setSpaces(itemIds: ['p1'], spaceIds: {roma.id});
    await label('p1', 'Imperio');

    final found = await topics();

    expect(
      {for (final t in found) t.name: t.itemCount},
      {'Roma': 1, 'Imperio': 1},
    );
    final suggestion = NotebookSuggestion(topic: found.first);
    expect(await reader.sampleTitles(suggestion), ['Título p1']);
  });

  test('se actualiza solo cuando entra algo', () async {
    final roma = (await organize.createSpace('Roma')).getRight().toNullable()!;
    await item('a');
    await library.setSpaces(itemIds: ['a'], spaceIds: {roma.id});

    final counts = <int>[];
    final subscription = reader.watchTopics().listen(
      (topics) => counts.add(topics.single.itemCount),
    );
    await pumpEventQueue();
    await item('b');
    await library.setSpaces(itemIds: ['b'], spaceIds: {roma.id});
    await pumpEventQueue();
    await subscription.cancel();

    expect(counts.first, 1);
    expect(counts.last, 2);
  });

  group('sampleTitles', () {
    test('lo más reciente del tema', () async {
      final roma = (await organize.createSpace(
        'Roma',
      )).getRight().toNullable()!;
      for (var i = 0; i < 5; i++) {
        await item('e$i', createdAt: now.add(Duration(days: i)));
        await library.setSpaces(itemIds: ['e$i'], spaceIds: {roma.id});
      }
      await item('otro');
      final suggestion = NotebookSuggestion(
        topic: NotebookTopic(
          kind: NotebookTopicKind.space,
          id: roma.id,
          name: 'Roma',
          itemCount: 5,
        ),
      );

      expect(await reader.sampleTitles(suggestion), [
        'Título e4',
        'Título e3',
        'Título e2',
      ]);
    });

    test('de una etiqueta, también lo de sus ramas', () async {
      final historia = await tag('Historia');
      await tag('Roma', parent: historia);
      await item('a', createdAt: now);
      await item('b', createdAt: now.add(const Duration(days: 1)));
      await label('a', 'Historia');
      await label('b', 'Roma');
      final suggestion = NotebookSuggestion(
        topic: NotebookTopic(
          kind: NotebookTopicKind.tag,
          id: historia,
          name: 'Historia',
          itemCount: 2,
        ),
      );

      expect(await reader.sampleTitles(suggestion, limit: 5), [
        'Título b',
        'Título a',
      ]);
    });
  });
}
