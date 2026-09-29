import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/data/repositories/processing_state_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';

import '../../../../support/fake_duplicate_suggestion_generator.dart';
import '../../../../support/fake_metadata_suggestion_generator.dart';
import '../../../../support/fake_property_suggestion_generator.dart';
import '../../../../support/fake_relation_suggestion_generator.dart';
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

  ProcessItemUseCase build(
    TransformerRegistry registry, {
    FakePropertySuggestionGenerator? suggestionGenerator,
    FakeRelationSuggestionGenerator? relationSuggestionGenerator,
    FakeDuplicateSuggestionGenerator? duplicateSuggestionGenerator,
    FakeMetadataSuggestionGenerator? metadataSuggestionGenerator,
    Duration longStallLimit = const Duration(minutes: 10),
  }) => ProcessItemUseCase(
    longStallLimit: longStallLimit,
    registry: registry,
    repository: repository,
    processingStates: ProcessingStateRepositoryImpl(db),
    logger: const SilentLogger(),
    telemetry: MockTelemetryService(),
    clock: () => now,
    suggestionGenerator:
        suggestionGenerator ?? FakePropertySuggestionGenerator(),
    relationSuggestionGenerator:
        relationSuggestionGenerator ?? FakeRelationSuggestionGenerator(),
    duplicateSuggestionGenerator:
        duplicateSuggestionGenerator ?? FakeDuplicateSuggestionGenerator(),
    metadataSuggestionGenerator:
        metadataSuggestionGenerator ?? FakeMetadataSuggestionGenerator(),
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
        onTransform: (_, _) async {
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

  group('estado del procesamiento: intentos y motivo', () {
    Future<KnowledgeSourceRow> sourceOf(String id) => (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(id))).getSingle();

    test('un fallo guarda su motivo real, no un "no se pudo" '
        'genérico', () async {
      // "Himno de Alabanza" (F21): falló porque faltaba el modelo de
      // transcripción, y la app solo decía "No se pudo sacar el texto".
      final item = await seedPending();

      await build(
        TransformerRegistry([
          FakeTransformer(error: const WhisperModelNotReadyException()),
        ]),
      )(item.id);

      final row = await sourceOf(item.id);
      expect(row.processingError, 'transcriptionModelMissing');
      expect(row.processingAttempts, 1);
    });

    test('un trabajo corto que no responde vence su tope y queda fallido '
        'por tiempo', () async {
      final item = await seedPending();

      final result = await build(
        TransformerRegistry([
          FakeTransformer(
            onTransform: (_, _) => Completer<void>().future,
            timeLimit: const Duration(milliseconds: 50),
          ),
        ]),
      )(item.id);

      expect(result.isLeft(), isTrue);
      final row = await sourceOf(item.id);
      expect(row.processingStatus, SourceProcessingStatus.failed);
      expect(row.processingError, 'timedOut');
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('un éxito deja sin motivo y sin intentos', () async {
      final item = await seedPending();
      await build(
        TransformerRegistry([FakeTransformer(error: Exception('sin red'))]),
      )(item.id);

      await build(TransformerRegistry([FakeTransformer()]))(item.id);

      final row = await sourceOf(item.id);
      expect(row.processingError, isNull);
      expect(row.processingAttempts, 0);
    });

    test('al fallar NO pisa lo que el usuario cambió mientras se '
        'procesaba', () async {
      // Antes el fallo se registraba guardando la foto del elemento tomada al
      // empezar: un título o una nota cambiados en el medio se perdían.
      final item = await seedPending();

      await build(
        TransformerRegistry([
          FakeTransformer(
            onTransform: (_, _) async {
              await repository.save(
                (await reload(item.id)).copyWith(title: 'Lo renombré yo'),
              );
            },
            error: Exception('sin red'),
          ),
        ]),
      )(item.id);

      final reloaded = await reload(item.id);
      expect(reloaded.processingState, ProcessingState.failed);
      expect(reloaded.title, 'Lo renombré yo');
    });
  });

  group('mientras se procesaba, el usuario siguió usando el elemento', () {
    Future<KnowledgeSourceRow> sourceOf(String id) => (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(id))).getSingle();

    test('lo que cambió se conserva, y lo que trajo el transformador '
        'entra igual', () async {
      // Antes el resultado se guardaba sobre la foto tomada al empezar: una
      // nota o un título cambiados en el medio se perdían.
      final item = await seedPending();

      await build(
        TransformerRegistry([
          FakeTransformer(
            onTransform: (_, _) async {
              await repository.save(
                (await reload(item.id)).copyWith(notes: 'Para el jueves'),
              );
            },
          ),
        ]),
      )(item.id);

      final result = await reload(item.id);
      expect(result.processingState, ProcessingState.ready);
      expect(result.notes, 'Para el jueves');
      expect(result.title, 'Título traído de la red');
      expect(result.searchableText, contains('El contenido que se trajo'));
    });

    test('si le cambió el título, gana el suyo', () async {
      final item = await seedPending();

      await build(
        TransformerRegistry([
          FakeTransformer(
            onTransform: (_, _) async {
              await repository.save(
                (await reload(item.id)).copyWith(title: 'Mi título'),
              );
            },
          ),
        ]),
      )(item.id);

      expect((await reload(item.id)).title, 'Mi título');
    });

    test('si lo mandó a la papelera, el resultado no se guarda y queda en '
        'espera por si lo restaura', () async {
      final item = await seedPending();

      final result = await build(
        TransformerRegistry([
          FakeTransformer(onTransform: (_, _) => repository.delete(item.id)),
        ]),
      )(item.id);

      expect(result.isLeft(), isTrue);
      final row = await sourceOf(item.id);
      expect(row.processingStatus, SourceProcessingStatus.pending);
      // Un elemento en la papelera no se devuelve al buscarlo: se mira la
      // tabla de formas directamente.
      final renditions = await (db.select(
        db.renditions,
      )..where((r) => r.itemId.equals(item.id))).get();
      expect(renditions, isEmpty);
    });

    test('con la señal de cancelación, lo suelta en el acto sin esperar al '
        'transformador', () async {
      final item = await seedPending();
      final cancellation = CancellationSignal();
      final started = Completer<void>();

      final processing = build(
        TransformerRegistry([
          FakeTransformer(
            onTransform: (_, _) {
              started.complete();
              // Un pedido a la red que no vuelve nunca.
              return Completer<void>().future;
            },
          ),
        ]),
      ).process(item.id, context: CancellableTransformContext(cancellation));

      await started.future;
      cancellation.cancel();

      expect((await processing).isLeft(), isTrue);
      expect(
        (await sourceOf(item.id)).processingStatus,
        SourceProcessingStatus.pending,
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('en la papelera antes de su turno: ni se empieza', () async {
      final item = await seedPending();
      await repository.delete(item.id);
      final transformer = FakeTransformer();

      final result = await build(TransformerRegistry([transformer]))(item.id);

      expect(result.isLeft(), isTrue);
      expect(transformer.transformed, isEmpty);
    });
  });

  group('el vigilante del trabajo largo', () {
    Future<KnowledgeSourceRow> sourceOf(String id) => (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(id))).getSingle();

    test('en el carril largo no rige el tope fijo: tarda lo que tarda '
        'mientras informe avance', () async {
      // Una transcripción de cuatro horas no puede vencer a los tres minutos.
      final item = await seedPending();

      final result = await build(
        TransformerRegistry([
          FakeTransformer(
            timeLimit: const Duration(milliseconds: 50),
            onTransform: (_, context) async {
              await context.enterLongLane();
              for (var part = 1; part <= 6; part++) {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                context.reportProgress(part, 6);
              }
            },
          ),
        ]),
        longStallLimit: const Duration(milliseconds: 150),
      )(item.id);

      expect(result.isRight(), isTrue);
      expect((await reload(item.id)).processingState, ProcessingState.ready);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('en el carril largo, si deja de avanzar, vence por tiempo', () async {
      final item = await seedPending();

      final result = await build(
        TransformerRegistry([
          FakeTransformer(
            onTransform: (_, context) async {
              await context.enterLongLane();
              context.reportProgress(1, 100);
              await Completer<void>().future;
            },
          ),
        ]),
        longStallLimit: const Duration(milliseconds: 80),
      )(item.id);

      expect(result.isLeft(), isTrue);
      expect((await sourceOf(item.id)).processingError, 'timedOut');
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('esperar turno para entrar al carril largo no cuenta para ningún '
        'tope', () async {
      // Detrás de una transcripción larga, esperar es lo normal.
      final item = await seedPending();

      final result =
          await build(
            TransformerRegistry([
              FakeTransformer(
                timeLimit: const Duration(milliseconds: 50),
                onTransform: (_, context) async {
                  await context.enterLongLane();
                  context.reportProgress(1, 1);
                },
              ),
            ]),
            longStallLimit: const Duration(milliseconds: 50),
          ).process(
            item.id,
            context: _SlowLaneContext(const Duration(milliseconds: 200)),
          );

      expect(result.isRight(), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
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

  group('genera sugerencias de propiedades al terminar', () {
    test('sin transformador que aplique, llama al generador con el '
        'elemento guardado', () async {
      final item = await seedPending();
      final generator = FakePropertySuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer(accepts: false)]),
        suggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, [item.id]);
    });

    test('con transformador, llama al generador con el elemento ya '
        'transformado', () async {
      final item = await seedPending();
      final generator = FakePropertySuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer()]),
        suggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, [item.id]);
    });

    test('al terminar en failed, no llama al generador', () async {
      final item = await seedPending();
      final generator = FakePropertySuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer(error: Exception('sin red'))]),
        suggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, isEmpty);
    });

    test(
      'un generador que lanza no le cuesta el resultado a _process()',
      () async {
        final item = await seedPending();
        final generator = FakePropertySuggestionGenerator(
          error: Exception('el modelo explotó'),
        );

        final result = await build(
          TransformerRegistry([FakeTransformer()]),
          suggestionGenerator: generator,
        )(item.id);

        expect(result.isRight(), isTrue);
      },
    );

    test('un generador cuyo Future nunca completa no bloquea _process(): '
        'es fire-and-forget de verdad', () async {
      final item = await seedPending();
      final generator = FakePropertySuggestionGenerator()
        ..hang = Completer<void>();

      final result = await build(
        TransformerRegistry([FakeTransformer()]),
        suggestionGenerator: generator,
      )(item.id);

      expect(result.isRight(), isTrue);
    });
  });

  group('genera sugerencias de relación al terminar', () {
    test('con transformador, llama al generador con el elemento ya '
        'transformado', () async {
      final item = await seedPending();
      final generator = FakeRelationSuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer()]),
        relationSuggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, [item.id]);
    });

    test('al terminar en failed, no llama al generador', () async {
      final item = await seedPending();
      final generator = FakeRelationSuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer(error: Exception('sin red'))]),
        relationSuggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, isEmpty);
    });

    test(
      'un generador que lanza no le cuesta el resultado a _process()',
      () async {
        final item = await seedPending();
        final generator = FakeRelationSuggestionGenerator(
          error: Exception('el modelo explotó'),
        );

        final result = await build(
          TransformerRegistry([FakeTransformer()]),
          relationSuggestionGenerator: generator,
        )(item.id);

        expect(result.isRight(), isTrue);
      },
    );

    test('corre en paralelo con el de propiedades: ninguno espera al '
        'otro', () async {
      final item = await seedPending();
      final propertyGenerator = FakePropertySuggestionGenerator()
        ..hang = Completer<void>();
      final relationGenerator = FakeRelationSuggestionGenerator();

      final result = await build(
        TransformerRegistry([FakeTransformer()]),
        suggestionGenerator: propertyGenerator,
        relationSuggestionGenerator: relationGenerator,
      )(item.id);

      expect(result.isRight(), isTrue);
      expect(relationGenerator.calls, [item.id]);
    });
  });

  group('genera sugerencias de duplicado al terminar', () {
    test('con transformador, llama al generador con el elemento ya '
        'transformado', () async {
      final item = await seedPending();
      final generator = FakeDuplicateSuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer()]),
        duplicateSuggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, [item.id]);
    });

    test('al terminar en failed, no llama al generador', () async {
      final item = await seedPending();
      final generator = FakeDuplicateSuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer(error: Exception('sin red'))]),
        duplicateSuggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, isEmpty);
    });

    test(
      'un generador que lanza no le cuesta el resultado a _process()',
      () async {
        final item = await seedPending();
        final generator = FakeDuplicateSuggestionGenerator(
          error: Exception('algo falló'),
        );

        final result = await build(
          TransformerRegistry([FakeTransformer()]),
          duplicateSuggestionGenerator: generator,
        )(item.id);

        expect(result.isRight(), isTrue);
      },
    );

    test('corre en paralelo con los otros dos: ninguno espera a los '
        'demás', () async {
      final item = await seedPending();
      final propertyGenerator = FakePropertySuggestionGenerator()
        ..hang = Completer<void>();
      final duplicateGenerator = FakeDuplicateSuggestionGenerator();

      final result = await build(
        TransformerRegistry([FakeTransformer()]),
        suggestionGenerator: propertyGenerator,
        duplicateSuggestionGenerator: duplicateGenerator,
      )(item.id);

      expect(result.isRight(), isTrue);
      expect(duplicateGenerator.calls, [item.id]);
    });
  });

  group('genera la sugerencia de referencia al terminar (F15)', () {
    test('con transformador, llama al generador con el elemento ya '
        'transformado', () async {
      final item = await seedPending();
      final generator = FakeMetadataSuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer()]),
        metadataSuggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, [item.id]);
    });

    test('al terminar en failed, no llama al generador', () async {
      final item = await seedPending();
      final generator = FakeMetadataSuggestionGenerator();

      await build(
        TransformerRegistry([FakeTransformer(error: Exception('sin red'))]),
        metadataSuggestionGenerator: generator,
      )(item.id);

      expect(generator.calls, isEmpty);
    });

    test(
      'un generador que lanza no le cuesta el resultado a _process()',
      () async {
        final item = await seedPending();
        final generator = FakeMetadataSuggestionGenerator(
          error: Exception('no se pudo leer el archivo'),
        );

        final result = await build(
          TransformerRegistry([FakeTransformer()]),
          metadataSuggestionGenerator: generator,
        )(item.id);

        expect(result.isRight(), isTrue);
      },
    );

    test('corre en paralelo con los otros tres: ninguno espera a los '
        'demás', () async {
      final item = await seedPending();
      final propertyGenerator = FakePropertySuggestionGenerator()
        ..hang = Completer<void>();
      final metadataGenerator = FakeMetadataSuggestionGenerator();

      final result = await build(
        TransformerRegistry([FakeTransformer()]),
        suggestionGenerator: propertyGenerator,
        metadataSuggestionGenerator: metadataGenerator,
      )(item.id);

      expect(result.isRight(), isTrue);
      expect(metadataGenerator.calls, [item.id]);
    });
  });
}

/// Una cola cuyo carril largo está ocupado un rato: entrar tarda [wait].
class _SlowLaneContext implements TransformContext {
  _SlowLaneContext(this.wait);

  final Duration wait;

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;

  @override
  void throwIfCancelled() {}

  @override
  Future<void> enterLongLane() => Future<void>.delayed(wait);

  @override
  void reportProgress(int done, int total) {}
}
