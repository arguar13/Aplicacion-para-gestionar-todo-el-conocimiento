import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/silent_logger.dart';
import '../../../../support/transform_test_doubles.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repository;
  late InMemoryFileStore files;

  final now = DateTime(2026, 9, 11, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = InMemoryFileStore();
    repository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: files,
    );
  });

  tearDown(() => db.close());

  ProcessItemUseCase build(TransformerRegistry registry) => ProcessItemUseCase(
    registry: registry,
    repository: repository,
    logger: const SilentLogger(),
    telemetry: MockTelemetryService(),
    clock: () => now,
  );

  Future<KnowledgeItem> seedPending() async {
    final item = KnowledgeItem(
      id: 'item-1',
      title: 'Un artículo pendiente',
      source: Source(
        id: 'src-1',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/a',
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(item);
    return item;
  }

  Future<KnowledgeItem> reload(String id) async =>
      (await repository.findById(id)).getRight().toNullable()!;

  group('sin transformador que aplique', () {
    test(
      'lo marca listo para que no siga apareciendo como pendiente',
      () async {
        // Una nota escrita a mano ya está completa. Dejarla pendiente la haría
        // volver a la cola en cada arranque, para siempre.
        final item = await seedPending();

        await build(TransformerRegistry([FakeTransformer(accepts: false)]))(
          item.id,
        );

        expect((await reload(item.id)).processingState, ProcessingState.ready);
      },
    );
  });

  group('con transformador', () {
    test('guarda lo que trajo y lo deja listo', () async {
      final item = await seedPending();

      await build(TransformerRegistry([FakeTransformer()]))(item.id);
      final result = await reload(item.id);

      expect(result.processingState, ProcessingState.ready);
      expect(result.title, 'Título traído de la red');
      expect(result.searchableText, contains('El contenido que se trajo'));
    });

    test('publica "en curso" ANTES de empezar, para que la interfaz lo '
        'muestre mientras dura', () async {
      final item = await seedPending();
      ProcessingState? stateDuringWork;

      final transformer = FakeTransformer(
        onTransform: (_) async {
          stateDuringWork = (await reload(item.id)).processingState;
        },
      );

      await build(TransformerRegistry([transformer]))(item.id);

      expect(stateDuringWork, ProcessingState.processing);
    });
  });

  group('cuando falla', () {
    test('marca el fallo pero NO pierde nada de lo guardado', () async {
      // Un fallo de red no puede costarle al usuario el enlace que guardó.
      final item = await seedPending();

      final result = await build(
        TransformerRegistry([FakeTransformer(error: Exception('sin red'))]),
      )(item.id);

      expect(result.isLeft(), isTrue);

      final reloaded = await reload(item.id);
      expect(reloaded.processingState, ProcessingState.failed);
      expect(reloaded.title, 'Un artículo pendiente');
      expect(reloaded.source.url, 'https://ejemplo.org/a');
    });

    test('atrapa también los Error, no solo las Exception', () async {
      // Un parser ajeno puede lanzar un `Error`. Dejarlo escapar cortaría la
      // cola entera y dejaría el elemento atascado en "en curso" para
      // siempre.
      final item = await seedPending();

      final result = await build(
        TransformerRegistry([FakeTransformer(error: StateError('roto'))]),
      )(item.id);

      expect(result.isLeft(), isTrue);
      expect((await reload(item.id)).processingState, ProcessingState.failed);
    });
  });

  group('elementos que ya no están', () {
    test('procesar algo borrado devuelve un fallo, no revienta', () async {
      // Pasa: alguien lo elimina mientras esperaba su turno en la cola.
      final result = await build(TransformerRegistry([FakeTransformer()]))(
        'no-existe',
      );

      expect(result.isLeft(), isTrue);
    });
  });
}
