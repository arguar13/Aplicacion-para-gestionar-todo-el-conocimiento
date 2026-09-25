import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/export/data/services/anki_topic_resolver_impl.dart';
import 'package:sinapsis/features/flashcards/data/services/quiz_session_summary_service_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real: qué tema del Atlas concentró los errores de una
/// sesión de quiz, con la nota viva de cada uno si tiene (F20, commit 8).
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late QuizSessionSummaryServiceImpl service;

  final now = DateTime(2026, 9, 25, 15);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'lib'),
      clock: () => now,
    );
    service = QuizSessionSummaryServiceImpl(
      database: db,
      topics: AnkiTopicResolverImpl(database: db),
    );
  });

  tearDown(() => db.close());

  Future<String> seedItem() async {
    final n = counter++;
    final id = 'item-$n';
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Elemento $n',
        source: Source(
          id: 'src-$n',
          kind: SourceKind.webPage,
          capturedAt: now,
          url: 'https://ejemplo.org/$n',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<String> seedLivingNote() async {
    final n = counter++;
    final id = 'nota-$n';
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Nota $n',
        source: Source(
          id: 'src-nota-$n',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      const KnowledgeNotesCompanion(
        noteKind: Value(NoteKind.living),
        maturity: Value(NoteMaturity.seed),
      ),
    );
    return id;
  }

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

  test('sin ninguna pregunta fallada, lista vacía', () async {
    expect(await service.summarize(const []), isEmpty);
  });

  test('agrupa por tema y cuenta cuántas preguntas de ese tema se '
      'fallaron', () async {
    final romaItem = await seedItem();
    final egiptoItem = await seedItem();
    await addTema('roma', 'Roma');
    await addTema('egipto', 'Egipto');
    await assignTema(romaItem, 'roma');
    await assignTema(egiptoItem, 'egipto');

    final result = await service.summarize([romaItem, romaItem, egiptoItem]);

    expect(result, hasLength(2));
    expect(result.first.topicLabel, 'Roma');
    expect(result.first.missedCount, 2);
    expect(result.last.topicLabel, 'Egipto');
    expect(result.last.missedCount, 1);
  });

  test('un elemento sin ningún tema no aporta a ningún grupo', () async {
    final itemId = await seedItem();

    final result = await service.summarize([itemId]);

    expect(result, isEmpty);
  });

  test('con una nota viva etiquetada con el tema, trae su elemento', () async {
    final itemId = await seedItem();
    final noteId = await seedLivingNote();
    await addTema('roma', 'Roma');
    await assignTema(itemId, 'roma');
    await assignTema(noteId, 'roma');

    final result = await service.summarize([itemId]);

    expect(result.single.livingNoteItemId, noteId);
  });

  test(
    'sin ninguna nota viva para el tema, queda sin acceso directo',
    () async {
      final itemId = await seedItem();
      await addTema('roma', 'Roma');
      await assignTema(itemId, 'roma');

      final result = await service.summarize([itemId]);

      expect(result.single.livingNoteItemId, isNull);
    },
  );
}
