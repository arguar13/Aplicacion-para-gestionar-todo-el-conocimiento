import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/attachments/domain/services/attachment_work.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/data/repositories/processing_state_repository_impl.dart';
import 'package:sinapsis/features/transform/data/repositories/text_anchor_relocator_impl.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

import '../../../../support/fake_duplicate_suggestion_generator.dart';
import '../../../../support/fake_metadata_suggestion_generator.dart';
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
    FakeDuplicateSuggestionGenerator? duplicateSuggestionGenerator,
    FakeMetadataSuggestionGenerator? metadataSuggestionGenerator,
    Duration longStallLimit = const Duration(minutes: 10),
    AttachmentWork? attachmentWork,
  }) => ProcessItemUseCase(
    attachmentWork: attachmentWork,
    longStallLimit: longStallLimit,
    registry: registry,
    repository: repository,
    processingStates: ProcessingStateRepositoryImpl(db),
    logger: const SilentLogger(),
    telemetry: MockTelemetryService(),
    clock: () => now,
    duplicateSuggestionGenerator:
        duplicateSuggestionGenerator ?? FakeDuplicateSuggestionGenerator(),
    metadataSuggestionGenerator:
        metadataSuggestionGenerator ?? FakeMetadataSuggestionGenerator(),
    anchorRelocator: TextAnchorRelocatorImpl(db),
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

  group('volver a extraer el texto (F22)', () {
    const oldText =
        'Te amo Dios. es tu maquillaje, es tu maquillaje, es tu maquillaje. '
        'Tu fidelidad sigue persiguiéndome.';
    const newText =
        '[0:00] Te amo Dios\n[0:14] Tu amor nunca me falla\n'
        '[0:28] Tu fidelidad sigue persiguiéndome';

    Future<KnowledgeItem> seedWithText() async {
      final item = KnowledgeItem(
        id: 'alabanza',
        title: 'Alabanza',
        notes: 'Mi nota.',
        source: Source(
          id: 'alabanza',
          kind: SourceKind.audio,
          capturedAt: now,
          originalFilePath: 'originales/alabanza.m4a',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'texto-viejo',
            itemId: 'alabanza',
            kind: RenditionKind.plainText,
            content: oldText,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );
      await repository.save(item);
      return item;
    }

    Future<void> highlight(String id, String excerpt, {String? note}) {
      final start = oldText.indexOf(excerpt);
      return db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              id: id,
              renditionId: 'texto-viejo',
              startOffset: start,
              endOffset: start + excerpt.length,
              excerpt: excerpt,
              note: Value(note),
              createdAt: now,
            ),
          );
    }

    Future<void> requestReextraction(String itemId) async {
      final states = ProcessingStateRepositoryImpl(db);
      await states.save(
        itemId,
        ProcessingCheckpointKind.reextract,
        position: 0,
        content: '',
      );
      await states.requeue(itemId);
    }

    test(
      'sin pedirlo, un elemento con texto no se vuelve a transformar',
      () async {
        final item = await seedWithText();
        final transformer = _LikeARealOne(newText);

        await build(TransformerRegistry([transformer]))(item.id);

        expect(transformer.calls, 0);
        expect(primaryTextOf(await reload(item.id))!.content, oldText);
      },
    );

    test('pedido, el texto nuevo toma el lugar del viejo —la misma forma—, '
        'y los subrayados van a su lugar en el texto nuevo', () async {
      final item = await seedWithText();
      await highlight('h1', 'Tu fidelidad sigue persiguiéndome', note: 'Clave');
      await requestReextraction(item.id);

      await build(TransformerRegistry([_LikeARealOne(newText)]))(item.id);

      final after = await reload(item.id);
      final text = primaryTextOf(after)!;
      expect(text.id, 'texto-viejo');
      expect(text.content, newText);
      expect(after.processingState, ProcessingState.ready);

      final moved = await db.select(db.highlights).getSingle();
      expect(
        newText.substring(moved.startOffset, moved.endOffset),
        'Tu fidelidad sigue persiguiéndome',
      );
      expect(moved.note, 'Clave');
      // Terminado bien, la marca se va: no se vuelve a extraer otra vez.
      expect(
        await ProcessingStateRepositoryImpl(
          db,
        ).load(item.id, ProcessingCheckpointKind.reextract),
        isEmpty,
      );
    });

    test('un subrayado que ya no está en el texto nuevo no se pierde: queda '
        'en la nota del elemento, con su nota', () async {
      final item = await seedWithText();
      await highlight('h1', 'es tu maquillaje', note: 'Esto no se canta');
      await requestReextraction(item.id);

      await build(TransformerRegistry([_LikeARealOne(newText)]))(item.id);

      final after = await reload(item.id);
      expect(await db.select(db.highlights).get(), isEmpty);
      expect(
        after.notes,
        'Mi nota.\n\n'
        'Subrayados que no se encontraron en el texto nuevo:\n\n'
        '> es tu maquillaje\n\nEsto no se canta',
      );
    });

    test('si el motor no trae texto, queda el de antes: volver a extraer '
        'nunca deja menos', () async {
      final item = await seedWithText();
      await highlight('h1', 'Te amo Dios');
      await requestReextraction(item.id);

      await build(TransformerRegistry([_LikeARealOne('   ')]))(item.id);

      final after = await reload(item.id);
      expect(primaryTextOf(after)!.content, oldText);
      expect(await db.select(db.highlights).get(), hasLength(1));
    });
  });

  group('«solo el libro» (F30, decisión 68)', () {
    /// Un libro cuyo texto se soltó a propósito: el archivo sin formas, con
    /// la marca. Como lo deja la papelera del contenido.
    Future<KnowledgeItem> seedOnlyFile() async {
      final item = KnowledgeItem(
        id: 'libro',
        title: 'Historia de Roma',
        source: Source(
          id: 'libro',
          kind: SourceKind.document,
          capturedAt: now,
          originalFilePath: 'originales/libro/roma.pdf',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(item);
      await (db.update(db.knowledgeSources)
            ..where((s) => s.itemId.equals(item.id)))
          .write(const KnowledgeSourcesCompanion(onlyFile: Value(true)));
      return reload(item.id);
    }

    test('la cola no le vuelve a extraer el texto sola, aunque no tenga '
        'ninguno', () async {
      final item = await seedOnlyFile();
      expect(item.source.onlyFile, isTrue);
      final transformer = _LikeARealOne('El texto de Roma.');

      await ProcessingStateRepositoryImpl(db).requeue(item.id);
      await build(TransformerRegistry([transformer]))(item.id);

      expect(transformer.calls, 0);
      final after = await reload(item.id);
      expect(after.renditions, isEmpty);
      expect(after.source.onlyFile, isTrue);
      expect(after.processingState, ProcessingState.ready);
    });

    test('«Volver a extraer», pedido a mano, sí: trae el texto y saca la '
        'marca', () async {
      final item = await seedOnlyFile();
      final states = ProcessingStateRepositoryImpl(db);
      await states.save(
        item.id,
        ProcessingCheckpointKind.reextract,
        position: 0,
        content: '',
      );
      await states.requeue(item.id);
      final transformer = _LikeARealOne('El texto de Roma.');

      await build(TransformerRegistry([transformer]))(item.id);

      expect(transformer.calls, 1);
      final after = await reload(item.id);
      expect(primaryTextOf(after)!.content, 'El texto de Roma.');
      expect(after.source.onlyFile, isFalse);
    });

    test('y si el motor no trae texto, la marca queda', () async {
      final item = await seedOnlyFile();
      final states = ProcessingStateRepositoryImpl(db);
      await states.save(
        item.id,
        ProcessingCheckpointKind.reextract,
        position: 0,
        content: '',
      );
      await states.requeue(item.id);

      await build(TransformerRegistry([_LikeARealOne('  ')]))(item.id);

      final after = await reload(item.id);
      expect(after.renditions, isEmpty);
      expect(after.source.onlyFile, isTrue);
    });
  });

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

    test('un generador cuyo Future nunca completa no bloquea _process(): '
        'es fire-and-forget de verdad', () async {
      final item = await seedPending();
      final generator = FakeDuplicateSuggestionGenerator()
        ..hang = Completer<void>();

      final result = await build(
        TransformerRegistry([FakeTransformer()]),
        duplicateSuggestionGenerator: generator,
      )(item.id);

      expect(result.isRight(), isTrue);
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

    test('corre en paralelo con el de duplicados: ninguno espera al '
        'otro', () async {
      final item = await seedPending();
      final duplicateGenerator = FakeDuplicateSuggestionGenerator()
        ..hang = Completer<void>();
      final metadataGenerator = FakeMetadataSuggestionGenerator();

      final result = await build(
        TransformerRegistry([FakeTransformer()]),
        duplicateSuggestionGenerator: duplicateGenerator,
        metadataSuggestionGenerator: metadataGenerator,
      )(item.id);

      expect(result.isRight(), isTrue);
      expect(metadataGenerator.calls, [item.id]);
    });
  });

  group('el «Contenido» bajado de una página (F30)', () {
    test(
      'corre en la misma vuelta, después del artículo ya guardado',
      () async {
        final item = await seedPending();
        final work = _FakeAttachmentWork(pending: 1);
        String? textWhenWorkStarted;
        work.onTransform = (_) async {
          textWhenWorkStarted = (await reload(
            item.id,
          )).renditions.firstOrNull?.searchableText;
        };

        final result = await build(
          TransformerRegistry([FakeTransformer()]),
          attachmentWork: work,
        )(item.id);

        expect(result.isRight(), isTrue);
        expect(work.calls, 1);
        // El artículo ya se podía leer mientras bajaba lo demás.
        expect(textWhenWorkStarted, 'El contenido que se trajo.');
        expect((await reload(item.id)).processingState, ProcessingState.ready);
      },
    );

    test('solo, cuando no hay otro trabajo («Bajar el resto»)', () async {
      final item = await seedPending();
      final work = _FakeAttachmentWork(pending: 1);

      await build(
        TransformerRegistry([FakeTransformer(accepts: false)]),
        attachmentWork: work,
      )(item.id);

      expect(work.calls, 1);
    });

    test('sin nada que bajar, no corre', () async {
      final item = await seedPending();
      final work = _FakeAttachmentWork(pending: 0);

      await build(
        TransformerRegistry([FakeTransformer()]),
        attachmentWork: work,
      )(item.id);

      expect(work.calls, 0);
    });

    test(
      'si no se puede saber si queda algo, el elemento sigue igual',
      () async {
        final item = await seedPending();
        final work = _FakeAttachmentWork(pending: 1)
          ..hasWorkError = StateError('base rota');

        final result = await build(
          TransformerRegistry([FakeTransformer()]),
          attachmentWork: work,
        )(item.id);

        expect(result.isRight(), isTrue);
        expect(work.calls, 0);
        expect((await reload(item.id)).processingState, ProcessingState.ready);
      },
    );
  });

  group('un enlace que resultó ser un archivo (F30)', () {
    test('en la misma vuelta le toca al transformador de esa clase', () async {
      final item = await seedPending();
      final asPage = _ByKind(SourceKind.webPage, (item) {
        // Lo que hace `WebArticleTransformer` con un enlace a un PDF: el
        // elemento pasa a ser un documento, sin texto todavía.
        return item.copyWith(
          source: item.source.copyWith(
            kind: SourceKind.document,
            originalFilePath: 'originales/src-1/informe.pdf',
          ),
        );
      });
      final asDocument = _ByKind(
        SourceKind.document,
        (item) => item.copyWith(
          renditions: [
            Rendition.text(
              id: 'texto-pdf',
              itemId: item.id,
              kind: RenditionKind.plainText,
              content: 'El texto del informe.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

      final result = await build(TransformerRegistry([asPage, asDocument]))(
        item.id,
      );

      expect(result.isRight(), isTrue);
      expect(asPage.calls, 1);
      expect(asDocument.calls, 1);
      final saved = await reload(item.id);
      expect(saved.source.kind, SourceKind.document);
      expect(saved.source.originalFilePath, 'originales/src-1/informe.pdf');
      expect(saved.renditions.single.id, 'texto-pdf');
      expect(saved.processingState, ProcessingState.ready);
    });

    test('si nadie sabe qué hacer con la clase nueva, queda listo', () async {
      final item = await seedPending();
      final asPage = _ByKind(
        SourceKind.webPage,
        (item) => item.copyWith(
          source: item.source.copyWith(kind: SourceKind.document),
        ),
      );

      final result = await build(TransformerRegistry([asPage]))(item.id);

      expect(result.isRight(), isTrue);
      expect(asPage.calls, 1);
      expect((await reload(item.id)).source.kind, SourceKind.document);
    });
  });
}

/// Acepta los elementos de [kind] sin texto, y los transforma con [enrich].
class _ByKind implements Transformer {
  _ByKind(this.kind, this.enrich);

  final SourceKind kind;
  final KnowledgeItem Function(KnowledgeItem) enrich;
  int calls = 0;

  @override
  Duration? get timeLimit => null;

  @override
  bool canTransform(KnowledgeItem item) =>
      item.source.kind == kind && item.renditions.isEmpty;

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    calls++;
    return enrich(item);
  }
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

/// Como un transformador de verdad: solo acepta un elemento sin texto, y
/// devuelve una forma de texto nueva, con su propio identificador.
class _LikeARealOne implements Transformer {
  _LikeARealOne(this.text);

  final String text;
  int calls = 0;

  @override
  Duration? get timeLimit => null;

  @override
  bool canTransform(KnowledgeItem item) => item.renditions.isEmpty;

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    calls++;
    return item.copyWith(
      renditions: [
        Rendition.text(
          id: 'texto-nuevo-$calls',
          itemId: item.id,
          kind: RenditionKind.plainText,
          content: text,
          isPrimary: true,
          createdAt: DateTime(2026, 9, 30),
        ),
      ],
    );
  }
}

/// Trabajo del «Contenido» de mentira: dice que queda [pending] por hacer y,
/// cuando corre, lo hace.
class _FakeAttachmentWork implements AttachmentWork {
  _FakeAttachmentWork({required this.pending});

  int pending;
  int calls = 0;
  Error? hasWorkError;
  Future<void> Function(KnowledgeItem item)? onTransform;

  @override
  Duration? get timeLimit => null;

  @override
  bool canTransform(KnowledgeItem item) => true;

  @override
  Future<bool> hasWork(String itemId) async {
    if (hasWorkError != null) throw hasWorkError!;
    return pending > 0;
  }

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    calls++;
    await onTransform?.call(item);
    pending = 0;
    return item;
  }
}
