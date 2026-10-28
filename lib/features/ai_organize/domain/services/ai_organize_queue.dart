import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_dates_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_dates_finder.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_flashcard_maker.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_memory.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_run_usage_saver.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/ai_organize/domain/services/content_change.dart';
import 'package:sinapsis/features/ai_organize/domain/services/organize_text.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Cuánto tiene que estar quieta una nota antes de que la IA la organice:
/// mientras se escribe, cada guardado la cambia, y organizarla a mitad sería
/// vincular y hacer tarjetas de un borrador.
const kAiNoteQuietPeriod = Duration(seconds: 15);

/// Cuánto espera la IA de fondo para volver a probar cuando el modelo en la
/// nube no contestó por algo que pasa solo —sin conexión, el proveedor
/// saturado— y no dijo cuánto esperar (F32).
const kAiModelRetryDelay = Duration(minutes: 5);

/// Si [error] dice que el modelo de lenguaje no puede contestar **por
/// ahora** —sin cuota, sin conexión, la clave—, por qué (F32); `null` si es
/// algo de este pedido —el proveedor no quiso, era largo— o de Gemma, que se
/// registra y se sigue como siempre.
AiModelWait? aiModelWaitFor(Object error) {
  if (error is! CloudModelException) return null;
  return switch (error.failure) {
    CloudModelFailure.quotaExhausted => AiModelWait.quota,
    CloudModelFailure.backgroundCap => AiModelWait.backgroundCap,
    CloudModelFailure.invalidKey ||
    CloudModelFailure.forbidden ||
    CloudModelFailure.noAccount => AiModelWait.keysRejected,
    CloudModelFailure.network => AiModelWait.offline,
    CloudModelFailure.timeout ||
    CloudModelFailure.cutOff => AiModelWait.interrupted,
    CloudModelFailure.unavailable ||
    CloudModelFailure.rateLimited => AiModelWait.busy,
    CloudModelFailure.modelNotFound => AiModelWait.modelGone,
    CloudModelFailure.blocked ||
    CloudModelFailure.badRequest ||
    CloudModelFailure.tooLong ||
    CloudModelFailure.unknown => null,
  };
}

/// La cola de la IA que organiza sola (F27): aparte de la de procesamiento,
/// de a un elemento por vez y en segundo plano. El elemento queda listo como
/// siempre; la IA trabaja después.
///
/// **Qué toma, en este orden:** lo que se pidió organizar a mano
/// ([organizeNow]), y cada documento procesado que se acaba de triar o volver
/// a triar ([enqueueProcessedForOrganizing]); las tarjetas que se pidieron
/// desde Repasar ([makeFlashcards], F30); las fechas que se pidieron para la
/// línea de tiempo ([findDates], F40); lo nuevo —cada nota, y cada documento
/// procesado, que es una, cuando lleva [kAiNoteQuietPeriod] sin cambios—; las
/// notas ya organizadas que cambiaron mucho de contenido
/// (`kNoteRegrowHammingBits`); y, solo si está prendido y el dispositivo está
/// enchufado, la biblioteca que ya existía (decisión C).
///
/// **Las fuentes de la Biblioteca no se organizan** (F41, paso 6): la
/// Biblioteca es la base de consulta, y el Atlas, el Mapa y la Línea de tiempo
/// se arman con lo que la persona eligió de cada una al triarla. La IA
/// organiza ese documento procesado, con lo elegido y nada más
/// ([OrganizeTextReader]). Lo que una fuente ya tenía —sus temas, sus
/// vínculos, sus fechas— queda donde está. Pedirle a la cola que organice o
/// busque fechas de una fuente no hace nada: quien lo ofrece pide el de su
/// documento procesado.
///
/// **Lo pendiente se deduce de la base** (`AiOrganizeBacklog`), no de una
/// lista en memoria: si la app se cierra a mitad, al volver se retoma sola.
/// En memoria solo vive lo que se pidió a mano.
///
/// **Cada elemento** es una pasada: `startRun`, los pasos prendidos en
/// Ajustes › IA, `finishRun`. Si un paso falla, el error se registra y se
/// sigue con el siguiente: lo que ya se creó queda, con su pasada, y se
/// puede deshacer. Un elemento cuya pasada se deshizo no se vuelve a
/// organizar solo.
///
/// **Cuándo no trabaja:** con la IA pausada (el interruptor general), y si
/// falta alguno de los dos modelos —bajar Gemma o el de relaciones, o una
/// clave del que está en la nube—, sin los que no puede hacer nada; en los
/// dos casos lo publica en su estado y espera, sin errores. Pausar no corta
/// el elemento en curso: termina lo que está haciendo —de segundos a un par
/// de minutos— y no toma otro.
///
/// **Con el modelo en la nube (F32)** también espera
/// —[AiOrganizeWaitingForModel]— si no hay cuota, si llegó a su tope del día,
/// si no anda ninguna clave, sin conexión o con el proveedor saturado, y se
/// despierta sola cuando vuelve
/// (a la hora de la renovación, o en [kAiModelRetryDelay]). Si el modelo deja
/// de contestar **a mitad de un elemento**, ese elemento no se da por
/// organizado ni se saltea: la pasada queda abierta y, cuando el modelo
/// vuelve, se retoma **primero** y en la misma pasada, sin repetir los pasos
/// que ya terminó. Lo mismo un pedido de tarjetas: no cuenta como hecho.
///
/// **Le cede el modelo a la persona** sin enterarse: los pasos usan el modelo
/// con el turno de la cola (`GemmaChatModel.background`), que espera a que la
/// persona no lo esté usando.
///
/// **Mantiene viva la app mientras trabaja**, venga de donde venga lo que
/// organiza: lo nuevo, lo pedido a mano, una nota que cambió o —con el
/// cargador— la biblioteca que ya existía. Pide el servicio en primer plano
/// de F21, que comparte con el procesamiento y las descargas
/// (`LongWorkCoordinator`), desde que toma un elemento hasta que no queda
/// nada que pueda hacer —terminó, se pausó, se desenchufó el cargador, falta
/// un modelo—. Antes lo pedía solo para la biblioteca existente: lo nuevo
/// que se organizaba al minimizar la app —de segundos a un par de minutos
/// por elemento, pero a veces decenas seguidas— quedaba congelado a mitad.
/// Si igual el sistema congela la app, la cola sigue al volver.
class AiOrganizeQueue {
  AiOrganizeQueue({
    required AiOrganizeBacklog backlog,
    required AiRunRepository runs,
    required LibraryRepository library,
    required List<AiOrganizeStep> Function() steps,
    required LanguageModelStatusCheck Function() languageModel,
    required EmbeddingModelManager Function() embeddingModel,
    required ChunkEmbeddingIndexer Function() vectors,
    required ChargingProbe charging,
    required AiOrganizeEpoch epoch,
    required TelemetryService telemetry,
    required Clock clock,
    required void Function(AiOrganizeStatus status) onStatus,
    AiOrganizeSettings settings = const AiOrganizeSettings(),
    String? Function()? modelName,
    Duration noteQuietPeriod = kAiNoteQuietPeriod,
    LongWorkKeeper longWork = const NoLongWorkKeeper(),
    void Function(AiFlashcardsBatch? batch)? onFlashcardsBatch,
    void Function(AiDatesBatch? batch)? onDatesBatch,
    Duration modelRetryDelay = kAiModelRetryDelay,
    AiTaskTracker? tasks,
    OrganizeTextReader texts = const OwnTextReader(),
  }) : _backlog = backlog,
       _runs = runs,
       _library = library,
       _steps = steps,
       _languageModel = languageModel,
       _modelRetryDelay = modelRetryDelay,
       _embeddingModel = embeddingModel,
       _vectors = vectors,
       _charging = charging,
       _epoch = epoch,
       _telemetry = telemetry,
       _clock = clock,
       _onStatus = onStatus,
       _settings = settings,
       _modelName = modelName,
       _noteQuietPeriod = noteQuietPeriod,
       _longWork = longWork,
       _onFlashcardsBatch = onFlashcardsBatch,
       _onDatesBatch = onDatesBatch,
       _tasks = tasks,
       _texts = texts;

  final AiOrganizeBacklog _backlog;
  final AiRunRepository _runs;
  final LibraryRepository _library;

  /// El texto que se lee de cada elemento: de una nota, sus formas; de un
  /// documento procesado, sus partes (F41, paso 6). Con él se toma la huella
  /// que dice si una nota cambió lo suficiente.
  final OrganizeTextReader _texts;

  /// Se piden al usarlos, no al nacer: armar los pasos arma la cadena de
  /// proveedores del modelo, y la cola vive toda la sesión.
  final List<AiOrganizeStep> Function() _steps;

  /// También al usarlos: elegir otro proveedor o bajar otro Gemma cambia lo
  /// que contesta. El de lenguaje se pregunta como IA de fondo, con su tope
  /// del día (F32).
  final LanguageModelStatusCheck Function() _languageModel;
  final EmbeddingModelManager Function() _embeddingModel;

  /// Ver [kAiModelRetryDelay].
  final Duration _modelRetryDelay;

  /// Lo que se cortó porque el modelo dejó de contestar a mitad (F32): se
  /// retoma primero, en la misma pasada.
  _Interrupted? _interrupted;

  /// Por qué y hasta cuándo esperar al modelo por algo que el chequeo no ve
  /// —sin conexión, el proveedor saturado, el modelo ya no existe— (F32).
  /// Sin `until`, hasta que cambie lo elegido ([languageModelChanged]).
  ({AiModelWait reason, DateTime? until})? _modelHeld;

  /// La despierta cuando vuelve la cuota o termina la espera (F32).
  Timer? _resumeTimer;

  /// Con qué se ponen al día los vectores de una nota que cambió poco: los
  /// necesita para ser destino de los vínculos de otros elementos.
  final ChunkEmbeddingIndexer Function() _vectors;
  final ChargingProbe _charging;
  final AiOrganizeEpoch _epoch;
  final TelemetryService _telemetry;
  final Clock _clock;
  final void Function(AiOrganizeStatus status) _onStatus;

  /// Qué modelo trabaja, para la pasada; al usarlo, por lo mismo.
  final String? Function()? _modelName;
  final Duration _noteQuietPeriod;

  AiOrganizeSettings _settings;

  /// El servicio en primer plano, del lado de la IA (ver la clase).
  final LongWorkKeeper _longWork;

  /// Lo que la IA está haciendo ahora (F39, paso 6): cada elemento que la cola
  /// toma es una tarea, con sus pasos, el modelo y los tokens que gasta. Sin
  /// él —las pruebas que no lo miran—, la cola trabaja igual.
  final AiTaskTracker? _tasks;

  /// Si la cola lo tiene pedido ahora, y cuántos organizó desde que lo
  /// pidió: el avance de la notificación.
  var _keepingAlive = false;
  var _organizedWhileKept = 0;

  /// Lo que se pidió organizar a mano, en orden.
  final _requested = Queue<String>();

  /// Los elementos de los que se pidieron solo tarjetas (F30), en orden, y
  /// los que pidieron otra tanda aunque ya tengan.
  final _cardRequests = Queue<String>();
  final _anotherBatch = <String>{};

  /// Cómo va el pedido de tarjetas, o `null` si no hay ninguno a la vista.
  AiFlashcardsBatch? _batch;

  /// Cuál pedido es: cambia con cada pedido nuevo y al cancelar.
  var _batchSerial = 0;
  var _cardsPaused = false;
  final void Function(AiFlashcardsBatch? batch)? _onFlashcardsBatch;

  /// Los elementos de los que se pidieron solo las fechas (F40), en orden.
  final _dateRequests = Queue<String>();

  /// Cómo va el pedido de fechas, o `null` si no hay ninguno a la vista, y
  /// cuál pedido es: cambia con cada pedido nuevo y al cancelar.
  AiDatesBatch? _datesBatch;
  var _datesSerial = 0;
  final void Function(AiDatesBatch? batch)? _onDatesBatch;

  /// Lo que no se pudo ni empezar en esta sesión —el elemento no se pudo
  /// leer, la pasada no se pudo abrir—: no se vuelve a intentar hasta la
  /// próxima, para no girar en vacío sobre lo mismo.
  final _skip = <String>{};

  /// Las notas que cambiaron pero no lo suficiente, con el momento del
  /// cambio que ya se miró: no se vuelven a mirar hasta que cambien de nuevo.
  final _noteChangesSeen = <String, DateTime>{};

  StreamSubscription<bool>? _chargingWatch;
  StreamSubscription<DateTime?>? _noteWatch;
  Timer? _noteTimer;

  /// La vuelta en curso, o la última. [_running] dice si sigue: se apaga
  /// dentro de la misma vuelta, sin nada en el medio desde que decidió que
  /// no queda nada —con un `whenComplete` aparte, un aviso que llegara justo
  /// entre las dos cosas se perdía—.
  Future<void> _draining = Future.value();
  var _running = false;
  var _wakeAgain = false;
  var _started = false;
  var _disposed = false;

  /// Arranca: escucha el cargador y las notas, y retoma lo pendiente. Se
  /// puede llamar más de una vez; las siguientes solo la despiertan.
  Future<void> start() {
    if (!_started && !_disposed) {
      _started = true;
      _chargingWatch = _charging.watchCharging().listen((charging) {
        if (charging) unawaited(wake());
      }, onError: (Object _) {});
      _noteWatch = _backlog.watchLastNoteEdit().listen(
        _noteEdited,
        onError: (Object _) {},
      );
    }
    return wake();
  }

  /// Se guardó una nota a las [lastEdit]: se mira cuando lleve
  /// [_noteQuietPeriod] quieta. La primera emisión —la última nota guardada
  /// antes de arrancar— también pasa por acá, porque no hay forma de saber
  /// si un guardado mientras arrancaba llegó antes o después; si ya está
  /// quieta, se mira en el acto, sin dejar un temporizador colgado.
  void _noteEdited(DateTime? lastEdit) {
    if (_disposed || lastEdit == null) return;
    _noteTimer?.cancel();
    final wait = lastEdit
        .add(_noteQuietPeriod + _noteSettleMargin)
        .difference(_clock());
    if (wait <= Duration.zero) {
      _noteTimer = null;
      unawaited(wake());
    } else {
      _noteTimer = Timer(wait, wake);
    }
  }

  /// Un poco más que el período de quietud: la nota tiene que haber estado
  /// quieta ESE tiempo cuando se mira, no casi.
  static const _noteSettleMargin = Duration(seconds: 1);

  /// La persona terminó de triar —o de volver a triar— una fuente, y su
  /// documento procesado [documentId] quedó como lo eligió (F41, paso 6): la IA
  /// lo organiza ahora, antes que lo nuevo, con los mismos interruptores de
  /// siempre —temas, vínculos con otros procesados, fechas para la línea de
  /// tiempo— y solo con lo elegido.
  ///
  /// Es el único punto para eso, y lo llama `TriageIntoProcessed` —triar en la
  /// Bandeja, pasar sin modificar y «Volver a triar»— cada vez que el triado
  /// cambió algo. Sin llamarlo, un procesado nuevo igual se organiza solo —es
  /// una nota, y la cola toma lo nuevo de la base cuando lleva
  /// [kAiNoteQuietPeriod] quieto—, y uno que cambió mucho también; esto es lo
  /// que hace que volver a triar con algo chico —un fragmento con una fecha—
  /// no espere a que el cambio sea grande. Es una pasada nueva: lo que ya
  /// estaba no se repite, y deshacerla saca solo lo que ella puso.
  void enqueueProcessedForOrganizing(String documentId) =>
      organizeAllNow([documentId]);

  /// Organiza [itemId] ahora, antes que lo demás, aunque su pasada anterior
  /// se haya deshecho o sea de la biblioteca que ya existía y el teléfono no
  /// esté cargando: lo pidió la persona. Sigue respetando la pausa y los
  /// modelos.
  void organizeNow(String itemId) => organizeAllNow([itemId]);

  /// [organizeNow] para varios a la vez, en ese orden: lo que pide el Mapa
  /// para lo que quedó sin tema (F28). Pueden ser miles: lo ya pedido se
  /// mira en un conjunto, no recorriendo la cola por cada uno, y la cola se
  /// despierta una sola vez.
  void organizeAllNow(Iterable<String> itemIds) {
    final pending = _requested.toSet();
    // El que se cortó a mitad ya está primero, en su pasada.
    final interrupted = _interrupted;
    if (interrupted != null && !interrupted.source.isRequestLane) {
      pending.add(interrupted.itemId);
    }
    for (final itemId in itemIds) {
      _skip.remove(itemId);
      if (pending.add(itemId)) _requested.add(itemId);
    }
    unawaited(wake());
  }

  /// Hace **solo las tarjetas** de [itemIds] (F30, el ✨ de Repasar), en ese
  /// orden, después de lo pedido a mano y antes que lo nuevo: sin vínculos,
  /// temas ni etiquetas, y **sin esperar el cargador**, aunque sean de la
  /// biblioteca que ya existía. Solo necesita el modelo de lenguaje, y no
  /// mira los interruptores de cada tipo —lo pidió la persona—; la pausa
  /// general de la IA, sí.
  ///
  /// Con [anotherBatch], los que ya tienen tarjetas suman otra tanda
  /// (`AiFlashcardMaker`). Cada elemento es una pasada de solo tarjetas
  /// (`AiRunRepository.startRun`), que se deshace como cualquiera y no cuenta
  /// como organizarlo. Si ya había un pedido en curso, estos se le suman.
  void makeFlashcards(Iterable<String> itemIds, {bool anotherBatch = false}) {
    final queued = _cardRequests.toSet();
    final interrupted = _interrupted;
    if (interrupted != null &&
        interrupted.source == AiWorkSource.flashcardsRequest) {
      queued.add(interrupted.itemId);
    }
    var added = 0;
    for (final itemId in itemIds) {
      _skip.remove(itemId);
      if (!queued.add(itemId)) continue;
      _cardRequests.add(itemId);
      if (anotherBatch) _anotherBatch.add(itemId);
      added++;
    }
    if (added == 0) return;
    final batch = _batch;
    if (batch == null || batch.finished) {
      _batchSerial++;
      _publishBatch(AiFlashcardsBatch(total: added, paused: _cardsPaused));
    } else {
      _publishBatch(batch.copyWith(total: batch.total + added));
    }
    unawaited(wake());
  }

  /// Pausa el pedido de tarjetas: lo que está en curso termina —una llamada
  /// al modelo no se corta a mitad— y no se toma otro hasta [resumeFlashcards].
  /// El resto de la IA sigue.
  void pauseFlashcards() {
    _cardsPaused = true;
    final batch = _batch;
    if (batch != null) _publishBatch(batch.copyWith(paused: true));
  }

  void resumeFlashcards() {
    _cardsPaused = false;
    final batch = _batch;
    if (batch != null) _publishBatch(batch.copyWith(paused: false));
    unawaited(wake());
  }

  /// Cancela lo que falta del pedido de tarjetas. Lo que ya se hizo queda,
  /// con su pasada, y se deshace desde «Lo que hizo la IA».
  void cancelFlashcards() {
    _cardRequests.clear();
    _anotherBatch.clear();
    _cardsPaused = false;
    _batchSerial++;
    _publishBatch(null);
    // Uno que se cortó esperando al modelo (F32) también se cancela: su
    // pasada se cierra con lo que alcanzó a hacer.
    final interrupted = _interrupted;
    if (interrupted != null &&
        interrupted.source == AiWorkSource.flashcardsRequest) {
      _interrupted = null;
      unawaited(_closeRun(interrupted.runId, 'de tarjetas cancelada'));
    }
  }

  /// Busca **solo las fechas** de [itemIds] para la línea de tiempo (F40), en
  /// ese orden, después de lo pedido a mano y de las tarjetas y antes que lo
  /// nuevo: sin vínculos, tarjetas, temas ni etiquetas, y **sin esperar el
  /// cargador**, aunque sean de la biblioteca que ya existía. Solo necesita el
  /// modelo de lenguaje, y no mira el interruptor de las fechas —lo pidió la
  /// persona—; la pausa general de la IA, sí.
  ///
  /// Cada elemento es una pasada de solo fechas (`AiRunScope.dates`), que se
  /// deshace como cualquiera y no cuenta como organizarlo. Si ya había un
  /// pedido en curso, estos se le suman.
  void findDates(Iterable<String> itemIds) {
    final queued = _dateRequests.toSet();
    final interrupted = _interrupted;
    if (interrupted != null &&
        interrupted.source == AiWorkSource.datesRequest) {
      queued.add(interrupted.itemId);
    }
    var added = 0;
    for (final itemId in itemIds) {
      if (!queued.add(itemId)) continue;
      _dateRequests.add(itemId);
      added++;
    }
    if (added == 0) return;
    final batch = _datesBatch;
    if (batch == null || batch.finished) {
      _datesSerial++;
      _publishDates(AiDatesBatch(total: added));
    } else {
      _publishDates(batch.copyWith(total: batch.total + added));
    }
    unawaited(wake());
  }

  /// Cancela lo que falta del pedido de fechas. Lo que ya se puso queda, con
  /// su pasada, y se deshace desde «Lo que hizo la IA».
  void cancelDates() {
    _dateRequests.clear();
    _publishDates(null);
    // Uno que se cortó esperando al modelo (F32) también se cancela: su pasada
    // se cierra con lo que alcanzó a hacer.
    final interrupted = _interrupted;
    if (interrupted != null &&
        interrupted.source == AiWorkSource.datesRequest) {
      _interrupted = null;
      unawaited(_closeRun(interrupted.runId, 'de fechas cancelada'));
    }
  }

  /// Saca de la vista un pedido de fechas que ya terminó.
  void dismissDates() {
    if (_datesBatch?.finished ?? true) _publishDates(null);
  }

  void _publishDates(AiDatesBatch? batch) {
    _datesBatch = batch;
    _onDatesBatch?.call(batch);
  }

  /// Cierra una pasada; si no se puede, lo registra.
  Future<void> _closeRun(String runId, String what) async {
    (await _runs.finishRun(runId)).match(
      (failure) => _telemetry.recordError(
        failure,
        StackTrace.current,
        hint: 'AiOrganizeQueue: no se pudo cerrar la pasada $what',
      ),
      (_) {},
    );
  }

  /// Saca de la vista un pedido de tarjetas que ya terminó.
  void dismissFlashcards() {
    if (_batch?.finished ?? true) _publishBatch(null);
  }

  void _publishBatch(AiFlashcardsBatch? batch) {
    _batch = batch;
    _onFlashcardsBatch?.call(batch);
  }

  /// Los interruptores cambiaron. Prender la IA la despierta; apagar un tipo
  /// vale desde el próximo paso.
  void updateSettings(AiOrganizeSettings settings) {
    _settings = settings;
    unawaited(wake());
  }

  /// Cambió el modelo de lenguaje elegido, sus cuentas o su modelo (F32): lo
  /// que se esperaba —una conexión, un modelo que ya no existía— puede estar
  /// resuelto. Se vuelve a mirar ahora.
  void languageModelChanged() {
    _modelHeld = null;
    unawaited(wake());
  }

  /// Revisa si hay algo para hacer. Lo usan los avisos de arriba, y también
  /// sirve después de bajar un modelo. Completa cuando la cola queda sin nada
  /// que pueda hacer ahora.
  Future<void> wake() {
    if (_disposed) return Future.value();
    if (_running) {
      _wakeAgain = true;
      return _draining;
    }
    _running = true;
    return _draining = _drain();
  }

  /// Deja de escuchar. Lo que esté en curso termina, pero no se toma nada más.
  Future<void> dispose() async {
    _disposed = true;
    _noteTimer?.cancel();
    _resumeTimer?.cancel();
    _letGo();
    // Las dos bajas se piden juntas, antes de esperar ninguna: un aviso que
    // llegara entre una y otra encontraría la cola descartada y no haría nada,
    // pero así ni siquiera llega.
    await Future.wait([?_chargingWatch?.cancel(), ?_noteWatch?.cancel()]);
  }

  /// Cuándo queda quieta la cola: para las pruebas.
  @visibleForTesting
  Future<void> get settled => _draining;

  Future<void> _drain() async {
    try {
      while (!_disposed) {
        _wakeAgain = false;
        final next = await _next();
        if (next != null) {
          final finished = await switch (next.source) {
            AiWorkSource.flashcardsRequest => _makeFlashcards(
              next.itemId,
              resume: next.resume,
            ),
            AiWorkSource.datesRequest => _findDates(
              next.itemId,
              resume: next.resume,
            ),
            _ => _organize(next.itemId, next.source, resume: next.resume),
          };
          // Uno que se cortó esperando al modelo no está hecho.
          if (finished) _organizedWhileKept++;
          continue;
        }
        // Nada que pueda hacer ahora: terminó, se pausó, falta el cargador o
        // un modelo, o se espera al de la nube. El servicio se suelta.
        _letGo();
        if (!_wakeAgain) break;
      }
      // Ningún error de una consulta puede dejar la cola trabada en
      // «trabajando»: se registra y se espera el próximo aviso.
    } on Object catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'AiOrganizeQueue._drain');
      _onStatus(const AiOrganizeIdle());
      _letGo();
    } finally {
      _running = false;
    }
  }

  /// El próximo elemento por organizar y de dónde salió, o `null` si no hay
  /// nada que se pueda hacer ahora; en ese caso deja publicado por qué.
  Future<_Next?> _next() async {
    final epoch = await _epoch();
    final quietBefore = _clock().subtract(_noteQuietPeriod);

    if (!_settings.enabled) {
      _onStatus(AiOrganizePaused(pending: await _pending(epoch, quietBefore)));
      return null;
    }
    final interrupted = _interrupted;
    final cardsInterrupted =
        interrupted?.source == AiWorkSource.flashcardsRequest;
    // Las tarjetas que pidió la persona (F30) no dependen de los
    // interruptores de cada tipo ni del modelo de vínculos.
    final cardsWaiting =
        (_cardRequests.isNotEmpty || cardsInterrupted) && !_cardsPaused;
    // Y las fechas que pidió la persona para la línea de tiempo (F40), por lo
    // mismo.
    final datesWaiting =
        _dateRequests.isNotEmpty ||
        interrupted?.source == AiWorkSource.datesRequest;
    final requestsWaiting = cardsWaiting || datesWaiting;
    if (!_anyStepOn && !requestsWaiting) {
      _onStatus(const AiOrganizeIdle());
      return null;
    }
    // Lo hace la IA de fondo: con su tope del día (F32).
    final language = await _languageModel()(background: true);
    final held = _stillHeld();
    final chatReady = language.isReady && held == null;
    final embeddingReady = await _embeddingModel().isReady();
    final canOrganize = _anyStepOn && chatReady && embeddingReady;
    if (!canOrganize && !(requestsWaiting && chatReady)) {
      _onStatus(
        await _notReady(
          language,
          held: held,
          chatReady: chatReady,
          embeddingReady: embeddingReady,
          pending: () => _pending(epoch, quietBefore),
        ),
      );
      return null;
    }

    // Lo que se cortó esperando al modelo, primero y en su pasada (F32).
    if (interrupted != null &&
        switch (interrupted.source) {
          AiWorkSource.flashcardsRequest => cardsWaiting,
          AiWorkSource.datesRequest => datesWaiting,
          _ => canOrganize,
        }) {
      _interrupted = null;
      return (
        itemId: interrupted.itemId,
        source: interrupted.source,
        resume: interrupted,
      );
    }
    if (canOrganize && _requested.isNotEmpty) {
      return (
        itemId: _requested.removeFirst(),
        source: AiWorkSource.requested,
        resume: null,
      );
    }
    if (cardsWaiting && _cardRequests.isNotEmpty) {
      return (
        itemId: _cardRequests.removeFirst(),
        source: AiWorkSource.flashcardsRequest,
        resume: null,
      );
    }
    if (datesWaiting && _dateRequests.isNotEmpty) {
      return (
        itemId: _dateRequests.removeFirst(),
        source: AiWorkSource.datesRequest,
        resume: null,
      );
    }
    // Con la IA de vínculos sin poder trabajar, lo de abajo espera: solo se
    // llegó hasta acá por tarjetas o fechas, y ya no quedan.
    if (!canOrganize) {
      _onStatus(const AiOrganizeIdle());
      return null;
    }

    final fresh = await _backlog.nextFresh(
      since: epoch,
      notesQuietBefore: quietBefore,
      skip: _skip,
    );
    if (fresh != null) {
      return (itemId: fresh, source: AiWorkSource.fresh, resume: null);
    }

    final grown = await _grownNote(quietBefore);
    if (grown != null) {
      return (itemId: grown, source: AiWorkSource.changedNote, resume: null);
    }

    if (_settings.backfillWhileCharging) {
      final existing = await _backlog.nextExisting(
        before: epoch,
        notesQuietBefore: quietBefore,
        skip: _skip,
      );
      if (existing != null) {
        if (await _charging.isCharging()) {
          return (
            itemId: existing,
            source: AiWorkSource.existingLibrary,
            resume: null,
          );
        }
        _onStatus(
          AiOrganizePaused(
            pending: (await _backlog.count(
              epoch: epoch,
              notesQuietBefore: quietBefore,
            )).existing,
            waitingForCharger: true,
          ),
        );
        return null;
      }
    }

    _onStatus(const AiOrganizeIdle());
    return null;
  }

  bool get _anyStepOn => _steps().any((s) => s.toggle.valueIn(_settings));

  /// La espera por algo que el chequeo no ve, si sigue en pie; la que ya
  /// pasó se olvida.
  ({AiModelWait reason, DateTime? until})? _stillHeld() {
    final held = _modelHeld;
    final until = held?.until;
    if (held == null || until == null) return held;
    if (_clock().isBefore(until)) return held;
    _modelHeld = null;
    return null;
  }

  /// Por qué no puede trabajar ahora: falta un modelo —bajarlo, o una clave
  /// del que está en la nube— o se espera al de la nube (F32). Lo que vuelve
  /// solo deja la cola lista para despertarse a esa hora.
  Future<AiOrganizeStatus> _notReady(
    LanguageModelStatus language, {
    required ({AiModelWait reason, DateTime? until})? held,
    required bool chatReady,
    required bool embeddingReady,
    required Future<int> Function() pending,
  }) async {
    final chatMissing = switch (language) {
      LanguageModelNeedsDownload() || LanguageModelNeedsAccount() => true,
      _ => false,
    };
    if (chatMissing || !embeddingReady) {
      return AiOrganizeModelMissing(
        chatModelMissing: chatMissing,
        embeddingModelMissing: !embeddingReady,
        keyFor: language is LanguageModelNeedsAccount
            ? language.provider
            : null,
      );
    }
    if (chatReady) return const AiOrganizeIdle();

    final (reason, resumesAt, cap) = switch (language) {
      LanguageModelOutOfQuota(keysRejected: true) => (
        AiModelWait.keysRejected,
        null,
        null,
      ),
      LanguageModelOutOfQuota(:final resetsAt) => (
        AiModelWait.quota,
        resetsAt,
        null,
      ),
      LanguageModelBackgroundCapReached(:final cap, :final resetsAt) => (
        AiModelWait.backgroundCap,
        resetsAt,
        cap,
      ),
      // Listo para el chequeo, pero se espera por algo que no ve.
      _ => (held!.reason, held.until, null),
    };
    // Se despierta con lo primero que vuelva: la cuota, o el fin de la
    // espera que el chequeo no ve.
    _wakeAt([?resumesAt, ?held?.until].fold<DateTime?>(null, _earliest));
    return AiOrganizeWaitingForModel(
      reason: reason,
      pending: await pending(),
      resumesAt: resumesAt ?? held?.until,
      cap: cap,
    );
  }

  static DateTime? _earliest(DateTime? a, DateTime b) =>
      a == null || b.isBefore(a) ? b : a;

  /// Despierta la cola a las [at] —con un segundo de margen, para que el
  /// chequeo ya vea lo que volvió—; sin hora, no la despierta nada de acá.
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

  /// El modelo dejó de contestar por [wait] (F32). Lo que el chequeo ve
  /// —la cuota, el tope, las claves— lo vuelve a decir él; igual se espera un
  /// rato antes de volver a probar, para no girar sobre lo mismo si el
  /// chequeo todavía no se enteró.
  void _hold(AiModelWait wait, Object error) {
    final retryAfter = error is CloudModelException ? error.retryAfter : null;
    _modelHeld = (
      reason: wait,
      until: wait == AiModelWait.modelGone
          ? null
          : _clock().add(retryAfter ?? _modelRetryDelay),
    );
  }

  /// Una nota ya organizada cuyo contenido cambió lo suficiente: su huella
  /// de hoy contra la del texto que vio su última pasada. Reescribirla sin
  /// cambiarle el largo cuenta; una coma, no.
  Future<String?> _grownNote(DateTime quietBefore) async {
    for (final edited in await _backlog.editedNotes(quietBefore: quietBefore)) {
      if (_skip.contains(edited.itemId)) continue;
      if (_noteChangesSeen[edited.itemId] == edited.updatedAt) continue;
      _noteChangesSeen[edited.itemId] = edited.updatedAt;

      final seen = edited.simhashSeen;
      // Sin saber cómo era —una pasada de antes de v35—, no se supone que
      // cambió: volver a organizar es más tarjetas y vínculos.
      if (seen == null) continue;
      final note = await _find(edited.itemId);
      if (note == null) continue;
      final text = (await _texts.textOf(note)).text;
      if (contentChangedMuch(seen, await _simhashOf(text))) {
        return edited.itemId;
      }
      await _refreshNoteVectors(edited.itemId);
    }
    return null;
  }

  /// Una nota que cambió poco no se reorganiza, pero sus vectores sí se
  /// ponen al día (F27): son lo que la hace destino de los vínculos que la IA
  /// busca para otros elementos, y tienen que describir su texto de hoy. Solo
  /// se recalculan los tramos que cambiaron. Un fallo se registra y no frena
  /// la cola: la nota sigue con los vectores de antes.
  Future<void> _refreshNoteVectors(String itemId) async {
    try {
      await _vectors().indexNote(itemId);
      // El modelo de vectores es de terceros: falla de formas sin un tipo
      // propio.
    } on Object catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'AiOrganizeQueue: vectores de la nota $itemId',
      );
    }
  }

  /// La huella de [text], fuera del hilo de la interfaz: es una cuenta por
  /// cada trío de palabras, y una nota larga tiene miles.
  static Future<String> _simhashOf(String text) =>
      compute(contentSimhashOf, text);

  /// Cuántos esperan: los nuevos, lo pedido a mano y —si se recorre— la
  /// biblioteca que ya existía.
  Future<int> _pending(DateTime epoch, DateTime quietBefore) async {
    final count = await _backlog.count(
      epoch: epoch,
      notesQuietBefore: quietBefore,
    );
    // El que se cortó a mitad, si no lo cuenta ya la base: lo nuevo y la
    // biblioteca existente siguen pendientes ahí mientras su pasada esté
    // abierta.
    final interrupted = switch (_interrupted?.source) {
      AiWorkSource.requested ||
      AiWorkSource.changedNote ||
      AiWorkSource.flashcardsRequest ||
      AiWorkSource.datesRequest => 1,
      _ => 0,
    };
    return _requested.length +
        _cardRequests.length +
        _dateRequests.length +
        interrupted +
        count.fresh +
        (_settings.backfillWhileCharging ? count.existing : 0);
  }

  /// Organiza [itemId] con los pasos prendidos, o —con [resume]— retoma la
  /// pasada que se cortó esperando al modelo, sin los pasos que ya terminó.
  /// Devuelve `false` si se volvió a cortar (F32): no está hecho.
  Future<bool> _organize(
    String itemId,
    AiWorkSource source, {
    _Interrupted? resume,
  }) async {
    final item = await _find(itemId);
    // Una fuente de la Biblioteca no se organiza (F41, paso 6): ver la clase.
    if (item == null || !_isNote(item)) {
      _skip.add(itemId);
      if (resume != null) await _closeRun(resume.runId, 'de un elemento ido');
      return true;
    }

    final epoch = await _epoch();
    final quietBefore = _clock().subtract(_noteQuietPeriod);
    // Este ya no espera.
    final pending = math.max(0, await _pending(epoch, quietBefore) - 1);
    _onStatus(
      AiOrganizeWorking(
        itemTitle: item.title,
        source: source,
        pending: pending,
      ),
    );
    _keepAlive(source, pending);

    final text = await _texts.textOf(item);
    final String runId;
    if (resume != null) {
      runId = resume.runId;
    } else {
      // La huella del texto que ve esta pasada, para saber después si la
      // nota —o el documento procesado— cambió.
      final simhash = await _simhashOf(text.text);
      final started =
          (await _runs.startRun(
            item.id,
            model: _modelName?.call(),
            contentSimhash: simhash,
          )).fold((failure) {
            _skip.add(item.id);
            _telemetry.recordError(
              failure,
              StackTrace.current,
              hint: 'AiOrganizeQueue: no se pudo abrir la pasada',
            );
            return null;
          }, (id) => id);
      if (started == null) return true;
      runId = started;
    }

    final done = <AiOrganizeToggle>{...?resume?.done};
    final steps = [
      for (final step in _steps())
        if (step.toggle.valueIn(_settings) && _appliesTo(step, text)) step,
    ];
    final task = _beginTask(AiTaskKind.organize, item, steps: steps);
    final usage = AiRunUsageSaver(
      runs: _runs,
      telemetry: _telemetry,
      runId: runId,
      task: task,
      hint: 'AiOrganizeQueue',
    );
    try {
      for (final step in steps) {
        // Cada paso mira su interruptor al empezar: apagar un tipo a mitad de
        // un elemento vale desde el paso siguiente.
        if (!step.toggle.valueIn(_settings)) continue;
        if (done.contains(step.toggle)) continue;
        final stepKind = step.toggle.taskStep;
        if (stepKind != null) task?.step(stepKind);
        try {
          await _within(task, () => step.organize(item, runId: runId));
          // Un paso que falla no corta la pasada: lo que ya creó queda, con su
          // pasada, y los demás pasos se hacen igual. Se atrapa todo —el modelo
          // es de terceros y falla de formas sin un tipo propio— y se
          // registra.
        } on Object catch (e, stackTrace) {
          // Salvo que el modelo no pueda contestar por ahora (F32): seguir
          // sería cerrar la pasada sin lo que faltaba. Se corta acá, abierta,
          // y se retoma en este paso cuando vuelva.
          final wait = aiModelWaitFor(e);
          if (wait != null) {
            _hold(wait, e);
            _interrupted = (
              itemId: item.id,
              source: source,
              runId: runId,
              done: done,
              anotherBatch: false,
            );
            return false;
          }
          _telemetry.recordError(
            e,
            stackTrace,
            hint: 'AiOrganizeQueue: ${step.toggle.name} en ${item.id}',
          );
        }
        done.add(step.toggle);
      }

      // Lo que costó, antes de cerrar la pasada: quien la lee al cerrarse ya
      // lo encuentra.
      await usage.save();
      (await _runs.finishRun(runId)).match((failure) {
        // Sin cerrar, la pasada cuenta como a medias y se retomaría: en esta
        // sesión no, para no repetirla en el acto.
        _skip.add(item.id);
        _telemetry.recordError(
          failure,
          StackTrace.current,
          hint: 'AiOrganizeQueue: no se pudo cerrar la pasada',
        );
      }, (_) {});
      return true;
    } finally {
      // También si se cortó esperando al modelo: lo que gastó hasta ahí es
      // suyo, y al retomar se suma lo que falte.
      await usage.save();
      usage.end();
    }
  }

  /// Si [step] tiene algo que hacer con un elemento de texto [text]: las fechas
  /// son para la línea de tiempo, que se arma solo con lo procesado (F41, paso
  /// 6), así que de una nota de la persona no se buscan —no se verían—.
  static bool _appliesTo(AiOrganizeStep step, OrganizeText text) =>
      step.toggle != AiOrganizeToggle.dates || text.processed;

  /// Abre la tarea de [item] para «Lo que hizo la IA» (F39, paso 6), con los
  /// pasos que hace. Una pasada retomada salta los que ya hizo, y los pasos de
  /// antes del que va se ven hechos. `null` si la cola no lleva la cuenta.
  AiTaskHandle? _beginTask(
    AiTaskKind kind,
    KnowledgeItem item, {
    required List<AiOrganizeStep> steps,
  }) => _tasks?.begin(
    kind: kind,
    title: item.title,
    itemId: item.id,
    model: _modelName?.call(),
    steps: [for (final step in steps) ?step.toggle.taskStep],
  );

  /// Corre [body] como parte de [task]: lo que el modelo conteste adentro se
  /// le anota. Sin tarea, corre solo.
  static Future<T> _within<T>(AiTaskHandle? task, Future<T> Function() body) =>
      task == null ? body() : task.run(body);

  /// Solo las tarjetas de [itemId] (F30): una pasada de solo tarjetas, con
  /// el paso de tarjetas como `AiFlashcardMaker`. Un fallo se registra y el
  /// pedido sigue con el próximo; el elemento cuenta como mirado igual.
  ///
  /// Salvo que el modelo no pueda contestar por ahora (F32): entonces no
  /// cuenta, la pasada queda abierta y se retoma primero —con [resume]—
  /// cuando vuelva. Devuelve `false` en ese caso.
  Future<bool> _makeFlashcards(String itemId, {_Interrupted? resume}) async {
    // De qué pedido es: si lo cancelan y piden otro mientras este corre, lo
    // que dé no se le suma al nuevo.
    final batchOf = _batchSerial;
    final anotherBatch = resume?.anotherBatch ?? _anotherBatch.remove(itemId);
    var report = AiStepReport.nothing;
    var waiting = false;
    // Pase lo que pase —salvo esperar al modelo—, el elemento cuenta como
    // mirado: un pedido que no llega nunca al final se quedaría «creando
    // tarjetas» para siempre.
    try {
      final item = await _find(itemId);
      final maker = _steps().whereType<AiFlashcardMaker>().firstOrNull;
      if (item == null || maker == null) {
        if (resume != null) {
          await _closeRun(resume.runId, 'de tarjetas de un elemento ido');
        }
        return true;
      }

      final epoch = await _epoch();
      final quietBefore = _clock().subtract(_noteQuietPeriod);
      final pending = math.max(0, await _pending(epoch, quietBefore));
      final batch = _batch;
      if (batch != null && batchOf == _batchSerial) {
        _publishBatch(batch.copyWith(currentTitle: () => item.title));
      }
      _onStatus(
        AiOrganizeWorking(
          itemTitle: item.title,
          source: AiWorkSource.flashcardsRequest,
          pending: pending,
        ),
      );
      _keepAlive(AiWorkSource.flashcardsRequest, pending);

      final runId =
          resume?.runId ??
          (await _runs.startRun(
            item.id,
            model: _modelName?.call(),
            scope: AiRunScope.flashcards,
          )).fold((failure) {
            _telemetry.recordError(
              failure,
              StackTrace.current,
              hint: 'AiOrganizeQueue: no se pudo abrir la pasada de tarjetas',
            );
            return null;
          }, (id) => id);
      if (runId == null) return true;

      // La tarea de «Lo que hizo la IA» (F39, paso 6): un paso, y cuánto va
      // del pedido entero.
      final batchNow = _batch;
      final task = _tasks?.begin(
        kind: AiTaskKind.flashcards,
        title: item.title,
        itemId: item.id,
        model: _modelName?.call(),
        steps: const [AiTaskStepKind.organizeFlashcards],
        batchProgress: batchNow != null && batchOf == _batchSerial
            ? AiTaskProgress(
                done: batchNow.done,
                total: batchNow.total,
                unit: AiTaskUnit.item,
              )
            : null,
      );
      task?.step(AiTaskStepKind.organizeFlashcards);
      final usage = AiRunUsageSaver(
        runs: _runs,
        telemetry: _telemetry,
        runId: runId,
        task: task,
        hint: 'AiOrganizeQueue',
      );
      try {
        report = await _within(
          task,
          () => maker.makeFlashcards(
            item,
            runId: runId,
            anotherBatch: anotherBatch,
          ),
        );
        // Como un paso de la pasada entera: el modelo es de terceros y falla
        // de formas sin un tipo propio. Lo que ya creó queda, con su pasada.
      } on Object catch (e, stackTrace) {
        final wait = aiModelWaitFor(e);
        if (wait != null) {
          // Lo que alcanzó a hacer queda; lo que falta lo completa al
          // retomar, que cuenta las que ya tiene.
          waiting = true;
          _hold(wait, e);
          _interrupted = (
            itemId: item.id,
            source: AiWorkSource.flashcardsRequest,
            runId: runId,
            done: const <AiOrganizeToggle>{},
            anotherBatch: anotherBatch,
          );
          final current = _batch;
          if (current != null && batchOf == _batchSerial) {
            _publishBatch(current.copyWith(currentTitle: () => null));
          }
          return false;
        }
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'AiOrganizeQueue: tarjetas en ${item.id}',
        );
      } finally {
        // Lo que costó, antes de cerrar la pasada y también si se cortó
        // esperando al modelo.
        await usage.save();
        // Cortada, la pasada queda abierta y no se cierra acá: la tarea sí.
        if (waiting) usage.end();
      }
      await _closeRun(runId, 'de tarjetas');
      usage.end();
      return true;
    } finally {
      if (batchOf == _batchSerial && !waiting) _cardDone(report);
    }
  }

  /// Solo las fechas de [itemId] (F40): una pasada de solo fechas, con el paso
  /// de fechas como `AiDatesFinder`. Un fallo se registra y el pedido sigue
  /// con el próximo; el elemento cuenta como mirado igual.
  ///
  /// Salvo que el modelo no pueda contestar por ahora (F32): entonces no
  /// cuenta, la pasada queda abierta y se retoma primero —con [resume]— cuando
  /// vuelva, desde el pasaje donde quedó. Devuelve `false` en ese caso.
  Future<bool> _findDates(String itemId, {_Interrupted? resume}) async {
    // De qué pedido es: si lo cancelan y piden otro mientras este corre, lo
    // que dé no se le suma al nuevo.
    final batchOf = _datesSerial;
    var report = AiStepReport.nothing;
    var waiting = false;
    // Pase lo que pase —salvo esperar al modelo—, el elemento cuenta como
    // mirado: un pedido que no llega nunca al final se quedaría «buscando
    // fechas» para siempre.
    try {
      final item = await _find(itemId);
      final finder = _steps().whereType<AiDatesFinder>().firstOrNull;
      // La línea de tiempo se arma solo con lo procesado (F41, paso 6): las
      // fechas de una fuente, o de una nota de la persona, no se verían. Van
      // las del documento procesado de la fuente. Ver la clase.
      if (item == null ||
          finder == null ||
          !(await _texts.textOf(item)).processed) {
        if (resume != null) {
          await _closeRun(resume.runId, 'de fechas de un elemento ido');
        }
        return true;
      }

      // Un texto sin ninguna fecha escrita no necesita al modelo ni deja una
      // pasada vacía: pedirle las fechas a toda la biblioteca llenaría «Lo que
      // hizo la IA» de pasadas sin nada. Una pasada que se retoma ya existe.
      if (resume == null && !await finder.mentionsDates(item)) return true;

      final epoch = await _epoch();
      final quietBefore = _clock().subtract(_noteQuietPeriod);
      final pending = math.max(0, await _pending(epoch, quietBefore));
      final batch = _datesBatch;
      if (batch != null && batchOf == _datesSerial) {
        _publishDates(batch.copyWith(currentTitle: () => item.title));
      }
      _onStatus(
        AiOrganizeWorking(
          itemTitle: item.title,
          source: AiWorkSource.datesRequest,
          pending: pending,
        ),
      );
      _keepAlive(AiWorkSource.datesRequest, pending);

      final runId =
          resume?.runId ??
          (await _runs.startRun(
            item.id,
            model: _modelName?.call(),
            scope: AiRunScope.dates,
          )).fold((failure) {
            _telemetry.recordError(
              failure,
              StackTrace.current,
              hint: 'AiOrganizeQueue: no se pudo abrir la pasada de fechas',
            );
            return null;
          }, (id) => id);
      if (runId == null) return true;

      // La tarea de «Lo que hizo la IA» (F39, paso 6): un paso, y cuánto va
      // del pedido entero.
      final batchNow = _datesBatch;
      final task = _tasks?.begin(
        kind: AiTaskKind.dates,
        title: item.title,
        itemId: item.id,
        model: _modelName?.call(),
        steps: const [AiTaskStepKind.organizeDates],
        batchProgress: batchNow != null && batchOf == _datesSerial
            ? AiTaskProgress(
                done: batchNow.done,
                total: batchNow.total,
                unit: AiTaskUnit.item,
              )
            : null,
      );
      task?.step(AiTaskStepKind.organizeDates);
      final usage = AiRunUsageSaver(
        runs: _runs,
        telemetry: _telemetry,
        runId: runId,
        task: task,
        hint: 'AiOrganizeQueue',
      );
      try {
        report = await _within(
          task,
          () => finder.findDates(item, runId: runId),
        );
        // Como un paso de la pasada entera: el modelo es de terceros y falla de
        // formas sin un tipo propio. Lo que ya puso queda, con su pasada.
      } on Object catch (e, stackTrace) {
        final wait = aiModelWaitFor(e);
        if (wait != null) {
          // Lo que alcanzó a poner queda; lo que falta lo sigue al retomar, que
          // sabe hasta dónde leyó.
          waiting = true;
          _hold(wait, e);
          _interrupted = (
            itemId: item.id,
            source: AiWorkSource.datesRequest,
            runId: runId,
            done: const <AiOrganizeToggle>{},
            anotherBatch: false,
          );
          final current = _datesBatch;
          if (current != null && batchOf == _datesSerial) {
            _publishDates(current.copyWith(currentTitle: () => null));
          }
          return false;
        }
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'AiOrganizeQueue: fechas en ${item.id}',
        );
      } finally {
        // Lo que costó, antes de cerrar la pasada y también si se cortó
        // esperando al modelo.
        await usage.save();
        // Cortada, la pasada queda abierta y no se cierra acá: la tarea sí.
        if (waiting) usage.end();
      }
      await _closeRun(runId, 'de fechas');
      usage.end();
      return true;
    } finally {
      if (batchOf == _datesSerial && !waiting) _datesDone(report);
    }
  }

  /// Un elemento del pedido de fechas, mirado: suma lo que dio.
  void _datesDone(AiStepReport report) {
    final batch = _datesBatch;
    if (batch == null) return;
    _publishDates(
      batch.copyWith(
        done: batch.done + 1,
        created: batch.created + report.applied,
        currentTitle: () => null,
      ),
    );
  }

  /// Un elemento del pedido de tarjetas, mirado: suma lo que dio.
  void _cardDone(AiStepReport report) {
    final batch = _batch;
    if (batch == null) return;
    _publishBatch(
      batch.copyWith(
        done: batch.done + 1,
        created: batch.created + report.applied,
        forReview: batch.forReview + report.forReview,
        currentTitle: () => null,
      ),
    );
  }

  /// Pide el servicio en primer plano al tomar un elemento, y lo mantiene
  /// —con el avance— mientras siga trabajando. La notificación dice si es la
  /// biblioteca que ya existía, que solo se recorre con el cargador.
  void _keepAlive(AiWorkSource source, int pending) {
    _keepingAlive = true;
    final batch = _batch;
    // Un pedido de tarjetas dice cuánto va de ese pedido (F30).
    if (source == AiWorkSource.flashcardsRequest && batch != null) {
      _longWork.working(
        done: batch.done,
        total: batch.total,
        detail: LongWorkDetail.flashcards,
      );
      return;
    }
    // Y uno de fechas (F40), lo mismo.
    final dates = _datesBatch;
    if (source == AiWorkSource.datesRequest && dates != null) {
      _longWork.working(done: dates.done, total: dates.total);
      return;
    }
    _longWork.working(
      done: _organizedWhileKept,
      total: _organizedWhileKept + pending + 1,
      detail: source == AiWorkSource.existingLibrary
          ? LongWorkDetail.whileCharging
          : null,
    );
  }

  /// Suelta el servicio, si lo tenía pedido.
  void _letGo() {
    if (!_keepingAlive) return;
    _keepingAlive = false;
    _organizedWhileKept = 0;
    _longWork.idle();
  }

  Future<KnowledgeItem?> _find(String itemId) async =>
      (await _library.findById(itemId)).getRight().toNullable();

  /// Una nota de la persona o un documento procesado: lo que la IA organiza.
  /// Si no, es una fuente de la Biblioteca.
  static bool _isNote(KnowledgeItem item) =>
      item.source.kind == SourceKind.manualNote;
}

/// Lo próximo que toma la cola: qué elemento, de dónde salió y —si se cortó
/// esperando al modelo (F32)— dónde quedó.
typedef _Next = ({String itemId, AiWorkSource source, _Interrupted? resume});

/// Lo que se cortó porque el modelo dejó de contestar (F32): qué elemento, de
/// dónde salió, en qué pasada, qué pasos ya terminó y —un pedido de
/// tarjetas— si era otra tanda.
typedef _Interrupted = ({
  String itemId,
  AiWorkSource source,
  String runId,
  Set<AiOrganizeToggle> done,
  bool anotherBatch,
});

extension on AiWorkSource {
  /// Si viene de un pedido de la persona con su propia fila en la cola, aparte
  /// de lo que se organiza entero: lo que pidió Repasar (F30) y la línea de
  /// tiempo (F40).
  bool get isRequestLane =>
      this == AiWorkSource.flashcardsRequest ||
      this == AiWorkSource.datesRequest;
}
