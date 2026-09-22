import 'dart:async';

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
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';

import '../../../../support/fake_duplicate_suggestion_generator.dart';
import '../../../../support/fake_metadata_suggestion_generator.dart';
import '../../../../support/fake_property_suggestion_generator.dart';
import '../../../../support/fake_relation_suggestion_generator.dart';
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
  _ScriptedTransformer({this.gated = false, this.failOn = const <String>{}});

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

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    processed.add(item.id);

    final startSignal = _signal(_started, item.id);
    if (!startSignal.isCompleted) startSignal.complete();

    if (gated) await _signal(_released, item.id).future;
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

  ProcessingQueueNotifier buildQueue(Transformer transformer) {
    final queue = ProcessingQueueNotifier(
      processItem: ProcessItemUseCase(
        registry: TransformerRegistry([transformer]),
        repository: repository,
        logger: const SilentLogger(),
        telemetry: MockTelemetryService(),
        clock: () => now,
        suggestionGenerator: FakePropertySuggestionGenerator(),
        relationSuggestionGenerator: FakeRelationSuggestionGenerator(),
        duplicateSuggestionGenerator: FakeDuplicateSuggestionGenerator(),
        metadataSuggestionGenerator: FakeMetadataSuggestionGenerator(),
      ),
      repository: repository,
      logger: const SilentLogger(),
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
    if (queue.state is QueueIdle) return Future<void>.value();

    final done = Completer<void>();
    final remove = queue.addListener((state) {
      if (state is QueueIdle && !done.isCompleted) done.complete();
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

      await queue.enqueuePending();
      await whenIdle(queue);

      expect(transformer.processed, containsAll(['uno', 'dos']));
    });

    test('NO se reintenta solo lo que ya falló', () async {
      // Un fallo puede ser permanente —un video borrado, una página que ya no
      // existe—. Reintentarlo en cada arranque sería gastar batería y datos
      // para volver a fallar. Se reintenta a pedido, desde el elemento.
      await seed('fallido', state: ProcessingState.failed);
      await seed('pendiente');

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.enqueuePending();
      await whenIdle(queue);

      expect(transformer.processed, ['pendiente']);
      expect(await stateOf('fallido'), ProcessingState.failed);
    });

    test('tampoco se vuelve a traer lo que ya está listo', () async {
      await seed('listo', state: ProcessingState.ready);

      final transformer = _ScriptedTransformer();
      final queue = buildQueue(transformer);

      await queue.enqueuePending();
      await whenIdle(queue);

      expect(transformer.processed, isEmpty);
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
      expect(
        queue.state,
        const ProcessingQueueState.working(currentItemId: 'a', remaining: 2),
      );

      transformer.release('a');
      await transformer.started('b');

      expect(
        queue.state,
        const ProcessingQueueState.working(currentItemId: 'b', remaining: 1),
      );

      transformer
        ..release('b')
        ..release('c');
      await whenIdle(queue);

      expect(queue.state, const ProcessingQueueState.idle());
    });
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
