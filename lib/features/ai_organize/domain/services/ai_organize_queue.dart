import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_memory.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';

/// Cuánto tiene que estar quieta una nota antes de que la IA la organice:
/// mientras se escribe, cada guardado la cambia, y organizarla a mitad sería
/// vincular y hacer tarjetas de un borrador.
const kAiNoteQuietPeriod = Duration(seconds: 15);

/// Cuánto tiene que cambiar una nota ya organizada para volver a
/// organizarla: [kNoteRegrowMinChars] caracteres o una [kNoteRegrowRatio]
/// parte de lo que tenía, lo que sea más. Un párrafo nuevo en una nota corta
/// alcanza; una coma en una nota larga, no. Se mide por el largo —lo único
/// que se recuerda de la vez anterior—: reescribir una nota sin cambiarle el
/// largo no la vuelve a organizar.
const kNoteRegrowMinChars = 300;
const kNoteRegrowRatio = 0.3;

/// La cola de la IA que organiza sola (F27): aparte de la de procesamiento,
/// de a un elemento por vez y en segundo plano. El elemento queda listo como
/// siempre; la IA trabaja después.
///
/// **Qué toma, en este orden:** lo que se pidió organizar a mano
/// ([organizeNow]); lo nuevo —cada fuente que termina de procesarse, cada
/// nota cuando lleva [kAiNoteQuietPeriod] sin cambios—; las notas ya
/// organizadas que crecieron mucho; y, solo si está prendido y el
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
/// No mantiene viva la app en segundo plano: el servicio en primer plano de
/// F21 es de la cola de procesamiento, con su propia notificación. Si el
/// sistema congela la app, la cola sigue al volver.
class AiOrganizeQueue {
  AiOrganizeQueue({
    required AiOrganizeBacklog backlog,
    required AiRunRepository runs,
    required LibraryRepository library,
    required List<AiOrganizeStep> Function() steps,
    required ChatModelManager Function() chatModel,
    required EmbeddingModelManager Function() embeddingModel,
    required ChargingProbe charging,
    required AiOrganizeMemory memory,
    required TelemetryService telemetry,
    required Clock clock,
    required void Function(AiOrganizeStatus status) onStatus,
    AiOrganizeSettings settings = const AiOrganizeSettings(),
    String? Function()? modelName,
    Duration noteQuietPeriod = kAiNoteQuietPeriod,
  }) : _backlog = backlog,
       _runs = runs,
       _library = library,
       _steps = steps,
       _chatModel = chatModel,
       _embeddingModel = embeddingModel,
       _charging = charging,
       _memory = memory,
       _telemetry = telemetry,
       _clock = clock,
       _onStatus = onStatus,
       _settings = settings,
       _modelName = modelName,
       _noteQuietPeriod = noteQuietPeriod;

  final AiOrganizeBacklog _backlog;
  final AiRunRepository _runs;
  final LibraryRepository _library;

  /// Se piden al usarlos, no al nacer: armar los pasos arma la cadena de
  /// proveedores del modelo, y la cola vive toda la sesión.
  final List<AiOrganizeStep> Function() _steps;

  /// También al usarlos: elegir otra opción de modelo de chat arma otro.
  final ChatModelManager Function() _chatModel;
  final EmbeddingModelManager Function() _embeddingModel;
  final ChargingProbe _charging;
  final AiOrganizeMemory _memory;
  final TelemetryService _telemetry;
  final Clock _clock;
  final void Function(AiOrganizeStatus status) _onStatus;

  /// Qué modelo trabaja, para la pasada; al usarlo, por lo mismo.
  final String? Function()? _modelName;
  final Duration _noteQuietPeriod;

  AiOrganizeSettings _settings;

  /// Lo que se pidió organizar a mano, en orden.
  final _requested = Queue<String>();

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
  void organizeNow(String itemId) {
    _skip.remove(itemId);
    if (!_requested.contains(itemId)) _requested.add(itemId);
    unawaited(wake());
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
          await _organize(next.itemId, next.source);
          continue;
        }
        if (!_wakeAgain) break;
      }
      // Ningún error de una consulta puede dejar la cola trabada en
      // «trabajando»: se registra y se espera el próximo aviso.
    } on Object catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'AiOrganizeQueue._drain');
      _onStatus(const AiOrganizeIdle());
    } finally {
      _running = false;
    }
  }

  /// El próximo elemento por organizar y de dónde salió, o `null` si no hay
  /// nada que se pueda hacer ahora; en ese caso deja publicado por qué.
  Future<_Next?> _next() async {
    final epoch = await _memory.epoch();
    final quietBefore = _clock().subtract(_noteQuietPeriod);

    if (!_settings.enabled) {
      _onStatus(AiOrganizePaused(pending: await _pending(epoch, quietBefore)));
      return null;
    }
    if (!_anyStepOn) {
      _onStatus(const AiOrganizeIdle());
      return null;
    }
    final chatReady = await _chatModel().isReady();
    final embeddingReady = await _embeddingModel().isReady();
    if (!chatReady || !embeddingReady) {
      _onStatus(
        AiOrganizeModelMissing(
          chatModelMissing: !chatReady,
          embeddingModelMissing: !embeddingReady,
        ),
      );
      return null;
    }

    if (_requested.isNotEmpty) {
      return (itemId: _requested.removeFirst(), source: AiWorkSource.requested);
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

  /// Una nota ya organizada que creció o se achicó lo suficiente.
  Future<String?> _grownNote(DateTime quietBefore) async {
    for (final edited in await _backlog.editedNotes(quietBefore: quietBefore)) {
      if (_skip.contains(edited.itemId)) continue;
      if (_noteChangesSeen[edited.itemId] == edited.updatedAt) continue;
      _noteChangesSeen[edited.itemId] = edited.updatedAt;

      final seen = _memory.noteLengthSeen(edited.itemId);
      // Sin saber cuánto tenía —se organizó en otro dispositivo—, no se
      // supone que cambió: volver a organizar es más tarjetas y vínculos.
      if (seen == null) continue;
      final note = await _find(edited.itemId);
      if (note == null) continue;
      final change = (note.searchableText.length - seen).abs();
      final needed = math.max(kNoteRegrowMinChars, kNoteRegrowRatio * seen);
      if (change >= needed) return edited.itemId;
    }
    return null;
  }

  /// Cuántos esperan: los nuevos, lo pedido a mano y —si se recorre— la
  /// biblioteca que ya existía.
  Future<int> _pending(DateTime epoch, DateTime quietBefore) async {
    final count = await _backlog.count(
      epoch: epoch,
      notesQuietBefore: quietBefore,
    );
    return _requested.length +
        count.fresh +
        (_settings.backfillWhileCharging ? count.existing : 0);
  }

  Future<void> _organize(String itemId, AiWorkSource source) async {
    final item = await _find(itemId);
    if (item == null) {
      _skip.add(itemId);
      return;
    }

    final epoch = await _memory.epoch();
    final quietBefore = _clock().subtract(_noteQuietPeriod);
    _onStatus(
      AiOrganizeWorking(
        itemTitle: item.title,
        source: source,
        // Este ya no espera.
        pending: math.max(0, await _pending(epoch, quietBefore) - 1),
      ),
    );

    final runId = (await _runs.startRun(item.id, model: _modelName?.call()))
        .fold((failure) {
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
    if (_isNote(item)) {
      await _memory.rememberNoteLength(item.id, item.searchableText.length);
    }
  }

  Future<KnowledgeItem?> _find(String itemId) async =>
      (await _library.findById(itemId)).getRight().toNullable();

  static bool _isNote(KnowledgeItem item) =>
      item.source.kind == SourceKind.manualNote;
}

/// Lo próximo que toma la cola: qué elemento y de dónde salió.
typedef _Next = ({String itemId, AiWorkSource source});
