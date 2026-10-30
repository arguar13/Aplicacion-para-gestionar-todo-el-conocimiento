import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

/// Lo que hay que pedirle a `flutter_tts` para que la voz hable a [speed]
/// —de 0,5× a 3×, la regla del lector (F47, paso 2)— en [platform], o en la
/// web con [web].
///
/// `flutter_tts` 4.2.5 no tiene una escala común: cada plataforma pasa el
/// número tal cual a su motor, con su propio "normal". Hasta F47 se pedía
/// siempre la mitad de la velocidad, que es lo justo solo en Android: en la
/// web 1× sonaba a la mitad, y en Windows 2× sonaba a 1,5×.
///
/// - **Android**: el motor recibe el doble de lo que se pide —su normal es
///   1, el nuestro 0,5— y acepta hasta 1,5 (3×).
/// - **Windows**: el motor suma 0,5 a lo que se pide —su normal es 1—, hasta
///   6×.
/// - **La web**: `SpeechSynthesisUtterance.rate`, con 1 de normal.
/// - **iOS y macOS**: `AVSpeechUtterance.rate`, con 0,5 de normal y 1 de
///   techo: más rápido que eso no se puede, y 3× suena como el techo.
double flutterTtsRate(
  double speed, {
  required TargetPlatform platform,
  required bool web,
}) {
  if (web) return speed.clamp(0.1, 10.0);
  return switch (platform) {
    TargetPlatform.android => (speed * 0.5).clamp(0.0, 1.5),
    TargetPlatform.windows => (speed - 0.5).clamp(0.0, 5.5),
    _ => (speed * 0.5).clamp(0.0, 1.0),
  };
}

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
    await _tts.setSpeechRate(
      flutterTtsRate(speed, platform: defaultTargetPlatform, web: kIsWeb),
    );
  }

  @override
  Future<void> speak(String text) async {
    _speaking = text;
    await _tts.speak(text);
  }

  /// El motor del sistema empieza a decir apenas se le pide: no hay nada que
  /// tener listo.
  @override
  Future<void> prepare(String text) async {}

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
