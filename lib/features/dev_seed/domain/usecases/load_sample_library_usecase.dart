import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_library_progress.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/repositories/sample_library_ledger.dart';
import 'package:sinapsis/features/dev_seed/domain/services/sample_file_downloader.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Carga la biblioteca de ejemplo en la bóveda: cada recurso por el mismo
/// camino que si el usuario lo hubiera guardado a mano.
///
/// - Un **enlace** —una página, un video— se captura por su dirección, como
///   cuando se pega uno, y se encola para procesarlo.
/// - Un **archivo** se baja primero a un temporal y se captura como si se lo
///   hubiera elegido con el selector del sistema, y se encola igual.
/// - Una **nota** se guarda como la guarda el editor de bloques, con sus
///   `[[enlaces]]`.
///
/// Lo que pasa después —transcribir, bajar el audio de un video, que la IA
/// lo organice— es lo de siempre: la cola de procesamiento no distingue un
/// ejemplo de algo propio. Esa es la idea: probar la app de verdad.
///
/// **Por tandas** de [batchSize], y dentro de cada tanda hasta
/// [parallelDownloads] a la vez. Así se ve el avance tanda por tanda, no se
/// pide todo de golpe a los mismos servidores y nunca hay más de
/// [parallelDownloads] temporales en el disco.
///
/// **No duplica.** Lo que ya se cargó queda anotado en el [SampleLibraryLedger]
/// uno por uno, apenas se guarda, y una pasada nueva lo saltea: tocar dos
/// veces «Cargar», o volver a tocarlo después de cancelar, sigue desde donde
/// quedó.
///
/// **Si uno falla, sigue con los demás**, y el informe dice cuáles fallaron y
/// por qué. Un fallado no se anota: la próxima pasada lo vuelve a intentar.
class LoadSampleLibraryUseCase {
  LoadSampleLibraryUseCase({
    required List<SampleResource> resources,
    required SampleLibraryLedger ledger,
    required SampleFileDownloader downloader,
    required UseCase<KnowledgeItem, CaptureRequest> captureItem,
    required LibraryRepository repository,
    required void Function(String itemId) enqueue,
    required IdGenerator ids,
    required Clock clock,
    this.batchSize = 10,
    this.parallelDownloads = 3,
  }) : assert(batchSize > 0, 'Una tanda tiene que tener algo.'),
       assert(parallelDownloads > 0, 'Hace falta al menos una bajada.'),
       _resources = resources,
       _ledger = ledger,
       _downloader = downloader,
       _captureItem = captureItem,
       _repository = repository,
       _enqueue = enqueue,
       _ids = ids,
       _clock = clock;

  final List<SampleResource> _resources;
  final SampleLibraryLedger _ledger;
  final SampleFileDownloader _downloader;
  final UseCase<KnowledgeItem, CaptureRequest> _captureItem;
  final LibraryRepository _repository;
  final void Function(String itemId) _enqueue;
  final IdGenerator _ids;
  final Clock _clock;

  /// Cuántos recursos tiene cada tanda.
  final int batchSize;

  /// Cuántos se cargan a la vez dentro de una tanda.
  final int parallelDownloads;

  /// Lo que todavía no se cargó, en el orden de la lista.
  List<SampleResource> pending() {
    final loaded = _ledger.loadedIds();
    return [
      for (final resource in _resources)
        if (!loaded.contains(resource.id)) resource,
    ];
  }

  /// Carga lo que falta. [onProgress] recibe el avance cada vez que algo
  /// cambia. Si [cancellation] pide cortar, no empieza nada más, corta las
  /// bajadas en curso y devuelve hasta donde llegó.
  Future<SampleLoadReport> call({
    required CancellationSignal cancellation,
    void Function(SampleLoadProgress progress)? onProgress,
  }) async {
    final toLoad = pending();
    final batches = (toLoad.length / batchSize).ceil();
    var progress = SampleLoadProgress(
      total: toLoad.length,
      alreadyLoaded: _resources.length - toLoad.length,
      batch: 0,
      batches: batches,
    );
    void publish(SampleLoadProgress next) {
      progress = next;
      onProgress?.call(next);
    }

    publish(progress);
    await _downloader.clearLeftovers();

    for (var batch = 0; batch < batches; batch++) {
      if (cancellation.isCancelled) break;
      publish(progress.copyWith(batch: batch + 1));

      final start = batch * batchSize;
      final end = (start + batchSize).clamp(0, toLoad.length);
      final waiting = Queue.of(toLoad.sublist(start, end));

      Future<void> worker() async {
        while (waiting.isNotEmpty && !cancellation.isCancelled) {
          final resource = waiting.removeFirst();
          publish(progress.copyWith(current: resource.title));

          final String? reason;
          try {
            reason = await _load(resource, cancellation);
          } on ProcessingCancelledException {
            return;
          }
          if (reason == null) {
            await _ledger.markLoaded(resource.id);
            publish(progress.copyWith(loaded: progress.loaded + 1));
          } else {
            publish(
              progress.copyWith(
                failures: [
                  ...progress.failures,
                  SampleLoadFailure(title: resource.title, reason: reason),
                ],
              ),
            );
          }
        }
      }

      await Future.wait([for (var i = 0; i < parallelDownloads; i++) worker()]);
    }

    return SampleLoadReport(
      progress: progress,
      cancelled: cancellation.isCancelled,
    );
  }

  /// Carga [resource] por su camino. Devuelve `null` si quedó guardado, o el
  /// motivo por el que no.
  ///
  /// Si se pidió cortar a mitad de una bajada, deja pasar la
  /// [ProcessingCancelledException]: no es un fallo —el recurso no se
  /// cargó, y la próxima pasada lo intenta—.
  Future<String?> _load(
    SampleResource resource,
    CancellationSignal cancellation,
  ) async {
    try {
      final saved = switch (resource) {
        SampleLink(:final url) => await _captureItem(
          CaptureRequest.text(rawInput: url),
        ),
        SampleFile() => await _captureFile(resource, cancellation),
        SampleNote() => await _repository.save(_noteFor(resource)),
      };
      return saved.match<String?>((failure) => failure.message, (item) {
        // Una nota ya está lista; lo demás se encola para traerle el
        // contenido, igual que después de capturar algo a mano.
        if (item.processingState != ProcessingState.ready) _enqueue(item.id);
        return null;
      });
    } on ProcessingCancelledException {
      // Antes que el `on Exception` de abajo, que también la atraparía: es
      // una excepción como cualquier otra para Dart, pero acá significa
      // «cortar», no «este recurso falló».
      rethrow;
    } on SampleDownloadException catch (e) {
      return e.message;
    } on Exception catch (e) {
      // Un error al copiar al almacén —disco lleno, permisos— lo lanza el
      // adaptador en vez de devolverlo. Es de este recurso y no de la
      // carga: se informa y se sigue con los demás.
      return e.toString();
    }
  }

  /// Baja [resource], comprueba que sea lo que se esperaba y lo captura como
  /// archivo. El temporal se borra siempre, se haya guardado o no.
  Future<Either<Failure, KnowledgeItem>> _captureFile(
    SampleFile resource,
    CancellationSignal cancellation,
  ) async {
    final downloaded = await _downloader.download(
      resource,
      cancellation: cancellation,
    );
    try {
      final format = downloaded.file.format;
      if (!resource.kind.formats.contains(format)) {
        return left(
          Failure.validation(
            message:
                'Llegó un archivo ${format.name} en vez de '
                '${resource.kind.name}.',
          ),
        );
      }
      return await _captureItem(
        CaptureRequest.file(file: downloaded.file, title: resource.title),
      );
    } finally {
      await downloaded.discard();
    }
  }

  /// La nota como la guarda el editor de bloques: una sola forma, la de
  /// bloques, que es la que registra los `[[enlaces]]` al guardarse.
  KnowledgeItem _noteFor(SampleNote note) {
    final now = _clock();
    final itemId = _ids.next();
    return KnowledgeItem(
      id: itemId,
      title: note.title,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: itemId,
          kind: RenditionKind.blocks,
          content: encodeContentBlocks([
            for (final block in note.blocks) _stamped(block, now),
          ]),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }

  /// [block] con la fecha en que se agregó, como cualquier bloque escrito
  /// en el editor: es lo que alimenta «qué notas crecieron esta semana».
  ContentBlock _stamped(ContentBlock block, DateTime now) => switch (block) {
    ParagraphBlock() => block.copyWith(addedAt: now),
    HeadingBlock() => block.copyWith(addedAt: now),
    BulletItemBlock() => block.copyWith(addedAt: now),
    NumberedItemBlock() => block.copyWith(addedAt: now),
    ChecklistItemBlock() => block.copyWith(addedAt: now),
    QuoteBlock() => block.copyWith(addedAt: now),
  };
}
