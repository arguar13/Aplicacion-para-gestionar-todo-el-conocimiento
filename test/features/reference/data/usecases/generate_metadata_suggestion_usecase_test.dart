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
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/reference/data/usecases/generate_metadata_suggestion_usecase.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, como `SuggestionRepositoryImpl`: lo que importa acá es
/// si de verdad llega a crear la fila o no, no que se haya llamado a algo.
void main() {
  late AppDatabase db;
  late InMemoryFileStore files;
  late SuggestionRepositoryImpl suggestions;
  late GenerateMetadataSuggestionUseCase generator;
  final now = DateTime(2026, 9, 20, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = InMemoryFileStore();
    final organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    suggestions = SuggestionRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      organize: organize,
      merge: null,
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    generator = GenerateMetadataSuggestionUseCase(
      files: files,
      suggestions: suggestions,
      telemetry: MockTelemetryService(),
    );
  });

  tearDown(() => db.close());

  /// Guarda el elemento de verdad —`createMetadataSuggestion` referencia su
  /// fila— y lo devuelve.
  Future<KnowledgeItem> seed(Source source) async {
    final built = KnowledgeItem(
      id: 'item-1',
      title: 'Un elemento',
      source: source,
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );
    await KnowledgeEntryWriter(db, clock: () => now).upsert(built);
    return built;
  }

  test('con algo que leer, crea la sugerencia pendiente', () async {
    final item = await seed(
      Source(
        id: 'src-1',
        kind: SourceKind.youtube,
        capturedAt: now,
        authorName: 'Canal de Prueba',
        publishedAt: DateTime(2020),
      ),
    );

    await generator.generate(item);

    final pending = await suggestions.watchPendingSuggestions('item-1').first;
    expect(pending, hasLength(1));
  });

  test('sin nada que leer —una nota—, no crea nada', () async {
    final item = await seed(
      Source(id: 'src-1', kind: SourceKind.manualNote, capturedAt: now),
    );

    await generator.generate(item);

    final pending = await suggestions.watchPendingSuggestions('item-1').first;
    expect(pending, isEmpty);
  });

  test('un canal sin nombre —nada que proponer—, no crea nada', () async {
    final item = await seed(
      Source(id: 'src-1', kind: SourceKind.youtube, capturedAt: now),
    );

    await generator.generate(item);

    final pending = await suggestions.watchPendingSuggestions('item-1').first;
    expect(pending, isEmpty);
  });
}
