import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/data/voices/method_channel_voice_recorder.dart';
import 'package:sinapsis/features/narration/domain/services/voice_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lee el nivel y el tiempo de cada evento, y deja de lado lo que no '
      'entiende', () {
    final progress = recordingProgressFrom({'level': 0.4, 'elapsedMs': 1500})!;
    expect(progress.level, 0.4);
    expect(progress.elapsed, const Duration(milliseconds: 1500));
    expect(recordingProgressFrom({'level': 3, 'elapsedMs': 0})!.level, 1);
    expect(recordingProgressFrom({'level': 'alto'}), isNull);
    expect(recordingProgressFrom('nada'), isNull);
  });

  test('sin el canal —la web, Windows— no se graba', () async {
    const recorder = MethodChannelVoiceRecorder(
      methods: MethodChannel('prueba/sin-canal'),
    );
    expect(await recorder.isAvailable(), isFalse);
    expect(await recorder.requestPermission(), isFalse);
    await recorder.stop();
  });

  test(
    'pide el permiso y graba por el canal, con el archivo y el límite',
    () async {
      const methods = MethodChannel('prueba/grabar');
      const events = EventChannel('prueba/grabar/eventos');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMethodCallHandler(methods, (call) async {
              calls.add(call);
              return true;
            })
            ..setMockStreamHandler(
              events,
              MockStreamHandler.inline(
                onListen: (arguments, sink) {
                  calls.add(MethodCall('listen', arguments));
                  sink
                    ..success({'level': 0.2, 'elapsedMs': 100})
                    ..error(code: 'busy')
                    ..endOfStream();
                },
              ),
            );
      addTearDown(() {
        messenger
          ..setMockMethodCallHandler(methods, null)
          ..setMockStreamHandler(events, null);
      });
      const recorder = MethodChannelVoiceRecorder(
        methods: methods,
        events: events,
      );
      expect(await recorder.requestPermission(), isTrue);
      final received = <Object>[];
      await recorder
          .record(
            outputPath: 'grabacion.wav',
            limit: const Duration(minutes: 3),
          )
          .handleError(received.add)
          .forEach(received.add);
      expect(calls.last.arguments, {
        'path': 'grabacion.wav',
        'limitMs': 180000,
      });
      expect((received.first as RecordingProgress).level, 0.2);
      expect(
        received.last,
        isA<VoiceRecorderException>().having((e) => e.code, 'code', 'busy'),
      );
    },
  );
}
