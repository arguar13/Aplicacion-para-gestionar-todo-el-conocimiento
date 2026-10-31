import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';

/// [TextToSpeechService] con las voces propias que viven en ElevenLabs (F47,
/// paso 4): cada tramo que pide el lector se le pide a ElevenLabs, llega en
/// MP3 y suena con [SpeechClipPlayer], como los de las voces sin conexión.
///
/// - **Cada tramo sale a ElevenLabs y gasta su cuota** (decisión F): el lector
///   lo marca, y antes de leer algo largo se dice el costo (ver
///   `CloudReadingGate`). Lo que se pide es solo el texto del tramo.
/// - **El próximo tramo se pide mientras suena el de ahora** ([prepare]): sin
///   eso, entre oración y oración se oiría la espera de la red. Un tramo
///   preparado y descartado —se saltó, se cambió de voz— ya se pagó.
/// - **La velocidad no se le pide a ElevenLabs**: el audio se genera a la
///   velocidad de la voz y suena más rápido o más lento. Así cambiar la
///   velocidad no vuelve a gastar.
/// - Cada tramo es un archivo en su carpeta, que se borra apenas suena.
class CloudTextToSpeechService implements TextToSpeechService {
  CloudTextToSpeechService({
    required VoiceCloud cloud,
    required SpeechClipPlayer player,
    required Future<String?> Function(NarrationVoice voice) cloudVoiceIdOf,
    required Future<Directory> Function() clipsDirectory,
  }) : _cloud = cloud,
       _player = player,
       _cloudVoiceIdOf = cloudVoiceIdOf,
       _clipsDirectory = clipsDirectory;

  final VoiceCloud _cloud;
  final SpeechClipPlayer _player;
  final Future<String?> Function(NarrationVoice voice) _cloudVoiceIdOf;
  final Future<Directory> Function() _clipsDirectory;

  final _events = StreamController<NarrationEvent>.broadcast();
  final _progress = StreamController<int>.broadcast();

  String? _voiceId;
  double _speed = 1;
  int _generation = 0;
  ({String voiceId, String text, Future<String> clip})? _prepared;
  Future<Directory>? _folder;
  var _clipNumber = 0;
  var _lastWord = -1;

  @override
  Future<List<NarrationVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    _voiceId = voice?.engine == NarrationEngine.cloud
        ? await _cloudVoiceIdOf(voice!)
        : null;
  }

  @override
  Future<void> setSpeed(double speed) async => _speed = speed;

  @override
  Future<void> prepare(String text) async {
    final voiceId = _voiceId;
    if (voiceId == null || text.trim().isEmpty) return;
    final prepared = _prepared;
    if (prepared != null &&
        prepared.voiceId == voiceId &&
        prepared.text == text) {
      return;
    }
    _discardPrepared();
    final clip = _fetch(voiceId, text);
    unawaited(clip.then<void>((_) {}, onError: (Object _) {}));
    _prepared = (voiceId: voiceId, text: text, clip: clip);
  }

  @override
  Future<void> speak(String text) async {
    final generation = ++_generation;
    await _player.stop();
    final voiceId = _voiceId;
    if (voiceId == null) {
      throw const VoiceCloudException(VoiceCloudFailure.voiceNotFound);
    }
    final prepared = _prepared;
    final Future<String> pending;
    if (prepared != null &&
        prepared.voiceId == voiceId &&
        prepared.text == text) {
      _prepared = null;
      pending = prepared.clip;
    } else {
      _discardPrepared();
      pending = _fetch(voiceId, text);
    }
    final path = await pending;
    if (generation != _generation) {
      _delete(path);
      return;
    }
    _lastWord = -1;
    unawaited(_play(generation, path, text));
  }

  Future<void> _play(int generation, String path, String text) async {
    try {
      final played = await _player.play(
        FileSpeechClip(path),
        speed: _speed,
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
      _delete(path);
    }
  }

  void _reportProgress(String text, double fraction) {
    if (_progress.isClosed || text.isEmpty) return;
    var at = (fraction * text.length).floor().clamp(0, text.length - 1);
    while (at > 0 && text.codeUnitAt(at - 1) != 0x20) {
      at--;
    }
    if (at <= _lastWord) return;
    _lastWord = at;
    _progress.add(at);
  }

  Future<String> _fetch(String voiceId, String text) async {
    final audio = await _cloud.speak(voiceId: voiceId, text: text);
    final folder = await (_folder ??= _cleanFolder());
    final file = File(p.join(folder.path, 'tramo-${_clipNumber++}.mp3'));
    await file.writeAsBytes(audio, flush: true);
    return file.path;
  }

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
    unawaited(prepared.clip.then(_delete, onError: (Object _) {}));
  }

  static void _delete(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
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
