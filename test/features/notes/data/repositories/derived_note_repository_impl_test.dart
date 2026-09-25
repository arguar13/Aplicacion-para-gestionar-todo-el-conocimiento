import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notes/data/repositories/derived_note_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La marca de procedencia de una nota generada (F16, D3), contra SQLite
/// real.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late KnowledgeEntryWriter writer;
  late DerivedNoteRepositoryImpl repository;

  final now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    writer = KnowledgeEntryWriter(db, clock: () => now);
    repository = DerivedNoteRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<void> seedNote(String id) => library
      .save(
        KnowledgeItem(
          id: id,
          title: 'Nota $id',
          source: Source(
            id: 'src-$id',
            kind: SourceKind.manualNote,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        ),
      )
      .then((_) {});

  test('una nota que no se generó no tiene marca', () async {
    await seedNote('nota');

    expect(await repository.watchMark('nota').first, isNull);
  });

  test('una nota generada trae su modelo, fecha y si ya se editó', () async {
    await seedNote('nota');
    await writer.markGenerated('nota', model: 'gemma-3n', at: now);

    final mark = await repository.watchMark('nota').first;

    expect(mark, isNotNull);
    expect(mark!.model, 'gemma-3n');
    expect(mark.generatedAt, now);
    expect(mark.edited, isFalse);
  });

  test('marcar como editada se refleja en la marca', () async {
    await seedNote('nota');
    await writer.markGenerated('nota', model: 'gemma-3n', at: now);

    await repository.markEdited('nota');

    final mark = await repository.watchMark('nota').first;
    expect(mark!.edited, isTrue);
  });

  test(
    'marcar como editada una nota que no es un derivado no hace nada',
    () async {
      await seedNote('nota');

      await repository.markEdited('nota');

      expect(await repository.watchMark('nota').first, isNull);
    },
  );
}
