import 'dart:async';

import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

/// Un motor de voz de mentira: no habla nada de verdad, solo anota qué se
/// le pidió y deja que el test decida cuándo "termina" de leer.
///
/// `flutter_tts` habla con un canal de plataforma que no existe en un
/// test —mismo motivo que `FakeFileChooser`—, y hace falta poder disparar
/// a mano el evento de "terminó" y el aviso de qué palabra va diciendo
/// (F25), para probar que quien lo usa encadena el próximo fragmento solo y
/// sabe dónde retomar.
class FakeTextToSpeechService implements TextToSpeechService {
  FakeTextToSpeechService({this.voices = const []});

  /// Lo que devuelve [getVoices].
  final List<NarrationVoice> voices;

  /// Cada texto que se le pidió leer, en orden.
  final spoken = <String>[];

  /// La última voz elegida con [setVoice]. `null` hasta el primer llamado,
  /// indistinguible de "se eligió la voz del sistema" — los tests que
  /// necesiten esa distinción comprueban [voiceSetCount] aparte.
  NarrationVoice? lastVoice;
  int voiceSetCount = 0;

  /// La última velocidad elegida con [setSpeed].
  double? lastSpeed;

  int stopCount = 0;
  bool disposed = false;

  final _events = StreamController<NarrationEvent>.broadcast();
  final _progress = StreamController<int>.broadcast();

  /// Simula que el motor terminó de leer lo último que se le pidió.
  void completeCurrent() => _events.add(NarrationEvent.completed);

  /// Simula que el motor falló a mitad de lectura.
  void failCurrent() => _events.add(NarrationEvent.error);

  /// Simula que el motor empezó a decir la palabra que arranca en [start]
  /// del último texto pedido.
  void emitProgress(int start) => _progress.add(start);

  @override
  Future<List<NarrationVoice>> getVoices() async => voices;

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    lastVoice = voice;
    voiceSetCount++;
  }

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Stream<int> get progress => _progress.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
    await _progress.close();
  }
}
