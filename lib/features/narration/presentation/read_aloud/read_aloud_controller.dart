import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';

/// Cómo se ve el lector flotante (F25).
enum ReadAloudPanel {
  /// Solo el botón redondo —si la pantalla tiene texto—: no se está leyendo
  /// nada.
  hidden,

  /// Leyendo (o en pausa), achicado al botón redondo con un anillo de
  /// avance.
  minimized,

  /// El mini reproductor abierto.
  expanded,
}

/// En qué va el lector flotante (F25).
@immutable
class ReadAloudState {
  const ReadAloudState({
    this.document,
    this.segmentIndex = 0,
    this.charInSegment = 0,
    this.playing = false,
    this.panel = ReadAloudPanel.hidden,
    this.speed = 1,
    this.voice,
    this.failed = false,
  });

  /// Lo que se está leyendo; `null` si nada.
  final ReadableDocument? document;

  /// Qué pedazo de [document] se lee ahora.
  final int segmentIndex;

  /// Por dónde va dentro de lo que se dice de ese pedazo (`spoken`), en
  /// caracteres: el comienzo de la palabra que se está diciendo.
  final int charInSegment;

  /// Si está sonando —o va a sonar enseguida—; `false` en pausa.
  final bool playing;

  final ReadAloudPanel panel;

  /// De 0,5 a 2.
  final double speed;

  /// `null`: la voz del sistema.
  final NarrationVoice? voice;

  /// El motor de voz falló; se ve en el reproductor.
  final bool failed;

  ReadableSegment? get currentSegment {
    final segments = document?.segments;
    if (segments == null || segmentIndex >= segments.length) return null;
    return segments[segmentIndex];
  }

  /// Cuánto leyó, de 0 a 1, por caracteres dichos: el anillo del botón.
  double get progress {
    final segments = document?.segments;
    if (segments == null || segments.isEmpty) return 0;
    var total = 0;
    var done = 0;
    for (var i = 0; i < segments.length; i++) {
      final length = segments[i].spoken.length;
      total += length;
      if (i < segmentIndex) done += length;
      if (i == segmentIndex) done += charInSegment.clamp(0, length);
    }
    return total == 0 ? 0 : done / total;
  }

  ReadAloudState copyWith({
    ReadableDocument? document,
    bool clearDocument = false,
    int? segmentIndex,
    int? charInSegment,
    bool? playing,
    ReadAloudPanel? panel,
    double? speed,
    NarrationVoice? voice,
    bool clearVoice = false,
    bool? failed,
  }) => ReadAloudState(
    document: clearDocument ? null : document ?? this.document,
    segmentIndex: segmentIndex ?? this.segmentIndex,
    charInSegment: charInSegment ?? this.charInSegment,
    playing: playing ?? this.playing,
    panel: panel ?? this.panel,
    speed: speed ?? this.speed,
    voice: clearVoice ? null : voice ?? this.voice,
    failed: failed ?? this.failed,
  );
}

/// El lector flotante: lee un [ReadableDocument] en voz alta, pedazo por
/// pedazo, con pausa de verdad y saltos de ±10 s de habla (F25).
///
/// Uno para toda la app: sigue leyendo aunque se cambie de pantalla, hasta
/// que se cierre.
///
/// Trabaja solo cuando el motor avisa algo —una palabra, un pedazo
/// terminado— o cuando se toca un control: sin temporizadores ni consultas
/// periódicas. El estado cambia a lo sumo una vez por palabra dicha, y el
/// pedazo resaltado —lo que cada pantalla redibuja— una vez por línea.
class ReadAloudController extends Notifier<ReadAloudState> {
  late TextToSpeechService _tts;
  late Duration Function() _now;

  /// Dónde empieza cada pedazo, en caracteres de `spoken` contados desde el
  /// principio del documento: los saltos cruzan pedazos. Se arma una vez por
  /// documento, no en cada salto.
  List<int> _starts = const [];
  int _total = 0;

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

  final _rate = _SpeechRate();

  /// La última palabra avisada de la lectura de ahora, y cuándo: de una
  /// palabra a la siguiente se mide el ritmo de la voz.
  int? _lastWordChar;
  Duration? _lastWordAt;

  @override
  ReadAloudState build() {
    _tts = ref.read(textToSpeechServiceProvider);
    _now = ref.read(narrationClockProvider);
    final events = _tts.events.listen(_onEvent);
    final progress = _tts.progress.listen(_onProgress);
    ref
      ..onDispose(() {
        _cut();
        unawaited(events.cancel());
        unawaited(progress.cancel());
      })
      // La voz o la velocidad cambiadas desde otro lado valen también para
      // lo que se está leyendo. Las que cambia este mismo controlador llegan
      // acá iguales a las del estado, y no hacen nada.
      ..listen(narrationSettingsNotifierProvider, (_, next) {
        if (next.speed != state.speed) unawaited(_changeSpeed(next.speed));
        if (next.voice != state.voice) unawaited(_changeVoice(next.voice));
      });

    final settings = ref.read(narrationSettingsNotifierProvider);
    _rate.reset(_SpeechRate.defaultFor(settings.speed));
    return ReadAloudState(speed: settings.speed, voice: settings.voice);
  }

  /// Abre el reproductor sobre [document] y empieza a leer desde el pedazo
  /// [fromSegment]. Si ya se estaba leyendo ese mismo documento, sigue
  /// donde iba y solo abre el reproductor.
  Future<void> open(ReadableDocument document, {int fromSegment = 0}) async {
    if (document.isEmpty) return;
    final current = state.document;
    if (current != null && current.id == document.id) {
      // El mismo documento, quizá con el texto cambiado —la pantalla se
      // reconstruyó después de editarlo—: se toma el nuevo para que el
      // resaltado caiga en su lugar, sin volver a empezar.
      if (current != document) _load(document);
      final index = state.segmentIndex.clamp(0, document.segments.length - 1);
      state = state.copyWith(
        document: document,
        segmentIndex: index,
        charInSegment: state.charInSegment.clamp(
          0,
          document.segments[index].spoken.length,
        ),
        panel: ReadAloudPanel.expanded,
      );
      return;
    }

    final generation = _cut();
    final wasPlaying = state.playing;
    _load(document);
    state = state.copyWith(
      document: document,
      segmentIndex: fromSegment.clamp(0, document.segments.length - 1),
      charInSegment: 0,
      playing: true,
      panel: ReadAloudPanel.expanded,
      failed: false,
    );
    if (wasPlaying) await _tts.stop();
    // Cada documento nuevo vuelve a fijar la voz y la velocidad: el motor
    // es uno solo para toda la app, y otro pudo haberlo usado entretanto.
    await _tts.setVoice(state.voice);
    await _tts.setSpeed(state.speed);
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

  /// Salta [delta] de habla —10 s para adelante o para atrás—, medidos con
  /// la voz y la velocidad de ahora, al comienzo de una palabra.
  ///
  /// La voz sintetizada no tiene una línea de tiempo (decisión A del plan):
  /// los segundos se pasan a caracteres con el ritmo que se viene midiendo
  /// en esta voz y a esta velocidad —ver [_SpeechRate]—, y se cuentan a lo
  /// largo del documento entero, así que un salto cruza pedazos.
  Future<void> skip(Duration delta) async {
    if (state.document == null || delta == Duration.zero) return;
    final here = _starts[state.segmentIndex] + state.charInSegment;
    final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
    final target = here + (seconds * _rate.value).round();
    if (target >= _total) return _finishAtEnd();

    var landing = _wordStartAt(target.clamp(0, _total));
    // Un salto siempre mueve: si el destino cae en la misma palabra —un
    // ritmo muy lento—, va a la de al lado.
    if (delta > Duration.zero && landing <= here) {
      landing = _nextWordStart(here);
    } else if (delta < Duration.zero && landing >= here) {
      landing = _previousWordStart(here);
    }
    if (landing >= _total) return _finishAtEnd();
    if (landing == here) return;

    final (index, char) = _locate(landing);
    state = state.copyWith(segmentIndex: index, charInSegment: char);
    if (state.playing) await _speak(restart: true);
  }

  Future<void> setSpeed(double speed) async {
    final value = speed.clamp(0.5, 2.0);
    if (value == state.speed) return;
    await _changeSpeed(value);
    await ref.read(narrationSettingsNotifierProvider.notifier).setSpeed(value);
  }

  Future<void> setVoice(NarrationVoice? voice) async {
    if (voice == state.voice) return;
    await _changeVoice(voice);
    await ref
        .read(narrationSettingsNotifierProvider.notifier)
        .selectVoice(voice);
  }

  void minimize() {
    if (state.document == null) return;
    state = state.copyWith(panel: ReadAloudPanel.minimized);
  }

  void expand() {
    if (state.document == null) return;
    state = state.copyWith(panel: ReadAloudPanel.expanded);
  }

  /// Deja de leer y cierra el reproductor.
  Future<void> close() async {
    if (state.document == null) return;
    _cut();
    _starts = const [];
    _total = 0;
    state = ReadAloudState(speed: state.speed, voice: state.voice);
    await _tts.stop();
  }

  // --- La lectura -----------------------------------------------------------

  bool get _atEnd {
    final segments = state.document!.segments;
    return state.segmentIndex >= segments.length - 1 &&
        state.charInSegment >= segments.last.spoken.length;
  }

  void _load(ReadableDocument document) {
    final starts = List<int>.filled(document.segments.length, 0);
    var total = 0;
    for (var i = 0; i < document.segments.length; i++) {
      starts[i] = total;
      total += document.segments[i].spoken.length;
    }
    _starts = starts;
    _total = total;
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

    _base = from;
    _lastWordChar = null;
    _lastWordAt = null;
    try {
      await _tts.speak(text);
    } on Exception {
      if (generation == _generation) _fail();
      return;
    }
    if (generation == _generation) _live = true;
  }

  /// El pedazo actual terminó: sigue con el próximo, o queda terminado al
  /// final —con el reproductor como estaba, para volver a empezar—.
  Future<void> _next() async {
    if (state.segmentIndex + 1 < state.document!.segments.length) {
      state = state.copyWith(
        segmentIndex: state.segmentIndex + 1,
        charInSegment: 0,
      );
      return _speak();
    }
    _cut();
    state = state.copyWith(
      charInSegment: state.currentSegment!.spoken.length,
      playing: false,
    );
  }

  /// Un salto más allá del final: queda terminado, como si hubiera llegado
  /// leyendo.
  Future<void> _finishAtEnd() async {
    final wasPlaying = state.playing;
    _cut();
    final segments = state.document!.segments;
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

    final now = _now();
    final lastChar = _lastWordChar;
    final lastAt = _lastWordAt;
    if (lastChar != null && lastAt != null && char > lastChar) {
      _rate.add(char - lastChar, now - lastAt);
    }
    _lastWordChar = char;
    _lastWordAt = now;

    if (char != state.charInSegment) {
      state = state.copyWith(charInSegment: char);
    }
  }

  // --- Voz y velocidad ------------------------------------------------------

  Future<void> _changeSpeed(double speed) async {
    // Lo medido sigue valiendo como punto de partida, escalado —la misma
    // voz al doble de velocidad dice el doble de caracteres por segundo—,
    // pero se vuelve a medir desde cero: el motor no escala exacto.
    _rate.reset(_rate.value * speed / state.speed);
    state = state.copyWith(speed: speed);
    await _tts.setSpeed(speed);
    // Que se oiga ya: el motor no cambia de velocidad a mitad de un pedido,
    // así que se vuelve a pedir desde la palabra en que iba.
    if (state.playing) await _speak(restart: true);
  }

  Future<void> _changeVoice(NarrationVoice? voice) async {
    // Otra voz es otro ritmo: lo medido no sirve ni escalado.
    _rate.reset(_SpeechRate.defaultFor(state.speed));
    state = state.copyWith(voice: voice, clearVoice: voice == null);
    await _tts.setVoice(voice);
    if (state.playing) await _speak(restart: true);
  }

  // --- Posiciones en el documento -------------------------------------------

  /// El pedazo y el carácter de su `spoken` de la posición [position] del
  /// documento. El final de un pedazo es el comienzo del siguiente.
  (int, int) _locate(int position) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_starts[middle] <= position) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return (low, position - _starts[low]);
  }

  String _spokenOf(int index) => state.document!.segments[index].spoken;

  /// El comienzo de la palabra en [position]; si cae en un espacio, el de la
  /// palabra que sigue.
  int _wordStartAt(int position) {
    final (index, char) = _locate(position);
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
    return _starts[index] + at;
  }

  /// El comienzo de la palabra después de la que empieza en [position]: el
  /// final del pedazo es el comienzo del siguiente.
  int _nextWordStart(int position) {
    final (index, char) = _locate(position);
    final spoken = _spokenOf(index);
    var at = char;
    while (at < spoken.length && !_isSpace(spoken.codeUnitAt(at))) {
      at++;
    }
    while (at < spoken.length && _isSpace(spoken.codeUnitAt(at))) {
      at++;
    }
    return _starts[index] + at;
  }

  /// El comienzo de la palabra antes de la que empieza en [position] —la
  /// última del pedazo anterior, si es la primera de este—.
  int _previousWordStart(int position) {
    if (position <= 0) return 0;
    var (index, char) = _locate(position);
    if (char == 0) {
      index--;
      char = _spokenOf(index).length;
    }
    final spoken = _spokenOf(index);
    var at = char;
    while (at > 0 && _isSpace(spoken.codeUnitAt(at - 1))) {
      at--;
    }
    while (at > 0 && !_isSpace(spoken.codeUnitAt(at - 1))) {
      at--;
    }
    return _starts[index] + at;
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

/// Cuántos caracteres por segundo dice la voz elegida a la velocidad
/// elegida, medido mientras habla (F25, decisión A).
///
/// Cada par de palabras seguidas que avisa el motor es una muestra: los
/// caracteres de una a la otra y el tiempo entre los dos avisos. Se suman
/// por separado con un peso que se desvanece —cada muestra nueva pesa 1 y
/// las anteriores se multiplican por [_decay]—, y el ritmo es el cociente:
/// una palabra corta o la pausa de una coma no mueven la cifra solas, y
/// pasadas unas decenas de palabras manda lo último que se oyó.
class _SpeechRate {
  /// Unas veinte palabras de memoria: 0,9²⁰ ≈ 0,12.
  static const _decay = 0.9;

  /// Menos de un segundo medido es muy poco para fiarse: hasta entonces vale
  /// el valor de partida.
  static const _minMeasured = 1.0;

  /// Entre dos palabras no pasan tres segundos hablando: si pasaron, el
  /// motor se trabó o el sistema lo demoró, y eso no dice nada del ritmo.
  static const _maxGap = 3.0;

  /// Unos 14 caracteres por segundo a 1×: ~150 palabras por minuto, el ritmo
  /// habitual de una voz en español, con palabras de cinco letras y su
  /// espacio. Es una estimación, no una medición: vale solo hasta medir la
  /// voz de verdad.
  static double defaultFor(double speed) => 14 * speed;

  double _chars = 0;
  double _seconds = 0;
  double _fallback = defaultFor(1);

  double get value => _seconds >= _minMeasured ? _chars / _seconds : _fallback;

  void add(int chars, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0 || seconds > _maxGap) return;
    _chars = _chars * _decay + chars;
    _seconds = _seconds * _decay + seconds;
  }

  /// Vuelve a medir desde cero, con [fallback] mientras tanto.
  void reset(double fallback) {
    _chars = 0;
    _seconds = 0;
    _fallback = fallback;
  }
}

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
