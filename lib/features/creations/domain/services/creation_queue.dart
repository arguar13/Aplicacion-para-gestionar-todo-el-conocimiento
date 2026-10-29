import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/creation_material_builder.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_resolver.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// La cola de crear de «Lo creado» (F43, punto 2 del plan): genera de a una,
/// en el orden en que se pidieron, lo que la persona pidió con
/// «Generar ahora» o «Generar más tarde».
///
/// - **«Generar ahora»** ([CreationRequest.runNow]): con el modelo de la
///   persona —su turno y su cuota—, antes que todo lo de «más tarde».
/// - **«Generar más tarde»**: con la cola de fondo (`LanguageModelTasks
///   .background`): espera a que la persona no use el modelo y gasta del tope
///   diario de la IA de fondo. Si ese tope se agotó o no hay cuota, espera
///   —sin fallar— y vuelve a mirar cada [laterRetryDelay].
/// - **Persistente**: el estado vive en la base. Lo que quedó en la cola o a
///   medias cuando se cerró la app se retoma al abrirla ([resume]); lo que se
///   empezó [maxInterruptedAttempts] veces sin terminar queda fallido, como en
///   la cola de procesamiento de F21.
/// - **Viva con la app minimizada**: mientras genera, pide el servicio en
///   primer plano de F21 ([LongWorkOwner.creating]); se puede salir de la
///   pantalla y sigue.
/// - **Las de extraer** no esperan nada: [create] las deja listas, y si a una
///   fuente le faltan el resumen, la síntesis o las palabras clave que muestra,
///   le pide el análisis de siempre (`analyzeForStudy`, F36).
/// - **Cancelar y reintentar**: [cancel] corta lo que se escribe; [retry] y
///   [regenerate] la vuelven a la cola. Mandarla a la papelera la cancela
///   sola.
///
/// Sus dependencias se piden al usarlas, no al nacer —como la cola de
/// procesamiento—: cambiar de modelo no la rearma ni pierde lo que espera.
class CreationQueue {
  CreationQueue({
    required StudyCreationRepository Function() repository,
    required CreationScopeResolver Function() scopes,
    required CreationMaterialBuilder Function() material,
    required Map<StudyCreationKind, CreationGenerator> Function() generators,
    required StructuredWriter Function() personWriter,
    required StructuredWriter Function() backgroundWriter,
    LanguageModelStatusCheck Function()? readiness,
    String Function()? modelName,
    LongWorkKeeper Function()? keeper,
    void Function(String documentId)? analyzeForStudy,
    void Function(Object error, StackTrace stackTrace)? onError,
    this.laterRetryDelay = const Duration(minutes: 10),
  }) : _repository = repository,
       _scopes = scopes,
       _material = material,
       _generators = generators,
       _personWriter = personWriter,
       _backgroundWriter = backgroundWriter,
       _readiness = readiness,
       _modelName = modelName,
       _keeperOf = keeper,
       _analyzeForStudy = analyzeForStudy,
       _onError = onError;

  /// Cuántas veces se retoma algo que quedó a medias porque la app se cerró,
  /// antes de darlo por fallido: lo de la cola de procesamiento (F21).
  static const maxInterruptedAttempts = 3;

  /// Cada cuánto se vuelve a mirar si la IA de fondo ya puede, cuando lo de
  /// «más tarde» espera cuota.
  final Duration laterRetryDelay;

  final StudyCreationRepository Function() _repository;
  final CreationScopeResolver Function() _scopes;
  final CreationMaterialBuilder Function() _material;
  final Map<StudyCreationKind, CreationGenerator> Function() _generators;
  final StructuredWriter Function() _personWriter;
  final StructuredWriter Function() _backgroundWriter;
  final LanguageModelStatusCheck Function()? _readiness;
  final String Function()? _modelName;
  final LongWorkKeeper Function()? _keeperOf;
  final void Function(String documentId)? _analyzeForStudy;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  LongWorkKeeper? _keeper;

  /// Lo que se está generando ahora, con su señal para cortarlo y cuándo
  /// termina.
  final _running = <String, _Run>{};

  var _draining = false;

  /// Si mientras se vaciaba la cola entró algo nuevo: se vuelve a mirar.
  var _wokenWhileDraining = false;
  var _recovered = false;
  var _disposed = false;
  Timer? _laterRetry;

  /// Si [id] se está generando en esta sesión.
  bool isRunning(String id) => _running.containsKey(id);

  /// Crea una para [request] y, si es de la IA, la pone a generar. Devuelve la
  /// creación tal como quedó guardada: en la cola, o lista si es de extraer.
  Future<Either<Failure, StudyCreation>> create(CreationRequest request) async {
    final created = await _repository().create(request);
    final creation = created.getRight().toNullable();
    if (creation == null) return created;
    if (creation.kind.isLiveView) {
      await _analyzeMissing(creation);
    } else {
      _wake();
    }
    return created;
  }

  /// «Reintentar»: la vuelve a la cola, con el turno de antes o el de
  /// [runNow].
  Future<Either<Failure, StudyCreation>> retry(String id, {bool? runNow}) =>
      regenerate(id, runNow: runNow);

  /// «Volver a generar con otras opciones»: la vuelve a la cola —con sus
  /// nuevas [options], [sourceIds] o [languageCode], si se dan— y conserva su
  /// lugar en «Lo creado». Una de extraer queda lista con lo nuevo.
  Future<Either<Failure, StudyCreation>> regenerate(
    String id, {
    bool? runNow,
    Map<String, Object?>? options,
    List<String>? sourceIds,
    String? languageCode,
  }) async {
    // Lo que se estaba generando se corta y se espera a que suelte: si no, su
    // «cancelada» llegaría después y pisaría la cola.
    final running = _running[id];
    if (running != null) {
      running.signal.cancel();
      await running.done.future;
    }
    final requeued = await _repository().requeue(
      id,
      runNow: runNow,
      options: options,
      sourceIds: sourceIds,
      languageCode: languageCode,
    );
    final creation = requeued.getRight().toNullable();
    if (creation == null) return requeued;
    if (creation.kind.isLiveView) {
      await _analyzeMissing(creation);
    } else {
      _wake();
    }
    return requeued;
  }

  /// Corta [id]: si se está generando, lo que se escribe; si espera, sale de
  /// la cola. Queda fallida por cancelada, con «Reintentar».
  Future<void> cancel(String id) async {
    final running = _running[id];
    if (running != null) {
      running.signal.cancel();
      return;
    }
    final found = await _repository().find(id);
    final creation = found.getRight().toNullable();
    if (creation == null || !creation.status.isPending) return;
    await _repository().fail(id, CreationFailure.cancelled);
  }

  /// La manda a la papelera; si se estaba generando, la corta.
  Future<Either<Failure, Unit>> trash(String id) async {
    final result = await _repository().trash(id);
    _running[id]?.signal.cancel();
    return result;
  }

  /// Retoma lo que quedó de sesiones anteriores: lo que se cortó a mitad
  /// vuelve a la cola —o falla si ya se intentó [maxInterruptedAttempts]
  /// veces— y la cola se pone a trabajar. Se llama al abrir la app, junto con
  /// la cola de procesamiento.
  Future<void> resume() async {
    await _recover();
    _wake();
  }

  /// Deja de trabajar: lo que se estaba generando se corta y queda en la cola
  /// —«generándose», para que el próximo [resume] lo retome—.
  void dispose() {
    _disposed = true;
    _laterRetry?.cancel();
    for (final run in _running.values) {
      run.signal.cancel();
    }
    _keeper?.idle();
  }

  Future<void> _recover() async {
    if (_recovered) return;
    _recovered = true;
    final recovered = await _repository().recoverInterrupted(
      maxAttempts: maxInterruptedAttempts,
      inFlight: _running.keys.toSet(),
    );
    recovered.getLeft().map((failure) => _report(failure, StackTrace.current));
  }

  void _wake() {
    if (_disposed) return;
    if (_draining) {
      _wokenWhileDraining = true;
      return;
    }
    unawaited(_drain());
  }

  /// Genera de a una lo que espera, hasta que no quede nada que se pueda hacer
  /// ahora.
  Future<void> _drain() async {
    _draining = true;
    try {
      await _recover();
      do {
        _wokenWhileDraining = false;
        while (!_disposed) {
          final next = await _next();
          if (next == null) break;
          await _run(next);
        }
      } while (_wokenWhileDraining && !_disposed);
    } finally {
      _draining = false;
      _keeper?.idle();
    }
  }

  /// La próxima que se puede generar ahora: la primera de «ahora» y, si no hay,
  /// la primera de «más tarde» si la IA de fondo puede. Si no puede, espera
  /// [laterRetryDelay] y vuelve a mirar.
  Future<StudyCreation?> _next() async {
    final pending = await _repository().pending();
    final queued = [
      for (final creation
          in pending.getRight().toNullable() ?? const <StudyCreation>[])
        if (creation.status == CreationStatus.queued) creation,
    ];
    for (final creation in queued) {
      if (creation.runNow) return creation;
    }
    if (queued.isEmpty) return null;
    final check = _readiness?.call();
    if (check != null && !(await check(background: true)).isReady) {
      _laterRetry?.cancel();
      _laterRetry = Timer(laterRetryDelay, _wake);
      return null;
    }
    return queued.first;
  }

  Future<void> _run(StudyCreation creation) async {
    final repository = _repository();
    final id = creation.id;
    final generator = _generators()[creation.kind];
    if (generator == null) {
      await repository.fail(
        id,
        CreationFailure.unsupported,
        detail: 'Sin generador para ${creation.kind.storageKey}.',
      );
      return;
    }
    if (creation.runNow) {
      final check = _readiness?.call();
      final status = check == null ? null : await check();
      if (status != null && !status.isReady) {
        await repository.fail(
          id,
          CreationFailure.modelUnavailable,
          detail: status.runtimeType.toString(),
        );
        return;
      }
    }

    final signal = CancellationSignal();
    final run = _Run(signal);
    _running[id] = run;
    // Si la mandan a la papelera desde cualquier lado mientras se genera, se
    // corta: se escucha la base y no a quien borra.
    final watch = repository.watch(id).listen((current) {
      if (current == null || current.isTrashed) signal.cancel();
    }, onError: (Object _) {});
    _working(0);
    try {
      await repository.markGenerating(id, modelName: _modelName?.call());
      final writer = creation.runNow ? _personWriter() : _backgroundWriter();
      final job = CreationJob(creation: creation, cancellation: signal);
      final material = await _material().build(
        sourceIds: creation.sourceIds,
        budget: generator.budgetFor(job, writer.contextTokens),
      );
      final built = material.getRight().toNullable();
      if (built == null) {
        throw StateError('No se pudo armar el material: $material');
      }
      if (built.isEmpty) {
        await repository.fail(id, CreationFailure.noSources);
        return;
      }
      if (signal.isCancelled) throw const CreationCancelledException();
      final output = await generator.generate(job, built, writer, (
        progress,
        step,
      ) {
        _working(progress);
        unawaited(
          repository.reportProgress(id, progress: progress, step: step),
        );
      });
      if (signal.isCancelled) throw const CreationCancelledException();
      await repository.complete(
        id,
        title: output.title,
        content: output.content,
        contentVersion: output.contentVersion,
        sourceIds: output.sourceIds ?? built.sourceIds,
      );
    } on CreationCancelledException {
      // Al descartarse la cola (la app se cierra) queda «generándose»: el
      // próximo arranque la retoma. Si no, la cortó la persona.
      if (!_disposed) await repository.fail(id, CreationFailure.cancelled);
    } on ProcessingCancelledException {
      if (!_disposed) await repository.fail(id, CreationFailure.cancelled);
    } on UnreadableStructuredReply catch (e) {
      await repository.fail(
        id,
        CreationFailure.unreadableReply,
        detail: e.reason,
      );
      // Un solo pedido que falla nunca corta la cola: los demás siguen.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _report(e, stackTrace);
      await repository.fail(id, CreationFailure.error, detail: '$e');
    } finally {
      await watch.cancel();
      _running.remove(id);
      run.done.complete();
    }
  }

  /// Pide el análisis de estudio (F36) de las fuentes de [creation] a las que
  /// les falta lo que muestra: el resumen, la síntesis o las palabras clave.
  Future<void> _analyzeMissing(StudyCreation creation) async {
    final analyze = _analyzeForStudy;
    if (analyze == null || creation.sourceIds.isEmpty) return;
    final described = await _scopes().sourcesOf(creation.sourceIds);
    for (final source
        in described.getRight().toNullable() ?? const <CreationSource>[]) {
      if (!source.isLive) continue;
      final missing = switch (creation.kind) {
        StudyCreationKind.summary => !source.hasSummary,
        StudyCreationKind.synthesis => !source.hasSynthesis,
        // El texto completo lleva las palabras clave en rosa.
        _ => !source.hasKeywords,
      };
      if (missing) analyze(source.documentId);
    }
  }

  /// Avisa que hay trabajo —con [progress] de 0 a 1— para el servicio en
  /// primer plano.
  void _working(double progress) {
    final keeper = _keeper ??= _keeperOf?.call();
    keeper?.working(done: (progress * 100).round().clamp(0, 100), total: 100);
  }

  void _report(Object error, StackTrace stackTrace) =>
      _onError?.call(error, stackTrace);
}

/// Una creación que se está generando: su señal y cuándo termina.
class _Run {
  _Run(this.signal);

  final CancellationSignal signal;
  final done = Completer<void>();
}
