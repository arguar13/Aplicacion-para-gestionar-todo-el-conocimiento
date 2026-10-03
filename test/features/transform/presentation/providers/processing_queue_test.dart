import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/data/repositories/processing_state_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

import '../../../../support/fake_duplicate_suggestion_generator.dart';
import '../../../../support/fake_metadata_suggestion_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/silent_logger.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Un transformador con freno de mano.
///
/// Lo que se prueba acá es el **orden** en que la cola hace las cosas, y el
/// orden no se puede comprobar esperando a que termine todo: para entonces ya
/// pasó. Con el freno puesto, cada elemento avisa cuando empieza y se queda
/// quieto hasta que el test lo suelta, así que se puede mirar la cola a mitad
/// de camino sin depender de cuánto tarde nada.
class _ScriptedTransformer implements Transformer {
  _ScriptedTransformer({
    this.gated = false,
    this.failOn = const <String>{},
    this.hangOn = const <String>{},
    this.longOn = const <String>{},
    this.progressOf = const {},
    this.timeLimit,
  });

  /// Identificadores que no terminan nunca: un pedido a la red que quedó
  /// colgado.
  final Set<String> hangOn;

  @override
  final Duration? timeLimit;

  /// Con el freno puesto, `transform` no termina hasta que se llame a
  /// [release].
  final bool gated;

  /// Identificadores que lanzan en vez de devolver contenido.
  final Set<String> failOn;

  /// En qué orden se procesó cada cosa.
  final processed = <String>[];

  final _started = <String, Completer<void>>{};
  final _released = <String, Completer<void>>{};

  Completer<void> _signal(Map<String, Completer<void>> signals, String id) =>
      signals.putIfAbsent(id, Completer<void>.new);

  /// Espera a que la cola haya empezado con [itemId].
  Future<void> started(String itemId) => _signal(_started, itemId).future;

  /// Deja que [itemId] termine.
  void release(String itemId) {
    final signal = _signal(_released, itemId);
    if (!signal.isCompleted) signal.complete();
  }

  @override
  bool canTransform(KnowledgeItem item) => true;

  /// Identificadores que pasan al carril largo antes de su freno —como una
  /// transcripción—, informando [progressOf] al entrar.
  final Set<String> longOn;

  /// Lo que informa cada uno de [longOn] al entrar al carril largo.
  final Map<String, (int, int)> progressOf;

  final _enteredLong = <String, Completer<void>>{};

  /// Espera a que [itemId] haya entrado al carril largo.
  Future<void> enteredLong(String itemId) =>
      _signal(_enteredLong, itemId).future;

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    processed.add(item.id);

    final startSignal = _signal(_started, item.id);
    if (!startSignal.isCompleted) startSignal.complete();

    if (longOn.contains(item.id)) {
      await context.enterLongLane();
      final progress = progressOf[item.id];
      if (progress != null) context.reportProgress(progress.$1, progress.$2);
      _signal(_enteredLong, item.id).complete();
    }

    if (gated) await _signal(_released, item.id).future;
    if (hangOn.contains(item.id)) await Completer<void>().future;
    if (failOn.contains(item.id)) throw Exception('se cayó ${item.id}');

    return item.copyWith(
      renditions: [
        Rendition.text(
          id: '${item.id}-rend',
          itemId: item.id,
          kind: RenditionKind.markdown,
          content: 'Contenido de ${item.id}.',
          isPrimary: true,
          createdAt: item.createdAt,
        ),
      ],
    );
  }
}

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

  ProcessItemUseCase buildUseCase(Transformer transformer) =>
      ProcessItemUseCase(
        registry: TransformerRegistry([transformer]),
        repository: repository,
        processingStates: ProcessingStateRepositoryImpl(db),
        logger: const SilentLogger(),
        telemetry: MockTelemetryService(),
        clock: () => now,
        duplicateSuggestionGenerator: FakeDuplicateSuggestionGenerator(),
        metadataSuggestionGenerator: FakeMetadataSuggestionGenerator(),
      );

  ProcessingQueueNotifier buildQueue(
    Transformer transformer, {
    ProcessItemUseCase Function()? resolveProcessItem,
    LongWorkKeeper? longWork,
    void Function(KnowledgeItem processed)? onProcessed,
  }) {
    final useCase = buildUseCase(transformer);
    final queue = ProcessingQueueNotifier(
      processItem: resolveProcessItem ?? () => useCase,
      processingStates: () => ProcessingStateRepositoryImpl(db),
      logger: const SilentLogger(),
      longWork: longWork == null ? null : () => longWork,
      onProcessed: onProcessed,
    );
    // Tolerante a propósito: una de las pruebas descarta la cola a mano, y
    // descartar dos veces revienta.
    addTearDown(() {
      if (queue.mounted) queue.dispose();
    });
    return queue;
  }

  Future<void> seed(
    String id, {
    ProcessingState state = ProcessingState.pending,
  }) async {
    final item = KnowledgeItem(
      id: id,
      title: 'Elemento $id',
      source: Source(
        id: 'src-$id',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$id',
      ),
      processingState: state,
      createdAt: now,
      updatedAt: now,
    );

    final result = await repository.save(item);
    result.match(
      (failure) => throw StateError('no se pudo sembrar: $failure'),
      (_) {},
    );
  }

  Future<ProcessingState> stateOf(String id) async =>
      (await repository.findById(id)).getRight().toNullable()!.processingState;

  /// Espera a que la cola vuelva a reposo.
  ///
  /// Se escucha el estado en vez de dormir un rato: un `await` de milisegundos
  /// convierte cualquier prueba en una apuesta, y la que se pierde de vez en
  /// cuando es peor que la que no existe.
  Future<void> whenIdle(ProcessingQueueNotifier queue) {
    if (queue.state.isIdle) return Future<void>.value();

    final done = Completer<void>();
    final remove = queue.addListener((state) {
      if (state.isIdle && !done.isCompleted) done.complete();
    }, fireImmediately: false);

    return done.future.whenComplete(remove);
  }

  group('de a uno', () {
    test('no empieza el segundo hasta que termina el primero', () async {
      // Diez enlaces capturados de golpe no pueden ser diez descargas a la
      // vez: es una ráfaga contra los mismos servidores y diez trabajos
      // peleando por la memoria de un teléfono.
      await seed('a');
      await seed('b');

      final transformer = _ScriptedTransformer(gated: true);
      final queue = buildQueue(transformer)
        ..enqueue('a')
        ..enqueue('b');
      await transformer.started('a');

      expect(transformer.processed, ['a']);
      expect(await stateOf('b'), ProcessingState.pending);

      transformer.release('a');
      await transformer.started('b');

      expect(transformer.processed, ['a', 'b']);

      transformer.release('b');
      await whenIdle(queue);
      expect(await stateOf('b'), ProcessingState.ready);
    });

    test('respeta el orden en que se encolaron', () async {
      await seed('primero');
      await seed('segundo');
      await seed('tercero');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer)
        ..enqueue('primero')
        ..enqueue('segundo')
        ..enqueue('tercero');

      await whenIdle(queue);

      expect(transformer.processed, ['primero', 'segundo', 'tercero']);
    });
  });

  group('sin trabajo repetido', () {
    test('encolar dos veces lo mismo lo procesa una sola vez', () async {
      await seed('a');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer)
        ..enqueue('a')
        ..enqueue('a');

      await whenIdle(queue);

      expect(transformer.processed, ['a']);
    });

    test(
      'tampoco se reencola el que se está descargando en ese momento',
      () async {
        // El que está en curso ya salió de la cola. Mirando solo la cola,
        // volvería a entrar y se descargaría dos veces — justo lo que pasa al
        // capturar algo y que la biblioteca arranque su repaso de pendientes
        // en el mismo instante.
        await seed('a');

        final transformer = _ScriptedTransformer(gated: true);
        final queue = buildQueue(transformer)..enqueue('a');
        await transformer.started('a');

        queue.enqueue('a');
        transformer.release('a');
        await whenIdle(queue);

        expect(transformer.processed, ['a']);
      },
    );
  });

  test('avisa cada elemento que terminó bien —lo que arranca la bajada del '
      'audio de un video de YouTube (F24)—, y no los que fallaron', () async {
    await seed('sano');
    await seed('roto');
    final processed = <String>[];

    final queue =
        buildQueue(
            _ScriptedTransformer(failOn: {'roto'}),
            onProcessed: (item) => processed.add(item.id),
          )
          ..enqueue('sano')
          ..enqueue('roto');
    await whenIdle(queue);

    expect(processed, ['sano']);
  });

  group('cuando algo falla', () {
    test('lo que sigue se procesa igual', () async {
      // Un enlace roto en el medio no puede dejar sin traer a los otros
      // nueve.
      await seed('roto');
      await seed('sano');

      final transformer = _ScriptedTransformer(failOn: {'roto'});
      final queue = buildQueue(transformer)
        ..enqueue('roto')
        ..enqueue('sano');

      await whenIdle(queue);

      expect(await stateOf('roto'), ProcessingState.failed);
      expect(await stateOf('sano'), ProcessingState.ready);
    });
  });

  group('lo que quedó de sesiones anteriores', () {
    test('se retoma lo pendiente al arrancar', () async {
      // Alguien capturó tres enlaces sin conexión y cerró la app.
      await seed('uno');
      await seed('dos');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.resume();
      await whenIdle(queue);

      expect(transformer.processed, containsAll(['uno', 'dos']));
    });

    test('se retoma también lo que quedó EN CURSO: la app se cerró a mitad '
        'de procesarlo', () async {
      // "El Santo Rosario" (F21): quedó "Procesando" de una sesión en la que
      // HyperOS congeló la app, y nada lo volvía a encolar nunca.
      await seed('a-medias', state: ProcessingState.processing);

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.resume();
      await whenIdle(queue);

      expect(transformer.processed, ['a-medias']);
      expect(await stateOf('a-medias'), ProcessingState.ready);
    });

    test('algo que se cortó demasiadas veces no se retoma más: queda '
        'fallido por interrupción', () async {
      // Si es él el que hace caer la app, retomarlo en cada arranque sería
      // un bucle.
      await seed('tumba-la-app', state: ProcessingState.processing);
      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('tumba-la-app'))).write(
        const KnowledgeSourcesCompanion(
          processingAttempts: Value(
            ProcessingQueueNotifier.maxInterruptedAttempts,
          ),
        ),
      );

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.resume();
      await whenIdle(queue);

      expect(transformer.processed, isEmpty);
      expect(await stateOf('tumba-la-app'), ProcessingState.failed);
    });

    test('retomar dos veces en la misma sesión no toma por interrumpido lo '
        'que se está procesando ahora', () async {
      await seed('a');

      final transformer = _ScriptedTransformer(gated: true);
      final queue = buildQueue(transformer);
      await queue.resume();
      await transformer.started('a');

      // La biblioteca se vuelve a montar —bloquear y desbloquear la bóveda,
      // por ejemplo— y pide retomar otra vez mientras 'a' está en curso.
      await queue.resume();
      expect(await stateOf('a'), ProcessingState.processing);

      transformer.release('a');
      await whenIdle(queue);

      expect(transformer.processed, ['a']);
      expect(await stateOf('a'), ProcessingState.ready);
    });

    test('NO se reintenta solo lo que ya falló', () async {
      // Un fallo puede ser permanente —un video borrado, una página que ya no
      // existe—. Reintentarlo en cada arranque sería gastar batería y datos
      // para volver a fallar. Se reintenta a pedido, desde el elemento.
      await seed('fallido', state: ProcessingState.failed);
      await seed('pendiente');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.resume();
      await whenIdle(queue);

      expect(transformer.processed, ['pendiente']);
      expect(await stateOf('fallido'), ProcessingState.failed);
    });

    test('tampoco se vuelve a traer lo que ya está listo', () async {
      await seed('listo', state: ProcessingState.ready);

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.resume();
      await whenIdle(queue);

      expect(transformer.processed, isEmpty);
    });

    test('ni lo que está en la papelera', () async {
      await seed('borrado');
      await repository.delete('borrado');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.resume();
      await whenIdle(queue);

      expect(transformer.processed, isEmpty);
    });
  });

  group('reintentar a pedido', () {
    test('vuelve a procesar un fallido, desde cero', () async {
      await seed('fallido', state: ProcessingState.failed);
      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('fallido'))).write(
        const KnowledgeSourcesCompanion(
          processingAttempts: Value(2),
          processingError: Value('network'),
        ),
      );

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.retry('fallido');
      await whenIdle(queue);

      expect(transformer.processed, ['fallido']);
      expect(await stateOf('fallido'), ProcessingState.ready);
    });
  });

  group('nada frena la cola', () {
    test(
      'un elemento colgado vence su tope y el siguiente se procesa',
      () async {
        // El short de YouTube (F21): un pedido que nunca respondía dejaba todo
        // lo que venía detrás "En espera" para siempre.
        await seed('colgado');
        await seed('siguiente');

        final transformer = _ScriptedTransformer(
          hangOn: {'colgado'},
          timeLimit: const Duration(milliseconds: 50),
        );
        final queue = buildQueue(transformer)
          ..enqueue('colgado')
          ..enqueue('siguiente');
        await whenIdle(queue);

        expect(await stateOf('colgado'), ProcessingState.failed);
        expect(await stateOf('siguiente'), ProcessingState.ready);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  group('lo que el usuario borra o restaura', () {
    test('borrar el que está en curso destraba la cola en el acto', () async {
      // Borrar el short trabado no destrababa nada (F21): la cola seguía
      // esperando lo que el usuario ya había descartado.
      await seed('trabado');
      await seed('siguiente');

      final transformer = _ScriptedTransformer(hangOn: {'trabado'});
      final queue = buildQueue(transformer)
        ..enqueue('trabado')
        ..enqueue('siguiente');
      await transformer.started('trabado');

      await repository.delete('trabado');
      await transformer.started('siguiente');
      await whenIdle(queue);

      expect(await stateOf('siguiente'), ProcessingState.ready);
      // En espera —no fallido—, por si se lo restaura. Un elemento en la
      // papelera no se devuelve al buscarlo: se mira su fila directamente.
      final trabado = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals('trabado'))).getSingle();
      expect(trabado.processingStatus, SourceProcessingStatus.pending);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('lo que se restaura de la papelera se procesa solo', () async {
      // La cola sigue a la base: nadie tiene que acordarse de avisarle.
      await seed('borrado');
      await repository.delete('borrado');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);
      await queue.resume();
      expect(transformer.processed, isEmpty);

      await repository.restore('borrado');
      await transformer.started('borrado');
      await whenIdle(queue);

      expect(await stateOf('borrado'), ProcessingState.ready);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('nada corta la cola', () {
    test('si armar el caso de uso lanza, el siguiente se procesa '
        'igual', () async {
      await seed('a');
      await seed('b');

      final transformer = _ScriptedTransformer();
      final useCase = buildUseCase(transformer);
      var calls = 0;
      final queue =
          buildQueue(
              transformer,
              resolveProcessItem: () {
                calls++;
                if (calls == 1) throw StateError('un proveedor roto');
                return useCase;
              },
            )
            ..enqueue('a')
            ..enqueue('b');
      await whenIdle(queue);

      expect(transformer.processed, ['b']);
      expect(queue.state.isIdle, isTrue);
    });
  });

  group('el proveedor', () {
    test('no se reconstruye —ni pierde la cola— cuando se reconstruye lo '
        'que usa', () {
      // Antes observaba ~20 proveedores: elegir otro modelo de chat
      // reconstruía la cola y dejaba todo "En espera" hasta el próximo
      // arranque.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = container.read(processingQueueProvider.notifier);
      container
        ..invalidate(processItemUseCaseProvider)
        ..invalidate(processingStateRepositoryProvider)
        ..invalidate(chatModelOptionNotifierProvider);

      expect(
        identical(container.read(processingQueueProvider.notifier), before),
        isTrue,
      );
    });
  });

  group('lo que publica mientras trabaja', () {
    test('dice cuál está en curso y cuántos faltan', () async {
      await seed('a');
      await seed('b');
      await seed('c');

      final transformer = _ScriptedTransformer(gated: true);
      final queue = buildQueue(transformer)
        ..enqueue('a')
        ..enqueue('b')
        ..enqueue('c');
      await transformer.started('a');

      // Los dos que entraron después del arranque tienen que contarse ya. Si
      // el contador solo se refrescara al sacar el siguiente de la cola, la
      // interfaz mostraría "faltan 0" con dos esperando turno.
      expect(queue.state.active.keys, ['a']);
      expect(queue.state.waiting, 2);

      transformer.release('a');
      await transformer.started('b');

      expect(queue.state.active.keys, ['b']);
      expect(queue.state.waiting, 1);

      transformer
        ..release('b')
        ..release('c');
      await whenIdle(queue);

      expect(queue.state.isIdle, isTrue);
    });

    test('publica el avance de lo que va por el carril largo', () async {
      // Lo que dibuja la barra: "página 3 de 10".
      await seed('libro');

      final transformer = _ScriptedTransformer(
        gated: true,
        longOn: {'libro'},
        progressOf: {'libro': (3, 10)},
      );
      final queue = buildQueue(transformer)..enqueue('libro');
      await transformer.enteredLong('libro');

      expect(
        queue.state.active['libro'],
        const ProcessingProgress(lane: ProcessingLane.long, done: 3, total: 10),
      );
      expect(queue.state.active['libro']!.fraction, closeTo(0.3, 1e-9));

      transformer.release('libro');
      await whenIdle(queue);
      expect(queue.state.active, isEmpty);
    });
  });

  group('dos carriles', () {
    test('lo largo no frena a lo corto: la página se procesa mientras el '
        'video se transcribe', () async {
      // Con una sola fila, un video de cuatro horas frenaba la página web que
      // se guardó después (F21).
      await seed('video-largo');
      await seed('pagina');

      final transformer = _ScriptedTransformer(
        gated: true,
        longOn: {'video-largo'},
      );
      final queue = buildQueue(transformer)
        ..enqueue('video-largo')
        ..enqueue('pagina');
      await transformer.enteredLong('video-largo');
      await transformer.started('pagina');

      transformer.release('pagina');
      await _until(
        () async => await stateOf('pagina') == ProcessingState.ready,
      );
      expect(await stateOf('video-largo'), ProcessingState.processing);
      expect(queue.state.active['video-largo']!.lane, ProcessingLane.long);

      transformer.release('video-largo');
      await whenIdle(queue);
      expect(await stateOf('video-largo'), ProcessingState.ready);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('el carril largo también es de a uno: el segundo espera su '
        'turno', () async {
      await seed('primero');
      await seed('segundo');

      final transformer = _ScriptedTransformer(
        gated: true,
        longOn: {'primero', 'segundo'},
      );
      final queue = buildQueue(transformer)
        ..enqueue('primero')
        ..enqueue('segundo');
      await transformer.enteredLong('primero');
      await transformer.started('segundo');
      await _until(
        () async =>
            queue.state.active['segundo']?.lane ==
            ProcessingLane.waitingForLong,
      );

      transformer.release('primero');
      await transformer.enteredLong('segundo');
      expect(queue.state.active['segundo']!.lane, ProcessingLane.long);

      transformer.release('segundo');
      await whenIdle(queue);
      expect(await stateOf('segundo'), ProcessingState.ready);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('borrar uno que espera turno para el carril largo lo saca de la '
        'fila', () async {
      await seed('primero');
      await seed('esperando');

      final transformer = _ScriptedTransformer(
        gated: true,
        longOn: {'primero', 'esperando'},
      );
      final queue = buildQueue(transformer)
        ..enqueue('primero')
        ..enqueue('esperando');
      await transformer.enteredLong('primero');
      await transformer.started('esperando');

      await repository.delete('esperando');
      await _until(() async => !queue.state.active.containsKey('esperando'));

      transformer.release('primero');
      await whenIdle(queue);
      expect(transformer.processed, ['primero', 'esperando']);
      expect(await stateOf('primero'), ProcessingState.ready);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('mantener viva la app en el trabajo largo (F21, decisión C)', () {
    test('mientras hay algo en el carril largo, con su avance; al terminar, '
        'se suelta', () async {
      await seed('video-largo');
      final keeper = _RecordingKeeper();
      final transformer = _ScriptedTransformer(
        gated: true,
        longOn: {'video-largo'},
        progressOf: {'video-largo': (3, 10)},
      );
      final queue = buildQueue(transformer, longWork: keeper)
        ..enqueue('video-largo');
      await transformer.enteredLong('video-largo');
      await _until(
        () async => keeper.calls.contains('working 3/10 mediaProcessing'),
      );

      transformer.release('video-largo');
      await whenIdle(queue);
      expect(keeper.calls.last, 'idle');
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('lo corto también la mantiene viva —una página que se está '
        'trayendo no se congela al minimizar—, como traer datos', () async {
      await seed('pagina');
      final keeper = _RecordingKeeper();
      final transformer = _ScriptedTransformer(gated: true);
      final queue = buildQueue(transformer, longWork: keeper)
        ..enqueue('pagina');
      await transformer.started('pagina');

      expect(keeper.calls.last, 'working 0/0 dataSync');

      transformer.release('pagina');
      await whenIdle(queue);
      expect(keeper.calls.last, 'idle');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('al descartarse', () {
    test('no sigue con los que quedaban esperando', () async {
      // Cerrar la app a mitad de la cola no puede dejar trabajo escribiendo
      // sobre un notifier ya muerto.
      await seed('a');
      await seed('b');

      final transformer = _ScriptedTransformer(gated: true);
      final queue = buildQueue(transformer)
        ..enqueue('a')
        ..enqueue('b');
      await transformer.started('a');

      queue.dispose();
      transformer.release('a');
      await pumpEventQueue();

      expect(transformer.processed, ['a']);
      expect(await stateOf('b'), ProcessingState.pending);
    });
  });
}

/// Espera a que [condition] se cumpla, dándole turno al resto: lo que la
/// cola hace en paralelo entre sus dos carriles no se puede esperar con una
/// sola señal.
Future<void> _until(Future<bool> Function() condition) async {
  while (!await condition()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Anota lo que la cola le pide al que mantiene viva la app.
class _RecordingKeeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('working $done/$total ${kind.name}');

  @override
  void idle() => calls.add('idle');
}
