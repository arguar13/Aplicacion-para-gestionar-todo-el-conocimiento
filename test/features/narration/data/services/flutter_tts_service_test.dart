import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sinapsis/features/narration/data/services/flutter_tts_service.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';

/// El `FlutterTts` de verdad, con el canal nativo atendido acá: lo que el
/// motor "avisa" se le hace llegar por `platformCallHandler`, el mismo
/// camino que usa la plataforma.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late List<MethodCall> calls;
  late FlutterTts flutterTts;
  late FlutterTtsService service;
  Object? Function(MethodCall call) answer = (_) => 1;

  setUp(() {
    calls = [];
    answer = (_) => 1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer(call);
        });
    flutterTts = FlutterTts();
    service = FlutterTtsService(flutterTts);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> sayWord(String text, int start, String word) =>
      flutterTts.platformCallHandler(
        MethodCall('speak.onProgress', {
          'text': text,
          'start': '$start',
          'end': '${start + word.length}',
          'word': word,
        }),
      );

  group('progress (F25)', () {
    test('avisa dónde empieza cada palabra de lo último pedido', () async {
      final offsets = <int>[];
      final subscription = service.progress.listen(offsets.add);
      addTearDown(subscription.cancel);

      await service.speak('Hola mundo lindo');
      await sayWord('Hola mundo lindo', 0, 'Hola');
      await sayWord('Hola mundo lindo', 5, 'mundo');
      await pumpEventQueue();

      expect(offsets, [0, 5]);
    });

    test('descarta lo que llega tarde de una lectura anterior', () async {
      final offsets = <int>[];
      final subscription = service.progress.listen(offsets.add);
      addTearDown(subscription.cancel);

      await service.speak('Lectura vieja');
      await service.speak('La nueva');
      await sayWord('Lectura vieja', 8, 'vieja');
      await sayWord('La nueva', 3, 'nueva');
      await pumpEventQueue();

      expect(offsets, [3]);
    });

    test('nada pedido todavía: ningún aviso cuenta', () async {
      final offsets = <int>[];
      final subscription = service.progress.listen(offsets.add);
      addTearDown(subscription.cancel);

      await sayWord('Algo', 0, 'Algo');
      await pumpEventQueue();

      expect(offsets, isEmpty);
    });
  });

  group('setVoice', () {
    test('una voz se elige por nombre y región', () async {
      await service.setVoice(
        const NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR'),
      );

      expect(calls.single.method, 'setVoice');
      expect(calls.single.arguments, {
        'name': 'es-ar-x-local',
        'locale': 'es-AR',
      });
    });

    test('sin voz vuelve a la del sistema', () async {
      await service.setVoice(null);

      expect(calls.single.method, 'clearVoice');
    });

    test('donde no se puede volver a la del sistema, no falla', () async {
      answer = (call) => throw MissingPluginException();
      await expectLater(service.setVoice(null), completes);

      answer = (call) => throw PlatformException(code: 'Unimplemented');
      await expectLater(service.setVoice(null), completes);
    });
  });
}
