import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/usecases/generate_property_suggestions_usecase.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

import '../../../../support/fake_chat_model_manager.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/fake_property_suggestion_service.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, con `LibraryRepositoryImpl` y
/// `OrganizeRepositoryImpl` reales: el vocabulario y el filtrado de lo ya
/// asignado dependen de datos de verdad, no de un doble.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late OrganizeRepositoryImpl organizeRepository;
  late SuggestionRepositoryImpl suggestionRepository;
  late FakePropertySuggestionService service;
  late FakeChatModelManager modelManager;
  late GeneratePropertySuggestionsUseCase generator;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    organizeRepository = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    suggestionRepository = SuggestionRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      organize: organizeRepository,
      merge: MergeDuplicateItemsUseCaseImpl(
        database: db,
        library: libraryRepository,
        ids: ids,
        clock: () => now,
        telemetry: MockTelemetryService(),
      ),
      ids: ids,
      clock: () => now,
    );
    service = FakePropertySuggestionService();
    modelManager = FakeChatModelManager(ready: true);
    generator = GeneratePropertySuggestionsUseCase(
      database: db,
      service: service,
      modelManager: modelManager,
      organize: organizeRepository,
      suggestions: suggestionRepository,
      telemetry: MockTelemetryService(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem({
    String title = 'Un elemento',
    String content = 'Contenido sobre Roma antigua.',
  }) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: content.isEmpty
          ? const []
          : [
              Rendition.text(
                id: 'rend-$n',
                itemId: 'item-$n',
                kind: RenditionKind.plainText,
                content: content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
    );

    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  test('con el modelo no listo, no genera ninguna sugerencia', () async {
    modelManager.ready = false;
    final item = await seedItem();
    await organizeRepository.getOrCreatePropertyDefinition('Región');
    service.drafts = [
      const PropertyDraft(
        definitionId: 'def',
        definitionName: 'Región',
        value: 'Roma',
      ),
    ];

    await generator.generate(item);

    final pending = await suggestionRepository
        .watchPendingSuggestions(item.id)
        .first;
    expect(pending, isEmpty);
    expect(service.requests, isEmpty);
  });

  test('un elemento sin contenido no llama al servicio', () async {
    final item = await seedItem(content: '');

    await generator.generate(item);

    expect(service.requests, isEmpty);
  });

  test('un draft con un valor que ya existe se persiste con '
      'isNewValue: false', () async {
    final definition = (await organizeRepository.getOrCreatePropertyDefinition(
      'Región',
    )).getRight().toNullable()!;
    await organizeRepository.assignProperty(
      itemId: (await seedItem()).id,
      definitionId: definition.id,
      value: 'Roma',
    );
    final item = await seedItem(title: 'Otro elemento');
    service.drafts = [
      PropertyDraft(
        definitionId: definition.id,
        definitionName: 'Región',
        value: 'Roma',
      ),
    ];

    await generator.generate(item);

    final pending = await suggestionRepository
        .watchPendingSuggestions(item.id)
        .first;
    expect(pending, hasLength(1));
    expect((pending.single as PropertySuggestion).isNewValue, isFalse);
  });

  test('un draft con un valor que no existe todavía se persiste con '
      'isNewValue: true', () async {
    final definition = (await organizeRepository.getOrCreatePropertyDefinition(
      'Región',
    )).getRight().toNullable()!;
    final item = await seedItem();
    service.drafts = [
      PropertyDraft(
        definitionId: definition.id,
        definitionName: 'Región',
        value: 'Roma',
      ),
    ];

    await generator.generate(item);

    final pending = await suggestionRepository
        .watchPendingSuggestions(item.id)
        .first;
    expect(pending, hasLength(1));
    expect((pending.single as PropertySuggestion).isNewValue, isTrue);
  });

  test(
    'el elemento ya tiene esa propiedad exacta asignada: no se genera',
    () async {
      final definition =
          (await organizeRepository.getOrCreatePropertyDefinition(
            'Región',
          )).getRight().toNullable()!;
      final seeded = await seedItem();
      await organizeRepository.assignProperty(
        itemId: seeded.id,
        definitionId: definition.id,
        value: 'Roma',
      );
      final item = (await libraryRepository.findById(
        seeded.id,
      )).getRight().toNullable()!;
      service.drafts = [
        PropertyDraft(
          definitionId: definition.id,
          definitionName: 'Región',
          value: 'Roma',
        ),
      ];

      await generator.generate(item);

      final pending = await suggestionRepository
          .watchPendingSuggestions(item.id)
          .first;
      expect(pending, isEmpty);
    },
  );

  test('solo categorías type: text entran al vocabulario', () async {
    // "Tema" y "Fecha del hecho" son categorías de sistema que toda base
    // nueva ya trae sembradas (ver seedSystemPropertyCategories):
    // "Tema" es type: text —entra—, "Fecha del hecho" es type: date
    // —tiene que quedar afuera—.
    await organizeRepository.getOrCreatePropertyDefinition('Región');
    final item = await seedItem();

    await generator.generate(item);

    expect(service.requests, hasLength(1));
    // "Tema" (sistema, text) + "Región" (text) — sin "Fecha del hecho".
    expect(service.requests.single.categoryCount, 2);
  });

  test('si el servicio lanza, generate() no lo deja escapar', () async {
    await organizeRepository.getOrCreatePropertyDefinition('Región');
    service.error = Exception('el modelo explotó');
    final item = await seedItem();

    await expectLater(generator.generate(item), completes);
  });
}
