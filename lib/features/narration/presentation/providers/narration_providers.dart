import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/data/services/flutter_tts_service.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

/// Deliberadamente NO autoDispose: cerrar y volver a abrir el canal nativo
/// con el motor de voz en cada pantalla que lee algo en voz alta sería
/// trabajo de más sin ningún beneficio — a diferencia de la sesión de
/// Gemma, acá no hay nada pesado que liberar entre usos.
final textToSpeechServiceProvider = Provider<TextToSpeechService>((ref) {
  final service = FlutterTtsService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Las voces instaladas en este dispositivo, para el panel de ajustes de
/// [NarrationPlayer]. `autoDispose`: no tiene sentido mantenerlas en
/// memoria cuando no hay ningún panel de ajustes abierto.
final narrationVoicesProvider =
    FutureProvider.autoDispose<List<NarrationVoice>>((ref) {
      return ref.watch(textToSpeechServiceProvider).getVoices();
    });
