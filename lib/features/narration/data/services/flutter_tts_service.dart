import 'dart:async';

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

/// La velocidad "normal" del motor nativo, en la escala 0.0–1.0 que usa
/// `flutter_tts`. El multiplicador de [TextToSpeechService.setSpeed] —de
/// 0.5x a 2.0x— se traduce contra este valor, así que 1.0x cae exactamente
/// en la velocidad que el motor ya trae por defecto.
const _kBaseRate = 0.5;

/// [TextToSpeechService] sobre `flutter_tts`: el motor de voz nativo de
/// Android, iOS, macOS, Windows y Web. Ver la decisión 28 en
/// docs/arquitectura.md.
class FlutterTtsService implements TextToSpeechService {
  FlutterTtsService([FlutterTts? tts]) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(() => _emit(NarrationEvent.completed));
    _tts.setErrorHandler((dynamic message) => _emit(NarrationEvent.error));
    _tts.setCancelHandler(() {});
    _tts.setProgressHandler(_onProgress);
  }

  final FlutterTts _tts;
  final _events = StreamController<NarrationEvent>.broadcast();
  final _progress = StreamController<int>.broadcast();

  /// El texto del último [speak], para reconocer de qué lectura es cada
  /// aviso de progreso (F25).
  String? _speaking;

  void _emit(NarrationEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// El motor dice en qué palabra va de **la lectura que la dijo**: el
  /// aviso trae el texto entero de esa lectura. Uno que llega tarde de una
  /// lectura ya cortada —el canal con la plataforma es asincrónico, y en
  /// Android el aviso sale de otro hilo— trae un texto que no es el del
  /// último [speak]: se descarta acá, para que su posición nunca se lea
  /// como la de la lectura nueva.
  void _onProgress(String text, int start, int end, String word) {
    if (text != _speaking || _progress.isClosed) return;
    _progress.add(start);
  }

  @override
  Future<List<NarrationVoice>> getVoices() async {
    final Object? raw;
    try {
      raw = await _tts.getVoices;
      // El plugin no tiene un motor de voz instalado, o la plataforma no
      // implementa esta llamada: una lista vacía —"no hay entre qué
      // elegir"— es más honesto que tumbar la pantalla de ajustes.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return const [];
    }
    if (raw is! List) return const [];

    final voices = <NarrationVoice>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final locale = entry['locale'];
      if (name is String && locale is String) {
        voices.add(NarrationVoice(name: name, locale: locale));
      }
    }
    return voices;
  }

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    if (voice != null) {
      await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      return;
    }
    // Volver a la voz del sistema: antes no se hacía nada, y quedaba sonando
    // la última voz elegida aunque se hubiera pedido la del sistema (F25).
    // Windows y la web no implementan `clearVoice` en flutter_tts 4.2.5
    // —uno contesta "no implementado", la otra tira `Unimplemented`—; ahí
    // la voz vuelve a la del sistema recién con la app reiniciada.
    try {
      await _tts.clearVoice();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    final rate = (speed * _kBaseRate).clamp(0.0, 1.0);
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> speak(String text) async {
    _speaking = text;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Stream<int> get progress => _progress.stream;

  @override
  Future<void> dispose() async {
    await _tts.stop();
    await _events.close();
    await _progress.close();
  }
}
