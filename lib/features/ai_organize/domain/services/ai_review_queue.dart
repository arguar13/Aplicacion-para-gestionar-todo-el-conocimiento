import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_item_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// La cola de «Revisar con otro modelo» (F33): de a un elemento por vez y en
/// segundo plano, el modelo elegido ahora revisa lo que hizo la IA y deja lo
/// que propone en «Revisión».
///
/// Hace lo mismo que la cola de la IA de fondo con el modelo (F32), con una
/// diferencia que decidió la persona (decisión C): **es algo que pidió**, así
/// que sale de su cuota, no del tope diario de la IA de fondo. Por eso:
///
/// - el modelo que recibe ([AiItemReviewer]) tiene el turno de la cola —le
///   cede el modelo a la persona cuando lo usa— pero gasta como la persona
///   (`LanguageModelTasks.requestedInBackground`), y el chequeo del modelo se
///   hace como el de la persona, sin el tope;
/// - si el modelo no puede contestar por ahora —sin cuota, sin conexión, el
///   proveedor saturado—, **espera sin perder nada**: el elemento a medio
///   revisar se retoma primero y en la misma pasada cuando vuelve, a la hora
///   de la renovación o en [kAiModelRetryDelay];
/// - tiene su propia **pausa** y su **cancelar**: lo que está en curso termina
///   —una llamada al modelo no se corta a mitad— y no se toma otro.
///
/// Cada elemento es una pasada de revisión (`AiRunScope.review`) del modelo
/// que trabaja: lo que la persona acepte después se aplica en ella, y
/// deshacerla lo devuelve todo.
///
/// Mantiene viva la app mientras trabaja ([LongWorkOwner.aiReview]): una
/// biblioteca entera son cientos de pedidos.
class AiReviewQueue {
  AiReviewQueue({
    required AiRunRepository runs,
    required LibraryRepository library,
    required AiItemReviewer Function() reviewer,
    required LanguageModelStatusCheck Function() languageModel,
    required String? Function() modelName,
    required TelemetryService telemetry,
    required Clock clock,
    required void Function(AiReviewBatch? batch) onBatch,
    LongWorkKeeper longWork = const NoLongWorkKeeper(),
    Duration modelRetryDelay = kAiModelRetryDelay,
  }) : _runs = runs,
       _library = library,
       _reviewer = reviewer,
       _languageModel = languageModel,
       _modelName = modelName,
       _telemetry = telemetry,
       _clock = clock,
       _onBatch = onBatch,
       _longWork = longWork,
       _modelRetryDelay = modelRetryDelay;

  final AiRunRepository _runs;
  final LibraryRepository _library;

  /// Se piden al usarlos: elegir otro modelo cambia quién contesta.
  final AiItemReviewer Function() _reviewer;
  final LanguageModelStatusCheck Function() _languageModel;
  final String? Function() _modelName;
  final TelemetryService _telemetry;
  final Clock _clock;
  final void Function(AiReviewBatch? batch) _onBatch;
  final LongWorkKeeper _longWork;
  final Duration _modelRetryDelay;

  /// Lo que falta revisar, en orden.
  final _pending = Queue<_Request>();

  /// El que se cortó porque el modelo dejó de contestar: se retoma primero,
  /// en su pasada.
  ({_Request request, String runId})? _interrupted;

  AiReviewBatch? _batch;

  /// Cuál pedido es: cambia con cada pedido nuevo y al cancelar, para que lo
  /// que termine de uno viejo no se le sume al nuevo.
  var _serial = 0;
  var _paused = false;

  /// Hasta cuándo esperar al modelo por algo que el chequeo no ve —sin
  /// conexión, el proveedor saturado—. Sin hora, hasta que cambie lo elegido.
  ({AiModelWait reason, DateTime? until})? _held;
  Timer? _resumeTimer;

  Future<void> _draining = Future.value();
  var _running = false;
  var _wakeAgain = false;
  var _disposed = false;

  /// Cómo va el pedido, o `null` si no hay ninguno a la vista.
  AiReviewBatch? get batch => _batch;

  /// Revisa [itemIds], en ese orden, con el modelo elegido. Con
  /// [skipOwnWork] —revisar toda la biblioteca—, en cada elemento deja afuera
  /// lo que hizo el mismo modelo que revisa; sin él —lo pidió la persona en
  /// un elemento—, revisa todo lo que sigue siendo de la IA. Si ya había un
  /// pedido en curso, estos se le suman; uno que ya está en la cola no se
  /// repite.
  void review(Iterable<String> itemIds, {bool skipOwnWork = true}) {
    final queued = {
      for (final request in _pending) request.itemId,
      ?_interrupted?.request.itemId,
    };
    var added = 0;
    for (final itemId in itemIds) {
      if (!queued.add(itemId)) continue;
      _pending.add((itemId: itemId, skipOwnWork: skipOwnWork));
      added++;
    }
    if (added == 0) return;
    final batch = _batch;
    if (batch == null || batch.finished) {
      _serial++;
      _publish(AiReviewBatch(total: added, paused: _paused));
    } else {
      _publish(batch.copyWith(total: batch.total + added));
    }
    unawaited(wake());
  }

  /// Lo que está en curso termina y no se toma otro hasta [resume].
  void pause() {
    _paused = true;
    final batch = _batch;
    if (batch != null) _publish(batch.copyWith(paused: true));
  }

  void resume() {
    _paused = false;
    final batch = _batch;
    if (batch != null) _publish(batch.copyWith(paused: false));
    unawaited(wake());
  }

  /// Cancela lo que falta. Lo que ya se revisó queda en «Revisión», y la
  /// pasada del que esperaba al modelo se cierra con lo que alcanzó.
  void cancel() {
    _pending.clear();
    _paused = false;
    _serial++;
    final interrupted = _interrupted;
    _interrupted = null;
    _resumeTimer?.cancel();
    _publish(null);
    if (interrupted != null) unawaited(_close(interrupted.runId));
  }

  /// Saca de la vista un pedido que ya terminó.
  void dismiss() {
    if (_batch?.finished ?? true) _publish(null);
  }

  /// Cambió el modelo elegido, sus cuentas o sus claves: lo que se esperaba
  /// puede estar resuelto.
  void languageModelChanged() {
    _held = null;
    unawaited(wake());
  }

  /// Revisa si hay algo para hacer. Completa cuando no queda nada que pueda
  /// hacer ahora.
  Future<void> wake() {
    if (_disposed) return Future.value();
    if (_running) {
      _wakeAgain = true;
      return _draining;
    }
    _running = true;
    return _draining = _drain();
  }

  Future<void> dispose() async {
    _disposed = true;
    _resumeTimer?.cancel();
    _longWork.idle();
  }

  /// Cuándo queda quieta: para las pruebas.
  @visibleForTesting
  Future<void> get settled => _draining;

  Future<void> _drain() async {
    try {
      while (!_disposed) {
        _wakeAgain = false;
        if (await _next() case final next?) {
          await _reviewOne(next.request, resumeRun: next.runId);
          continue;
        }
        _longWork.idle();
        if (!_wakeAgain) break;
      }
    } on Object catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'AiReviewQueue._drain');
      _longWork.idle();
    } finally {
      _running = false;
    }
  }

  /// Lo próximo por revisar, o `null` si no se puede ahora; en ese caso deja
  /// publicado por qué.
  Future<({_Request request, String? runId})?> _next() async {
    if (_paused || (_pending.isEmpty && _interrupted == null)) return null;

    final status = await _languageModel()();
    final held = _stillHeld();
    if (!status.isReady || held != null) {
      _waitFor(status, held);
      return null;
    }
    _setWaiting(null, null, modelMissing: false);

    final interrupted = _interrupted;
    if (interrupted != null) {
      _interrupted = null;
      return (request: interrupted.request, runId: interrupted.runId);
    }
    return (request: _pending.removeFirst(), runId: null);
  }

  /// Revisa un elemento en su pasada. Si el modelo deja de contestar por
  /// ahora, el elemento queda primero, con su pasada abierta.
  Future<void> _reviewOne(_Request request, {String? resumeRun}) async {
    final serial = _serial;
    var report = AiStepReport.nothing;
    final item = await _find(request.itemId);
    if (item == null) {
      if (resumeRun != null) await _close(resumeRun);
      _done(serial, report);
      return;
    }
    final batch = _batch;
    if (batch != null && serial == _serial) {
      _publish(batch.copyWith(currentTitle: () => item.title));
      _longWork.working(done: batch.done, total: batch.total);
    }

    final model = _modelName();
    final runId =
        resumeRun ??
        (await _runs.startRun(
          item.id,
          model: model,
          scope: AiRunScope.review,
        )).fold((failure) {
          _telemetry.recordError(
            failure,
            StackTrace.current,
            hint: 'AiReviewQueue: no se pudo abrir la pasada de revisión',
          );
          return null;
        }, (id) => id);
    if (runId == null) {
      _done(serial, report);
      return;
    }

    try {
      report = await _reviewer().review(
        item,
        runId: runId,
        model: model,
        exceptMadeBy: request.skipOwnWork ? model : null,
      );
      // Como un paso de la IA: el modelo es de terceros. Lo que ya propuso
      // queda en «Revisión».
    } on Object catch (e, stackTrace) {
      final wait = aiModelWaitFor(e);
      if (wait != null && serial == _serial) {
        _hold(wait, e);
        _interrupted = (request: request, runId: runId);
        final current = _batch;
        if (current != null) {
          _publish(current.copyWith(currentTitle: () => null));
        }
        return;
      }
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'AiReviewQueue: revisión de ${item.id}',
      );
    }
    await _close(runId);
    _done(serial, report);
  }

  /// Un elemento del pedido, revisado: suma lo que dio.
  void _done(int serial, AiStepReport report) {
    final batch = _batch;
    if (batch == null || serial != _serial) return;
    final next = batch.copyWith(
      done: batch.done + 1,
      proposed: batch.proposed + report.forReview,
      currentTitle: () => null,
    );
    _publish(next);
    if (next.finished) _longWork.idle();
  }

  Future<void> _close(String runId) async {
    (await _runs.finishRun(runId)).match(
      (failure) => _telemetry.recordError(
        failure,
        StackTrace.current,
        hint: 'AiReviewQueue: no se pudo cerrar la pasada de revisión',
      ),
      (_) {},
    );
  }

  /// La espera por algo que el chequeo no ve, si sigue en pie.
  ({AiModelWait reason, DateTime? until})? _stillHeld() {
    final held = _held;
    final until = held?.until;
    if (held == null || until == null) return held;
    if (_clock().isBefore(until)) return held;
    _held = null;
    return null;
  }

  void _hold(AiModelWait wait, Object error) {
    final retryAfter = error is CloudModelException ? error.retryAfter : null;
    _held = (
      reason: wait,
      until: wait == AiModelWait.modelGone
          ? null
          : _clock().add(retryAfter ?? _modelRetryDelay),
    );
  }

  /// No puede trabajar ahora: lo publica y se despierta sola cuando vuelva lo
  /// que espera.
  void _waitFor(
    LanguageModelStatus status,
    ({AiModelWait reason, DateTime? until})? held,
  ) {
    _longWork.idle();
    switch (status) {
      case LanguageModelNeedsDownload() || LanguageModelNeedsAccount():
        _setWaiting(null, null, modelMissing: true);
        _wakeAt(null);
      case LanguageModelOutOfQuota(keysRejected: true):
        _setWaiting(AiModelWait.keysRejected, null, modelMissing: false);
        _wakeAt(null);
      case LanguageModelOutOfQuota(:final resetsAt):
        _setWaiting(AiModelWait.quota, resetsAt, modelMissing: false);
        _wakeAt(resetsAt);
      // El tope de la IA de fondo no cuenta acá; si alguna vez llega, se
      // espera igual.
      case LanguageModelBackgroundCapReached(:final resetsAt):
        _setWaiting(AiModelWait.quota, resetsAt, modelMissing: false);
        _wakeAt(resetsAt);
      case LanguageModelReady():
        _setWaiting(held!.reason, held.until, modelMissing: false);
        _wakeAt(held.until);
    }
  }

  void _setWaiting(
    AiModelWait? reason,
    DateTime? until, {
    required bool modelMissing,
  }) {
    final batch = _batch;
    if (batch == null) return;
    final next = batch.copyWith(
      waiting: () => reason,
      resumesAt: () => until,
      modelMissing: modelMissing,
    );
    if (next != batch) _publish(next);
  }

  /// Despierta la cola a las [at], con un segundo de margen.
  void _wakeAt(DateTime? at) {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (at == null || _disposed) return;
    final wait = at.difference(_clock()) + const Duration(seconds: 1);
    _resumeTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(wake()),
    );
  }

  void _publish(AiReviewBatch? batch) {
    _batch = batch;
    _onBatch(batch);
  }

  Future<KnowledgeItem?> _find(String itemId) async =>
      (await _library.findById(itemId)).getRight().toNullable();
}

/// Un elemento por revisar, y si se deja afuera lo que hizo el mismo modelo.
typedef _Request = ({String itemId, bool skipOwnWork});
