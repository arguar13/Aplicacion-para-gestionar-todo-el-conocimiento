import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// [TextToSpeechService] con las voces sin conexión (F47, paso 3): cada tramo
/// que pide el lector se genera con [OfflineSpeechSynthesizer] en un WAV y
/// suena con [SpeechClipPlayer].
///
/// - **El próximo tramo se genera mientras suena el de ahora** ([prepare]): el
///   lector lo pide apenas empieza uno, y al pasar al siguiente ya está listo.
///   Sin eso, entre oración y oración habría la pausa de generarla.
/// - **Por qué palabra va** ([progress]) se estima por cuánto lleva sonando el
///   tramo: la voz generada no avisa palabra por palabra, y repartir el tiempo
///   por caracteres alcanza para resaltar, pausar y saltar ±10 s.
/// - Cada tramo es un archivo en su carpeta (`clipsDirectory`) que se borra
///   apenas suena —o se descarta—; lo que haya quedado de una vez anterior se
///   borra al empezar.
class OfflineTextToSpeechService implements TextToSpeechService {
  OfflineTextToSpeechService({
    required OfflineSpeechSynthesizer synthesizer,
    required SpeechClipPlayer player,
    required Future<OfflineVoiceEngineConfig?> Function(OfflineVoice voice)
    engineOf,
    required Future<Directory> Function() clipsDirectory,
  }) : _synthesizer = synthesizer,
       _player = player,
       _engineOf = engineOf,
       _clipsDirectory = clipsDirectory;

  final OfflineSpeechSynthesizer _synthesizer;
  final SpeechClipPlayer _player;
  final Future<OfflineVoiceEngineConfig?> Function(OfflineVoice voice)
  _engineOf;
  final Future<Directory> Function() _clipsDirectory;

  final _events = StreamController<NarrationEvent>.broadcast();
  final _progress = StreamController<int>.broadcast();

  OfflineVoice? _voice;
  double _speed = 1;

  /// Cada [speak] y cada [stop] suman uno: lo que llega de un tramo que ya no
  /// es el último —su fin, su avance, su audio recién generado— no cuenta.
  int _generation = 0;

  /// El tramo que se generó por adelantado ([prepare]). Vale para la voz y la
  /// velocidad de ahora: cambiar una u otra lo descarta.
  _Prepared? _prepared;
  Future<Directory>? _folder;
  var _clipNumber = 0;

  /// Dónde empieza la última palabra avisada del tramo de ahora.
  var _lastWord = -1;

  @override
  Future<List<NarrationVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    _voice = voice?.engine == NarrationEngine.offline
        ? OfflineVoiceCatalog.byId(voice!.name)
        : null;
    _discardPrepared();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    _discardPrepared();
  }

  @override
  Future<void> prepare(String text) async {
    final voice = _voice;
    if (voice == null || text.trim().isEmpty) return;
    if (_prepared?.text == text) return;
    _discardPrepared();
    final clip = _synthesize(voice, text);
    // Un tramo que no se pudo generar falla recién cuando se lo pide.
    unawaited(clip.then<void>((_) {}, onError: (Object _) {}));
    _prepared = _Prepared(text, clip);
  }

  /// Genera [text] —o toma el que ya estaba listo— y empieza a hacerlo sonar.
  /// Falla con [OfflineSpeechException] si no se pudo generar; si se pidió
  /// otro tramo o se cortó mientras tanto, no suena.
  @override
  Future<void> speak(String text) async {
    final generation = ++_generation;
    await _player.stop();
    final voice = _voice;
    if (voice == null) {
      throw const OfflineSpeechException('ninguna voz sin conexión elegida');
    }
    final prepared = _prepared;
    final Future<_Clip> pending;
    if (prepared != null && prepared.text == text) {
      _prepared = null;
      pending = prepared.clip;
    } else {
      _discardPrepared();
      pending = _synthesize(voice, text);
    }

    final _Clip clip;
    try {
      clip = await pending;
    } on OfflineSpeechException {
      rethrow;
    } on Object catch (error) {
      throw OfflineSpeechException('$error');
    }
    if (generation != _generation) {
      clip.delete();
      return;
    }
    _lastWord = -1;
    unawaited(_play(generation, clip, text));
  }

  Future<void> _play(int generation, _Clip clip, String text) async {
    try {
      final played = await _player.play(
        FileSpeechClip(clip.path),
        onProgress: (fraction) {
          if (generation == _generation) _reportProgress(text, fraction);
        },
      );
      if (played && generation == _generation && !_events.isClosed) {
        _events.add(NarrationEvent.completed);
      }
    } on Object {
      if (generation == _generation && !_events.isClosed) {
        _events.add(NarrationEvent.error);
      }
    } finally {
      clip.delete();
    }
  }

  /// La palabra en que va el tramo, por la parte que ya sonó: la que empieza
  /// antes de esa parte del texto. Una por palabra, nunca para atrás.
  void _reportProgress(String text, double fraction) {
    if (_progress.isClosed || text.isEmpty) return;
    var at = (fraction * text.length).floor().clamp(0, text.length - 1);
    while (at > 0 && !_isSpace(text.codeUnitAt(at - 1))) {
      at--;
    }
    if (at <= _lastWord) return;
    _lastWord = at;
    _progress.add(at);
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

  Future<_Clip> _synthesize(OfflineVoice voice, String text) async {
    final engine = await _engineOf(voice);
    if (engine == null) {
      throw OfflineSpeechException('la voz ${voice.id} no está en el teléfono');
    }
    final folder = await (_folder ??= _cleanFolder());
    final path = p.join(folder.path, 'tramo-${_clipNumber++}.wav');
    await _synthesizer.synthesize(
      engine: engine,
      speakerId: voice.speakerId,
      text: text,
      speed: _speed,
      outputPath: path,
    );
    return _Clip(path);
  }

  /// La carpeta de los tramos, vacía: lo de una vez anterior —la app se
  /// cerró mientras sonaba— ya no sirve.
  Future<Directory> _cleanFolder() async {
    final folder = await _clipsDirectory();
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    return folder;
  }

  void _discardPrepared() {
    final prepared = _prepared;
    _prepared = null;
    if (prepared == null) return;
    unawaited(
      prepared.clip.then((clip) => clip.delete(), onError: (Object _) {}),
    );
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
  }

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Stream<int> get progress => _progress.stream;

  @override
  Future<void> dispose() async {
    await stop();
    _discardPrepared();
    await _events.close();
    await _progress.close();
  }
}

class _Prepared {
  const _Prepared(this.text, this.clip);

  final String text;
  final Future<_Clip> clip;
}

/// Un tramo generado, en su archivo.
class _Clip {
  const _Clip(this.path);

  final String path;

  void delete() {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
