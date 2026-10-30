import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/read_aloud_speed.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_queue.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_timeline.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/sleep_timer.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/passage_languages.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';

/// Cómo se ve el lector (F25; anclado abajo desde F47, paso 2).
enum ReadAloudPanel {
  /// Solo el botón redondo —si la pantalla tiene texto—: no se está leyendo
  /// nada.
  hidden,

  /// Leyendo (o en pausa), con el reproductor achicado a una línea: ▶, el
  /// título, +10 s y ⌃.
  minimized,

  /// El reproductor abierto.
  expanded,
}

/// En qué va el lector flotante (F25).
@immutable
class ReadAloudState {
  const ReadAloudState({
    this.document,
    this.scope = ReadScope.all,
    this.segmentIndex = 0,
    this.charInSegment = 0,
    this.playing = false,
    this.panel = ReadAloudPanel.hidden,
    this.speed = 1,
    this.voice,
    this.failed = false,
    this.queue = const ReadingQueue(),
    this.sleep,
  });

  /// Lo que se está leyendo; `null` si nada.
  final ReadableDocument? document;

  /// Qué parte de [document] se lee (F39): todo, o lo estudiado.
  final ReadScope scope;

  /// Qué pedazo de [segments] se lee ahora.
  final int segmentIndex;

  /// Por dónde va dentro de lo que se dice de ese pedazo (`spoken`), en
  /// caracteres: el comienzo de la palabra que se está diciendo.
  final int charInSegment;

  /// Si está sonando —o va a sonar enseguida—; `false` en pausa.
  final bool playing;

  final ReadAloudPanel panel;

  /// De 0,5 a 3 (decisión H de F47).
  final double speed;

  /// La voz que lee el pedazo de ahora —la del idioma del texto (F47, paso
  /// 3)—; sin nada que leer, la última elegida. `null`: la voz del sistema.
  final NarrationVoice? voice;

  /// El motor de voz falló; se ve en el reproductor.
  final bool failed;

  /// Lo que se lee después, y qué se repite (F47, paso 2).
  final ReadingQueue queue;

  /// El Temporizador para dormir, si hay uno en marcha (F47, paso 2).
  final SleepTimer? sleep;

  /// Los pedazos que se leen: los de [scope] de [document]. Lo que se
  /// resalta, el avance y los saltos salen todos de acá (F39).
  List<ReadableSegment> get segments =>
      document?.segmentsOf(scope) ?? const <ReadableSegment>[];

  ReadableSegment? get currentSegment {
    final segments = this.segments;
    if (segmentIndex >= segments.length) return null;
    return segments[segmentIndex];
  }

  /// Cuánto leyó, de 0 a 1, por caracteres dichos: el anillo del botón.
  ///
  /// Se pregunta con cada palabra dicha: no recorre el documento —un libro
  /// entero son decenas de miles de pedazos—, sino lo dicho antes de cada
  /// pedazo, que se cuenta una vez por lista (ver [_spokenBefore]).
  double get progress {
    final segments = this.segments;
    if (segments.isEmpty) return 0;
    final before = _spokenBefore[segments] ??= _countSpokenBefore(segments);
    final total = before.last;
    if (total == 0) return 0;
    if (segmentIndex >= segments.length) return 1;
    final done =
        before[segmentIndex] +
        charInSegment.clamp(0, segments[segmentIndex].spoken.length);
    return done / total;
  }

  /// La línea de tiempo de lo que se lee (F47, paso 2): el tiempo y los
  /// saltos, estimados por las palabras y la velocidad. Una por lista de
  /// pedazos, armada la primera vez que se pide.
  ReadingTimeline get timeline => ReadingTimeline.of(segments);

  /// Por dónde va, en caracteres de `spoken` desde el comienzo de lo que se
  /// lee.
  int get position {
    final segments = this.segments;
    if (segments.isEmpty) return 0;
    final index = segmentIndex.clamp(0, segments.length - 1);
    return timeline.startOf(index) +
        charInSegment.clamp(0, segments[index].spoken.length);
  }

  /// Cuánto se lleva leído, a la velocidad de ahora.
  Duration get elapsed => timeline.elapsedAt(position, speed);

  /// Cuánto dura todo lo que se lee, a la velocidad de ahora.
  Duration get total => timeline.durationAt(speed);

  /// Si llegó al final leyendo —o saltando— y quedó ahí, quieto.
  bool get finished {
    final segments = this.segments;
    if (document == null || playing || segments.isEmpty) return false;
    return segmentIndex >= segments.length - 1 &&
        charInSegment >= segments.last.spoken.length;
  }

  ReadAloudState copyWith({
    ReadableDocument? document,
    bool clearDocument = false,
    ReadScope? scope,
    int? segmentIndex,
    int? charInSegment,
    bool? playing,
    ReadAloudPanel? panel,
    double? speed,
    NarrationVoice? voice,
    bool clearVoice = false,
    bool? failed,
    ReadingQueue? queue,
    SleepTimer? sleep,
    bool clearSleep = false,
  }) => ReadAloudState(
    document: clearDocument ? null : document ?? this.document,
    scope: scope ?? this.scope,
    segmentIndex: segmentIndex ?? this.segmentIndex,
    charInSegment: charInSegment ?? this.charInSegment,
    playing: playing ?? this.playing,
    panel: panel ?? this.panel,
    speed: speed ?? this.speed,
    voice: clearVoice ? null : voice ?? this.voice,
    failed: failed ?? this.failed,
    queue: queue ?? this.queue,
    sleep: clearSleep ? null : sleep ?? this.sleep,
  );
}

/// Cuántos caracteres de `spoken` hay antes de cada pedazo de una lista, y al
/// final el total: lo que cuenta [ReadAloudState.progress], una vez por lista
/// de pedazos y no con cada palabra.
final _spokenBefore = Expando<List<int>>('lo dicho antes de cada pedazo');

List<int> _countSpokenBefore(List<ReadableSegment> segments) {
  final before = List<int>.filled(segments.length + 1, 0);
  for (var i = 0; i < segments.length; i++) {
    before[i + 1] = before[i] + segments[i].spoken.length;
  }
  return before;
}

/// El lector en voz alta: lee un [ReadableDocument], pedazo por pedazo, con
/// pausa de verdad y saltos de ±10 s (F25); y después, lo que espera en la
/// cola, con su repetición y su Temporizador para dormir (F47, paso 2).
///
/// Uno para toda la app: sigue leyendo aunque se cambie de pantalla, hasta
/// que se cierre.
///
/// **La voz sigue al idioma del texto** (F47, paso 3, decisión L): cada
/// pedazo se lee con la voz elegida para su idioma —ver `PassageLanguages`—,
/// y un texto con partes en dos idiomas se lee con las dos. Sin una elegida
/// para ese idioma, la mejor bajada de ese idioma, o una del teléfono en ese
/// idioma, o la del sistema; nunca una de otro idioma. Lo que no se sabe en
/// qué idioma está, con la última elegida.
///
/// Trabaja solo cuando el motor avisa algo —una palabra, un pedazo
/// terminado— o cuando se toca un control: sin consultas periódicas. El
/// único temporizador es el de dormir, uno solo y mientras esté elegido. El
/// estado cambia a lo sumo una vez por palabra dicha, y el pedazo resaltado
/// —lo que cada pantalla redibuja— una vez por línea.
class ReadAloudController extends Notifier<ReadAloudState> {
  late TextToSpeechService _tts;
  late Duration Function() _now;

  /// La línea de tiempo de lo que se lee: dónde empieza cada pedazo y cada
  /// oración, para los saltos, que cruzan pedazos. Una por lista de pedazos,
  /// no una en cada salto.
  ReadingTimeline _timeline = ReadingTimeline.of(const []);

  /// El que pausa la lectura cuando se cumple el Temporizador para dormir.
  Timer? _sleepTimer;

  /// Desde qué carácter de `spoken` del pedazo actual se le pidió al motor
  /// lo que suena: el progreso que avisa es relativo a eso.
  int _base = 0;

  /// Cada lectura pedida —y cada corte— suma uno: una lectura que todavía
  /// esperaba al motor y ya no es la última no sigue.
  int _generation = 0;

  /// Si los avisos del motor son de la lectura de ahora. Se apaga apenas se
  /// corta o se pide otra, y se prende recién cuando el motor aceptó la
  /// nueva: un "terminó" o una palabra de la lectura vieja pueden llegar
  /// por el canal con la plataforma después de cortarla, y no tienen que
  /// mover nada —ni pasar al pedazo siguiente después de una pausa—.
  bool _live = false;

  /// Si el motor tiene puestas la voz y la velocidad del lector. Una muestra
  /// de la biblioteca de voces lo usa prestado ([lendEngine]), y antes de
  /// volver a leer se le vuelven a poner (F47, paso 3).
  bool _engineReady = true;

  /// Las voces del teléfono, para leer un idioma sin voz elegida con una de
  /// ese idioma; vacía hasta que el motor las dice.
  List<NarrationVoice> _deviceVoices = const [];

  /// Los paquetes de voces sin conexión que están en el teléfono: una voz
  /// elegida que se borró no lee (F47, paso 3).
  Set<String> _installedPackages = const {};

  /// El último cambio de voz por un cambio de elección, para que
  /// [setVoice] lo espere.
  Future<void>? _following;

  @override
  ReadAloudState build() {
    _tts = ref.read(textToSpeechServiceProvider);
    _now = ref.read(narrationClockProvider);
    final events = _tts.events.listen(_onEvent);
    final progress = _tts.progress.listen(_onProgress);
    ref
      ..onDispose(() {
        _cut();
        _sleepTimer?.cancel();
        unawaited(events.cancel());
        unawaited(progress.cancel());
      })
      // La voz o la velocidad cambiadas desde otro lado valen también para
      // lo que se está leyendo. Las que cambia este mismo controlador llegan
      // acá iguales a las del estado, y no hacen nada.
      ..listen(narrationSettingsNotifierProvider, (_, next) {
        if (next.speed != state.speed) unawaited(_changeSpeed(next.speed));
        unawaited(_following = _followChoice());
      })
      // Una voz sin conexión que se baja o se borra cambia con qué se lee.
      ..listen(installedVoicePackagesProvider, (previous, next) {
        _installedPackages = next.valueOrNull ?? const {};
        // La primera vez es al nacer, antes de que haya estado.
        if (previous != null) unawaited(_following = _followChoice());
      }, fireImmediately: true);
    unawaited(
      _tts.getVoices().then(
        (voices) => _deviceVoices = voices,
        onError: (Object _) => const <NarrationVoice>[],
      ),
    );

    final settings = ref.read(narrationSettingsNotifierProvider);
    return ReadAloudState(
      speed: settings.speed,
      voice: _usable(settings.voice),
    );
  }

  /// Abre el reproductor sobre [document] y empieza a leer desde el pedazo
  /// [fromSegment] de [scope] —sin decirlo, el que ya se leía de ese
  /// documento, o todo; y si no hay, la primera capa estudiada que tenga
  /// algo—. Sin [fromSegment], desde lo que se ve en la pantalla que lo
  /// ofrece —ver [ReadableDocument.startAt]—, o desde el principio. Si ya se
  /// estaba leyendo eso mismo, sigue donde iba y solo abre el reproductor.
  Future<void> open(
    ReadableDocument document, {
    int? fromSegment,
    ReadScope? scope,
  }) async {
    if (document.isEmpty) return;
    final current = state.document;
    final same = current != null && current.id == document.id;
    final target =
        scope ??
        (same && document.offers(state.scope)
            ? state.scope
            : document.defaultScope);
    if (same && target == state.scope && document.offers(target)) {
      // El mismo documento, quizá con el texto cambiado —la pantalla se
      // reconstruyó después de editarlo—: se toma el nuevo para que el
      // resaltado caiga en su lugar, sin volver a empezar.
      final segments = document.segmentsOf(target);
      if (current != document) _load(segments);
      final index = state.segmentIndex.clamp(0, segments.length - 1);
      state = state.copyWith(
        document: document,
        segmentIndex: index,
        charInSegment: state.charInSegment.clamp(
          0,
          segments[index].spoken.length,
        ),
        panel: ReadAloudPanel.expanded,
      );
      return;
    }
    if (!document.offers(target)) return;
    await _start(
      document,
      target,
      fromSegment: fromSegment ?? document.startIndexOf(target),
    );
  }

  /// Cambia qué parte del documento se lee (F39) —todo, o solo el resumen, la
  /// síntesis o las palabras clave— y empieza a leerla desde el principio:
  /// cada parte es otra lista de pedazos, y la posición de una no es la de
  /// la otra. En un documento que dice por dónde va su vista —un libro, un
  /// PDF—, desde ahí: el resumen de lo que se está mirando. Una parte sin
  /// nada que leer no cambia nada.
  Future<void> setScope(ReadScope scope) async {
    final document = state.document;
    if (document == null || scope == state.scope || !document.offers(scope)) {
      return;
    }
    await _start(
      document,
      scope,
      fromSegment: document.startIndexOf(scope),
      panel: state.panel,
    );
  }

  /// Lee [scope] de [document] desde el pedazo [fromSegment], cortando lo que
  /// esté sonando.
  Future<void> _start(
    ReadableDocument document,
    ReadScope scope, {
    int fromSegment = 0,
    ReadAloudPanel panel = ReadAloudPanel.expanded,
  }) async {
    final segments = document.segmentsOf(scope);
    final generation = _cut();
    final wasPlaying = state.playing;
    _load(segments);
    state = state.copyWith(
      document: document,
      scope: scope,
      segmentIndex: fromSegment.clamp(0, segments.length - 1),
      charInSegment: 0,
      playing: true,
      panel: panel,
      failed: false,
    );
    if (wasPlaying) await _tts.stop();
    // Cada documento nuevo vuelve a fijar la voz y la velocidad —al decir su
    // primer pedazo, con la voz de su idioma—: el motor es uno solo para
    // toda la app, y otro pudo haberlo usado entretanto.
    _engineReady = false;
    if (generation != _generation) return;
    await _speak();
  }

  Future<void> play() async {
    final document = state.document;
    if (document == null || state.playing) return;
    if (_atEnd) state = state.copyWith(segmentIndex: 0, charInSegment: 0);
    state = state.copyWith(playing: true, failed: false);
    await _speak();
  }

  /// Pausa de verdad: corta el motor y se queda en la palabra que estaba
  /// diciendo —[ReadAloudState.charInSegment]—; [play] retoma desde ahí,
  /// repitiendo esa palabra.
  Future<void> pause() async {
    if (!state.playing) return;
    _cut();
    state = state.copyWith(playing: false);
    await _tts.stop();
  }

  Future<void> togglePlay() => state.playing ? pause() : play();

  /// Salta [delta] —10 s para adelante o para atrás— a la oración más
  /// cercana a ese tiempo (F47, paso 2): ver [ReadingTimeline.skip].
  ///
  /// La voz sintetizada no tiene una línea de tiempo (decisión A de F25):
  /// el tiempo se estima por las palabras y la velocidad de ahora, a lo
  /// largo de todo lo que se lee, así que un salto cruza pedazos. Pasado el
  /// final, queda terminado.
  Future<void> skip(Duration delta) async {
    if (state.document == null || delta == Duration.zero) return;
    final here = state.position;
    final landing = _timeline.skip(here, delta, state.speed);
    if (landing >= _timeline.length) return _finishAtEnd();
    if (landing == here) return;

    final (index, char) = _timeline.locate(landing);
    state = state.copyWith(segmentIndex: index, charInSegment: char);
    if (state.playing) await _speak(restart: true);
  }

  /// Va a [time] de lo que se lee —contado como [ReadAloudState.elapsed]—,
  /// al comienzo de la palabra que se dice entonces: soltar la barra del
  /// reproductor, o arrastrar la de la notificación (F47, paso 2). Si
  /// estaba sonando, sigue desde ahí; en pausa, queda ahí en pausa.
  Future<void> seekTo(Duration time) async {
    if (state.document == null || _timeline.length == 0) return;
    final target = _timeline.positionAt(time, state.speed);
    if (target >= _timeline.length) return _finishAtEnd();
    final (index, char) = _timeline.locate(target);
    state = state.copyWith(segmentIndex: index, charInSegment: char);
    if (state.playing) await _speak(restart: true);
  }

  /// Va al comienzo del pedazo [index] —una oración, un renglón— y, si estaba
  /// sonando, lo dice desde ahí; en pausa, queda ahí en pausa (F43, paso 7:
  /// «oración anterior» y «siguiente» del reproductor de los visores de
  /// Repasar). Antes del primero, el primero; después del último, queda
  /// terminado, como si hubiera llegado leyendo.
  Future<void> seekToSegment(int index) async {
    final segments = state.segments;
    if (state.document == null || segments.isEmpty) return;
    if (index >= segments.length) return _finishAtEnd();
    state = state.copyWith(
      segmentIndex: index < 0 ? 0 : index,
      charInSegment: 0,
    );
    if (state.playing) await _speak(restart: true);
  }

  /// La oración anterior: la de antes de la que suena, o el comienzo de la
  /// primera.
  Future<void> previousSegment() => seekToSegment(state.segmentIndex - 1);

  /// La oración siguiente.
  Future<void> nextSegment() => seekToSegment(state.segmentIndex + 1);

  /// Va a [fraction] de lo que se lee —de 0 a 1, contado en lo que se dice,
  /// como [ReadAloudState.progress]—, al comienzo de una palabra: soltar la
  /// barra de avance después de arrastrarla (F43, paso 7). Si estaba
  /// sonando, sigue desde ahí; en pausa, queda ahí en pausa. 1 es el final.
  Future<void> seekToFraction(double fraction) async {
    final total = _timeline.length;
    if (state.document == null || total == 0) return;
    final target = (fraction.clamp(0.0, 1.0) * total).round();
    if (target >= total) return _finishAtEnd();
    final (index, char) = _timeline.locate(_wordStartAt(target));
    state = state.copyWith(segmentIndex: index, charInSegment: char);
    if (state.playing) await _speak(restart: true);
  }

  Future<void> setSpeed(double speed) async {
    final value = speed.clamp(readAloudMinSpeed, readAloudMaxSpeed);
    if (value == state.speed) return;
    await _changeSpeed(value);
    await ref.read(narrationSettingsNotifierProvider.notifier).setSpeed(value);
  }

  /// Elige [voice] para su idioma (F47, paso 3): lee ya si es la del idioma
  /// de lo que se lee —o si no se sabe cuál es—, y si no, queda para cuando
  /// el texto pase a su idioma. `null`, la del sistema, deja sin elegida al
  /// idioma que se lee.
  Future<void> setVoice(NarrationVoice? voice) async {
    await ref
        .read(narrationSettingsNotifierProvider.notifier)
        .selectVoice(voice, language: _language);
    await _following;
  }

  /// El idioma del pedazo que se lee, o `null` si no se sabe o no hay nada.
  String? get _language {
    final segments = state.segments;
    if (segments.isEmpty) return null;
    return PassageLanguages.of(segments).at(state.segmentIndex);
  }

  /// Alguien más va a usar el motor de voz —una muestra de la biblioteca de
  /// voces (F47, paso 3)— con otra voz: antes de volver a leer, el lector le
  /// vuelve a poner la suya y su velocidad. Se llama con el lector en pausa.
  void lendEngine() => _engineReady = false;

  void minimize() {
    if (state.document == null) return;
    state = state.copyWith(panel: ReadAloudPanel.minimized);
  }

  void expand() {
    if (state.document == null) return;
    state = state.copyWith(panel: ReadAloudPanel.expanded);
  }

  /// Deja de leer y cierra el reproductor. La cola y el Temporizador para
  /// dormir se van con lo que sonaba: eran de esta escucha.
  Future<void> close() async {
    if (state.document == null) return;
    _cut();
    _cancelSleepTimer();
    _timeline = ReadingTimeline.of(const []);
    state = ReadAloudState(speed: state.speed, voice: state.voice);
    await _tts.stop();
  }

  // --- La cola (F47, paso 2) ------------------------------------------------

  /// Suma [document] a «Siguiente», con la parte [scope] —sin decirla, la
  /// que leería al abrirlo—. Sin nada sonando, empieza a leerlo; si es lo
  /// que ya suena, o ya está en la cola, no cambia nada.
  Future<void> enqueue(ReadableDocument document, {ReadScope? scope}) async {
    if (document.isEmpty) return;
    final target = scope ?? document.defaultScope;
    if (!document.offers(target)) return;
    final current = state.document;
    if (current == null) return open(document, scope: target);
    final reading = QueuedReading(document, scope: target);
    if (reading.sameAs(QueuedReading(current, scope: state.scope))) return;
    state = state.copyWith(queue: state.queue.add(reading));
  }

  /// Saca de la cola lo que está en [index].
  void removeFromQueue(int index) =>
      state = state.copyWith(queue: state.queue.removeAt(index));

  /// Mueve lo de [from] a [to], la posición en que queda: ver
  /// [ReadingQueue.move].
  void moveInQueue(int from, int to) =>
      state = state.copyWith(queue: state.queue.move(from, to));

  /// «Limpiar cola».
  void clearQueue() => state = state.copyWith(queue: state.queue.clear());

  /// ⟲: no repetir, repetir la cola, repetir lo que suena, y otra vez.
  void cycleRepeat() => setRepeat(state.queue.repeat.next);

  void setRepeat(ReadAloudRepeat repeat) =>
      state = state.copyWith(queue: state.queue.withRepeat(repeat));

  /// Lee ya lo que está en [index] de la cola, desde el principio. Lo que
  /// sonaba no vuelve a la cola: se eligió otra cosa.
  Future<void> playQueued(int index) async {
    final upcoming = state.queue.upcoming;
    if (index < 0 || index >= upcoming.length) return;
    final reading = upcoming[index];
    state = state.copyWith(queue: state.queue.removeAt(index));
    await _start(reading.document, reading.scope, panel: _panelToKeep);
  }

  /// «Siguiente»: lo primero de la cola, como si lo que suena hubiera
  /// terminado —ver [ReadingQueue.skipFrom]—. Sin nada después, no hace
  /// nada.
  Future<void> playNext() async {
    final document = state.document;
    if (document == null) return;
    final (:next, :rest) = state.queue.skipFrom(
      QueuedReading(document, scope: state.scope),
    );
    if (next == null) return;
    state = state.copyWith(queue: rest);
    await _start(next.document, next.scope, panel: _panelToKeep);
  }

  /// Lo que sigue se lee con el reproductor como estaba: achicado sigue
  /// achicado.
  ReadAloudPanel get _panelToKeep => state.panel == ReadAloudPanel.hidden
      ? ReadAloudPanel.expanded
      : state.panel;

  // --- El Temporizador para dormir (F47, paso 2) ----------------------------

  /// Pausa la lectura cuando se cumpla [choice]; `null` lo apaga. Elegir
  /// otro reemplaza al que había. Sin nada abierto, no hay qué pausar.
  void setSleepTimer(SleepTimerChoice? choice) {
    _cancelSleepTimer();
    if (choice == null || state.document == null) {
      state = state.copyWith(clearSleep: true);
      return;
    }
    final now = _now();
    final timer = SleepTimer.start(choice, now: now);
    state = state.copyWith(sleep: timer);
    final left = timer.remaining(now);
    if (left != null) _sleepTimer = Timer(left, _sleepNow);
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  /// Se cumplió el tiempo: se pausa —la tarjeta queda, para seguir después
  /// donde quedó— y el temporizador se apaga.
  void _sleepNow() {
    _sleepTimer = null;
    state = state.copyWith(clearSleep: true);
    unawaited(pause());
  }

  // --- La lectura -----------------------------------------------------------

  bool get _atEnd {
    final segments = state.segments;
    return state.segmentIndex >= segments.length - 1 &&
        state.charInSegment >= segments.last.spoken.length;
  }

  void _load(List<ReadableSegment> segments) {
    _timeline = ReadingTimeline.of(segments);
  }

  /// Deja sin efecto la lectura en curso y lo que esté por pedirse: sus
  /// avisos ya no cuentan. Devuelve el número de la lectura que sigue.
  int _cut() {
    _live = false;
    return ++_generation;
  }

  /// Le pide al motor el pedazo actual desde [ReadAloudState.charInSegment].
  /// Con [restart], primero corta lo que esté sonando: en iOS un pedido
  /// nuevo se encola detrás del anterior en vez de reemplazarlo.
  Future<void> _speak({bool restart = false}) async {
    final generation = _cut();
    if (restart) await _tts.stop();
    if (generation != _generation || !state.playing) return;

    final segment = state.currentSegment;
    if (segment == null) return;
    final from = state.charInSegment.clamp(0, segment.spoken.length);
    final text = segment.spoken.substring(from);
    if (text.trim().isEmpty) return _next();

    // La voz del idioma de este pedazo; si cambió —el texto pasó a otro
    // idioma— o el motor se prestó, se le vuelven a poner voz y velocidad.
    final voice = _voiceAt(state.segmentIndex);
    if (!_engineReady || voice != state.voice) {
      _engineReady = true;
      if (voice != state.voice) {
        state = state.copyWith(voice: voice, clearVoice: voice == null);
      }
      await _tts.setVoice(voice);
      await _tts.setSpeed(state.speed);
      if (generation != _generation || !state.playing) return;
    }

    _base = from;
    try {
      await _tts.speak(text);
    } on Exception {
      if (generation == _generation) _fail();
      return;
    }
    if (generation != _generation) return;
    _live = true;
    // El que sigue, listo mientras suena este —una voz sin conexión lo
    // genera—, si lo lee la misma voz.
    final next = state.segmentIndex + 1;
    final segments = state.segments;
    if (next < segments.length && _voiceAt(next) == voice) {
      unawaited(_tts.prepare(segments[next].spoken));
    }
  }

  /// El pedazo actual terminó: sigue con el próximo. Al final, lo que diga
  /// la cola (F47, paso 2) —lo siguiente, o lo mismo otra vez—; y si no hay
  /// nada después, o el Temporizador para dormir era «al terminar esto»,
  /// queda terminado, con el reproductor como estaba, para volver a empezar.
  Future<void> _next() async {
    if (state.segmentIndex + 1 < state.segments.length) {
      state = state.copyWith(
        segmentIndex: state.segmentIndex + 1,
        charInSegment: 0,
      );
      return _speak();
    }
    _cut();
    final document = state.document!;
    final atEnd = state.copyWith(
      charInSegment: state.currentSegment!.spoken.length,
      playing: false,
    );
    if (state.sleep?.atEndOfReading ?? false) {
      _cancelSleepTimer();
      state = atEnd.copyWith(clearSleep: true);
      return;
    }
    final (:next, :rest) = state.queue.afterFinishing(
      QueuedReading(document, scope: state.scope),
    );
    if (next == null) {
      state = atEnd;
      return;
    }
    state = state.copyWith(queue: rest);
    await _start(next.document, next.scope, panel: state.panel);
  }

  /// Un salto más allá del final: queda terminado, como si hubiera llegado
  /// leyendo.
  Future<void> _finishAtEnd() async {
    final wasPlaying = state.playing;
    _cut();
    final segments = state.segments;
    state = state.copyWith(
      segmentIndex: segments.length - 1,
      charInSegment: segments.last.spoken.length,
      playing: false,
    );
    if (wasPlaying) await _tts.stop();
  }

  void _fail() {
    _cut();
    state = state.copyWith(playing: false, failed: true);
  }

  void _onEvent(NarrationEvent event) {
    if (!_live || !state.playing) return;
    switch (event) {
      case NarrationEvent.completed:
        _live = false;
        unawaited(_next());
      case NarrationEvent.error:
        _fail();
    }
  }

  void _onProgress(int offset) {
    if (!_live || !state.playing) return;
    final segment = state.currentSegment;
    if (segment == null) return;
    final char = (_base + offset).clamp(0, segment.spoken.length);

    if (char != state.charInSegment) {
      state = state.copyWith(charInSegment: char);
    }
  }

  // --- Voz y velocidad ------------------------------------------------------

  Future<void> _changeSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _tts.setSpeed(speed);
    // Que se oiga ya: el motor no cambia de velocidad a mitad de un pedido,
    // así que se vuelve a pedir desde la palabra en que iba.
    if (state.playing) await _speak(restart: true);
  }

  /// Lo elegido cambió —otra voz para un idioma, una voz bajada o borrada—:
  /// si cambia la voz del pedazo de ahora, se oye ya.
  Future<void> _followChoice() async {
    final voice = _voiceAt(state.segmentIndex);
    if (voice != state.voice) await _changeVoice(voice);
  }

  /// La voz con que se lee el pedazo [index]: la de su idioma.
  NarrationVoice? _voiceAt(int index) {
    final segments = state.segments;
    final language = segments.isEmpty
        ? null
        : PassageLanguages.of(segments).at(index);
    return _voiceFor(language);
  }

  /// La voz para [language]: la elegida; sin elegida, la mejor sin conexión
  /// bajada de ese idioma, una del teléfono de ese idioma —primero las que
  /// andan sin conexión— o la del sistema. Sin idioma, la última elegida.
  NarrationVoice? _voiceFor(String? language) {
    final settings = ref.read(narrationSettingsNotifierProvider);
    if (language == null) return _usable(settings.voice);
    final chosen = _usable(settings.voicesByLanguage[language]);
    if (chosen != null) return chosen;
    for (final quality in [...VoiceQuality.values, null]) {
      for (final voice in OfflineVoiceCatalog.voices) {
        if (voice.language == language &&
            voice.quality == quality &&
            _installedPackages.contains(voice.package.id)) {
          return narrationVoiceOf(voice);
        }
      }
    }
    final device = [
      for (final voice in _deviceVoices)
        if (accentLanguage(voice.locale) == language) voice,
    ];
    if (device.isEmpty) return null;
    return device.firstWhere(
      (voice) => voice.name.toLowerCase().contains('local'),
      orElse: () => device.firstWhere(
        (voice) => !voice.name.toLowerCase().contains('network'),
        orElse: () => device.first,
      ),
    );
  }

  /// [voice], si puede leer: una sin conexión cuyo paquete se borró, no.
  NarrationVoice? _usable(NarrationVoice? voice) {
    if (voice == null || voice.engine != NarrationEngine.offline) return voice;
    final offline = OfflineVoiceCatalog.byId(voice.name);
    if (offline == null) return null;
    return _installedPackages.contains(offline.package.id) ? voice : null;
  }

  Future<void> _changeVoice(NarrationVoice? voice) async {
    state = state.copyWith(voice: voice, clearVoice: voice == null);
    await _tts.setVoice(voice);
    if (state.playing) await _speak(restart: true);
  }

  // --- Posiciones en el documento -------------------------------------------

  String _spokenOf(int index) => state.segments[index].spoken;

  /// El comienzo de la palabra en [position]; si cae en un espacio, el de la
  /// palabra que sigue.
  int _wordStartAt(int position) {
    final (index, char) = _timeline.locate(position);
    final spoken = _spokenOf(index);
    var at = char;
    if (at < spoken.length && _isSpace(spoken.codeUnitAt(at))) {
      while (at < spoken.length && _isSpace(spoken.codeUnitAt(at))) {
        at++;
      }
    } else {
      while (at > 0 && !_isSpace(spoken.codeUnitAt(at - 1))) {
        at--;
      }
    }
    return _timeline.startOf(index) + at;
  }
}

/// `spoken` viene con los espacios juntados en uno —ver
/// `buildReadableSegments`—, pero un documento armado a mano puede traer
/// tabuladores o saltos.
bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

final readAloudControllerProvider =
    NotifierProvider<ReadAloudController, ReadAloudState>(
      ReadAloudController.new,
    );

/// Lo que se está leyendo en el texto `sourceKey` —`[start, end)` de ese
/// texto—, o `null` si el lector no está leyendo nada de él: lo que cada
/// pantalla pinta de amarillo (F25).
final readAloudHighlightProvider = Provider.family<(int, int)?, String>((
  ref,
  sourceKey,
) {
  final segment = ref.watch(
    readAloudControllerProvider.select(
      (s) => s.panel == ReadAloudPanel.hidden ? null : s.currentSegment,
    ),
  );
  if (segment == null || segment.sourceKey != sourceKey) return null;
  return (segment.start, segment.end);
});

/// Cómo va la lectura de una parte de un documento (F39).
enum ReadAloudRun {
  /// El lector no está leyendo esa parte de ese documento.
  none,

  /// La está leyendo, en pausa.
  paused,

  /// La está leyendo, sonando.
  playing,
}

/// Cómo va la lectura de la parte `scope` del documento `documentId`: lo que
/// un botón «Escuchar» necesita para saber si empieza, pausa o retoma. Sale
/// del mismo estado que el reproductor, no de una copia.
final readAloudRunProvider =
    Provider.family<ReadAloudRun, ({String documentId, ReadScope scope})>((
      ref,
      key,
    ) {
      return ref.watch(
        readAloudControllerProvider.select((s) {
          // Cerrado el lector no queda documento: el panel no hace falta.
          if (s.document?.id != key.documentId || s.scope != key.scope) {
            return ReadAloudRun.none;
          }
          return s.playing ? ReadAloudRun.playing : ReadAloudRun.paused;
        }),
      );
    });
