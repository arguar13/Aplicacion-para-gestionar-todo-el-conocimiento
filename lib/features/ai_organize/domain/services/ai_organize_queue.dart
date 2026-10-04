import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_flashcard_maker.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_memory.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/ai_organize/domain/services/content_change.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Cuánto tiene que estar quieta una nota antes de que la IA la organice:
/// mientras se escribe, cada guardado la cambia, y organizarla a mitad sería
/// vincular y hacer tarjetas de un borrador.
const kAiNoteQuietPeriod = Duration(seconds: 15);

/// La cola de la IA que organiza sola (F27): aparte de la de procesamiento,
/// de a un elemento por vez y en segundo plano. El elemento queda listo como
/// siempre; la IA trabaja después.
///
/// **Qué toma, en este orden:** lo que se pidió organizar a mano
/// ([organizeNow]); las tarjetas que se pidieron desde Repasar
/// ([makeFlashcards], F30); lo nuevo —cada fuente que termina de procesarse,
/// cada nota cuando lleva [kAiNoteQuietPeriod] sin cambios—; las notas ya
/// organizadas que cambiaron mucho de contenido (`kNoteRegrowHammingBits`);
/// y, solo si está prendido y el
/// dispositivo está enchufado, la biblioteca que ya existía (decisión C).
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
/// falta bajar alguno de los dos modelos —sin ellos no puede hacer nada—; en
/// los dos casos lo publica en su estado y espera, sin errores. Pausar no
/// corta el elemento en curso: termina lo que está haciendo —de segundos a un
/// par de minutos— y no toma otro.
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
    required ChatModelManager Function() chatModel,
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
  }) : _backlog = backlog,
       _runs = runs,
       _library = library,
       _steps = steps,
       _chatModel = chatModel,
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
       _onFlashcardsBatch = onFlashcardsBatch;

  final AiOrganizeBacklog _backlog;
  final AiRunRepository _runs;
  final LibraryRepository _library;

  /// Se piden al usarlos, no al nacer: armar los pasos arma la cadena de
  /// proveedores del modelo, y la cola vive toda la sesión.
  final List<AiOrganizeStep> Function() _steps;

  /// También al usarlos: elegir otra opción de modelo de chat arma otro.
  final ChatModelManager Function() _chatModel;
  final EmbeddingModelManager Function() _embeddingModel;

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
  var _cardsPaused = false;
  final void Function(AiFlashcardsBatch? batch)? _onFlashcardsBatch;

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

  /// Un elemento terminó de procesarse bien: la cola se despierta y lo toma
  /// —ya está pendiente en la base—.
  void itemProcessed(String itemId) => unawaited(wake());

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
    _publishBatch(
      batch == null || batch.finished
          ? AiFlashcardsBatch(total: added, paused: _cardsPaused)
          : batch.copyWith(total: batch.total + added),
    );
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
    _publishBatch(null);
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
          await (next.source == AiWorkSource.flashcardsRequest
              ? _makeFlashcards(next.itemId)
              : _organize(next.itemId, next.source));
          _organizedWhileKept++;
          continue;
        }
        // Nada que pueda hacer ahora: terminó, se pausó, falta el cargador o
        // un modelo. El servicio se suelta.
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
    // Las tarjetas que pidió la persona (F30) no dependen de los
    // interruptores de cada tipo ni del modelo de vínculos.
    final cardsWaiting = _cardRequests.isNotEmpty && !_cardsPaused;
    if (!_anyStepOn && !cardsWaiting) {
      _onStatus(const AiOrganizeIdle());
      return null;
    }
    final chatReady = await _chatModel().isReady();
    final embeddingReady = await _embeddingModel().isReady();
    final canOrganize = _anyStepOn && chatReady && embeddingReady;
    if (!canOrganize && !(cardsWaiting && chatReady)) {
      _onStatus(
        chatReady && embeddingReady
            ? const AiOrganizeIdle()
            : AiOrganizeModelMissing(
                chatModelMissing: !chatReady,
                embeddingModelMissing: !embeddingReady,
              ),
      );
      return null;
    }

    if (canOrganize && _requested.isNotEmpty) {
      return (itemId: _requested.removeFirst(), source: AiWorkSource.requested);
    }
    if (cardsWaiting) {
      return (
        itemId: _cardRequests.removeFirst(),
        source: AiWorkSource.flashcardsRequest,
      );
    }

    final fresh = await _backlog.nextFresh(
      since: epoch,
      notesQuietBefore: quietBefore,
      skip: _skip,
    );
    if (fresh != null) return (itemId: fresh, source: AiWorkSource.fresh);

    final grown = await _grownNote(quietBefore);
    if (grown != null) {
      return (itemId: grown, source: AiWorkSource.changedNote);
    }

    if (_settings.backfillWhileCharging) {
      final existing = await _backlog.nextExisting(
        before: epoch,
        notesQuietBefore: quietBefore,
        skip: _skip,
      );
      if (existing != null) {
        if (await _charging.isCharging()) {
          return (itemId: existing, source: AiWorkSource.existingLibrary);
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
      if (contentChangedMuch(seen, await _simhashOf(note.searchableText))) {
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
    return _requested.length +
        _cardRequests.length +
        count.fresh +
        (_settings.backfillWhileCharging ? count.existing : 0);
  }

  Future<void> _organize(String itemId, AiWorkSource source) async {
    final item = await _find(itemId);
    if (item == null) {
      _skip.add(itemId);
      return;
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

    // La huella del texto que ve esta pasada, para saber después si la nota
    // cambió. Solo de las notas: una fuente no se vuelve a organizar por
    // cambios, y la de un libro serían cientos de miles de cuentas.
    final simhash = _isNote(item)
        ? await _simhashOf(item.searchableText)
        : null;
    final runId =
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
    if (runId == null) return;

    for (final step in _steps()) {
      // Cada paso mira su interruptor al empezar: apagar un tipo a mitad de
      // un elemento vale desde el paso siguiente.
      if (!step.toggle.valueIn(_settings)) continue;
      try {
        await step.organize(item, runId: runId);
        // Un paso que falla no corta la pasada: lo que ya creó queda, con su
        // pasada, y los demás pasos se hacen igual. Se atrapa todo —el modelo
        // es de terceros y falla de formas sin un tipo propio— y se registra.
      } on Object catch (e, stackTrace) {
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'AiOrganizeQueue: ${step.toggle.name} en ${item.id}',
        );
      }
    }

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
  }

  /// Solo las tarjetas de [itemId] (F30): una pasada de solo tarjetas, con
  /// el paso de tarjetas como `AiFlashcardMaker`. Un fallo se registra y el
  /// pedido sigue con el próximo; el elemento cuenta como mirado igual.
  Future<void> _makeFlashcards(String itemId) async {
    final anotherBatch = _anotherBatch.remove(itemId);
    final item = await _find(itemId);
    final maker = _steps().whereType<AiFlashcardMaker>().firstOrNull;
    if (item == null || maker == null) {
      _cardDone(AiStepReport.nothing);
      return;
    }

    final epoch = await _epoch();
    final quietBefore = _clock().subtract(_noteQuietPeriod);
    final pending = math.max(0, await _pending(epoch, quietBefore));
    final batch = _batch;
    if (batch != null) {
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
        (await _runs.startRun(
          item.id,
          model: _modelName?.call(),
          flashcardsOnly: true,
        )).fold((failure) {
          _telemetry.recordError(
            failure,
            StackTrace.current,
            hint: 'AiOrganizeQueue: no se pudo abrir la pasada de tarjetas',
          );
          return null;
        }, (id) => id);
    if (runId == null) {
      _cardDone(AiStepReport.nothing);
      return;
    }

    var report = AiStepReport.nothing;
    try {
      report = await maker.makeFlashcards(
        item,
        runId: runId,
        anotherBatch: anotherBatch,
      );
      // Como un paso de la pasada entera: el modelo es de terceros y falla
      // de formas sin un tipo propio. Lo que ya creó queda, con su pasada.
    } on Object catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'AiOrganizeQueue: tarjetas en ${item.id}',
      );
    }
    (await _runs.finishRun(runId)).match(
      (failure) => _telemetry.recordError(
        failure,
        StackTrace.current,
        hint: 'AiOrganizeQueue: no se pudo cerrar la pasada de tarjetas',
      ),
      (_) {},
    );
    _cardDone(report);
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

  static bool _isNote(KnowledgeItem item) =>
      item.source.kind == SourceKind.manualNote;
}

/// Lo próximo que toma la cola: qué elemento y de dónde salió.
typedef _Next = ({String itemId, AiWorkSource source});
