import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/data/audio/device_speech_voice_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/offline_speech_voice_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_encoder.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// F47, pasos 5 y 6: quienes hacen cada voz del audio generado —las sin
/// conexión con `sherpa_onnx`, las del teléfono con un motor del sistema
/// propio— y el codificador del sistema, por sus canales.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('las voces sin conexión', () {
    final daniela = OfflineVoiceCatalog.voices.firstWhere(
      (v) => v.locale == 'es-AR',
    );
    final id = SpeechVoiceIds.offline(daniela.id);
    late _FakeSynthesizer synthesizer;
    late Set<OfflineVoice> installed;
    late OfflineSpeechVoiceRenderer renderer;

    setUp(() {
      synthesizer = _FakeSynthesizer();
      installed = {daniela};
      renderer = OfflineSpeechVoiceRenderer(
        synthesizer: synthesizer,
        engineOf: (voice) async => installed.contains(voice)
            ? OfflineVoiceEngineConfig(
                family: voice.package.family,
                model: 'm',
                tokens: 't',
                dataDir: 'd',
              )
            : null,
      );
    });

    test('son las de prefijo offline:, listas si su paquete está bajado, y '
        'gratis', () async {
      expect(renderer.owns(id), isTrue);
      expect(renderer.owns('device:es-AR:x'), isFalse);
      expect(await renderer.isReady(id), isTrue);
      installed.clear();
      expect(await renderer.isReady(id), isFalse);
      expect(await renderer.isReady('offline:no-existe#0'), isFalse);
      expect(renderer.priceOf(id), isNull);
      // La versión sigue al paquete: otro modelo es otro audio.
      expect(renderer.versionOf(id), contains(daniela.package.sha256));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('dicen el tramo con su hablante, siempre a velocidad 1', () async {
      await renderer.render(voiceId: id, text: 'Hola', outputPath: 'o.wav');
      final call = synthesizer.calls.single;
      expect(call.speakerId, daniela.speakerId);
      expect(call.speed, 1);
      expect(call.text, 'Hola');
      expect(call.outputPath, 'o.wav');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('una borrada falta, y un motor que falla es una falla del '
        'motor', () async {
      installed.clear();
      await expectLater(
        renderer.render(voiceId: id, text: 'x', outputPath: 'o'),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.voiceMissing,
          ),
        ),
      );
      installed.add(daniela);
      synthesizer.fail = true;
      await expectLater(
        renderer.render(voiceId: id, text: 'x', outputPath: 'o'),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.engine,
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('las voces del teléfono', () {
    const channel = MethodChannel('prueba/device_speech');
    final calls = <MethodCall>[];
    Object? Function(MethodCall call)? reply;

    setUp(() {
      calls.clear();
      reply = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return reply?.call(call);
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('son las de prefijo device:, con nombre o sin él (la del acento), '
        'y le piden el archivo al motor propio', () async {
      const renderer = DeviceSpeechVoiceRenderer(channel: channel);
      expect(renderer.owns('device:es-AR:es-ar-x-local'), isTrue);
      expect(renderer.owns('device:es:'), isTrue);
      expect(renderer.owns('offline:x#0'), isFalse);
      expect(await renderer.isReady('device:es:'), isTrue);
      expect(renderer.priceOf('device:es:'), isNull);

      await renderer.render(
        voiceId: 'device:es-AR:es-ar-x-local',
        text: 'Hola',
        outputPath: '/t/a.wav',
      );
      expect(calls.single.method, 'synthesize');
      expect(calls.single.arguments, {
        'text': 'Hola',
        'locale': 'es-AR',
        'voice': 'es-ar-x-local',
        'output': '/t/a.wav',
      });
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('una voz que el teléfono no tiene falta; otra falla es del '
        'motor', () async {
      const renderer = DeviceSpeechVoiceRenderer(channel: channel);
      reply = (_) => throw PlatformException(code: 'voice');
      await expectLater(
        renderer.render(voiceId: 'device:es:', text: 'x', outputPath: 'o'),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.voiceMissing,
          ),
        ),
      );
      reply = (_) => throw PlatformException(code: 'synthesize');
      await expectLater(
        renderer.render(voiceId: 'device:es:', text: 'x', outputPath: 'o'),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.engine,
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('un motor que no avisa nunca no deja el trabajo colgado', () async {
      const renderer = DeviceSpeechVoiceRenderer(
        channel: channel,
        timeout: Duration(milliseconds: 50),
      );
      final never = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) => never.future);
      await expectLater(
        renderer.render(voiceId: 'device:es:', text: 'x', outputPath: 'o'),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.engine,
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('sin el canal (otra plataforma), la voz falta', () async {
      const renderer = DeviceSpeechVoiceRenderer(
        channel: MethodChannel('prueba/sin_canal'),
      );
      await expectLater(
        renderer.render(voiceId: 'device:es:', text: 'x', outputPath: 'o'),
        throwsA(
          isA<SpeechAudioException>().having(
            (e) => e.failure,
            'failure',
            SpeechAudioFailure.voiceMissing,
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('el codificador del sistema', () {
    const channel = MethodChannel('prueba/audio');
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('en Android le pide el M4A al canal de audio, con su tasa', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen = call;
            return null;
          });
      const encoder = PlatformSpeechAudioEncoder(
        channel: channel,
        android: true,
      );
      expect(await encoder.toM4a('/a.wav', '/a.m4a'), isTrue);
      expect(seen!.method, 'wavToM4a');
      expect(seen!.arguments, {
        'input': '/a.wav',
        'output': '/a.m4a',
        'bitRate': PlatformSpeechAudioEncoder.bitRate,
      });
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('el decodificador del sistema lleva el MP3 a un WAV de 24 kHz, por '
        'el PCM crudo de siempre, y borra el crudo', () async {
      final dir = Directory.systemTemp.createTempSync('dec');
      addTearDown(() => dir.deleteSync(recursive: true));
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen = call;
            final pcm = ByteData(2400 * 2);
            for (var i = 0; i < 2400; i++) {
              pcm.setInt16(i * 2, 8000, Endian.little);
            }
            File(
              (call.arguments as Map)['output'] as String,
            ).writeAsBytesSync(pcm.buffer.asUint8List());
            return [
              {
                'offset': 0,
                'length': 4800,
                'sampleRate': 24000,
                'channels': 1,
                'encoding': 'int16',
              },
            ];
          });
      const decoder = PlatformSpeechClipDecoder(
        channel: channel,
        android: true,
      );
      final wav = '${dir.path}${Platform.pathSeparator}t.wav';
      expect(await decoder.toWav('/nube.mp3', wav), isTrue);
      expect(seen!.method, 'toRawPcm');
      expect((seen!.arguments as Map)['input'], '/nube.mp3');
      expect(isWavFile(wav), isTrue);
      expect(File(wav).lengthSync(), 44 + 4800);
      expect(File('$wav.pcm').existsSync(), isFalse);

      // Sin audio, lanza; fuera de Android, no decodifica.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => <Object?>[]);
      await expectLater(decoder.toWav('/x.mp3', wav), throwsException);
      expect(
        await const PlatformSpeechClipDecoder(android: false).toWav('a', 'b'),
        isFalse,
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('si el sistema falla, lanza', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'wavToM4a'),
          );
      const encoder = PlatformSpeechAudioEncoder(
        channel: channel,
        android: true,
      );
      await expectLater(encoder.toM4a('/a.wav', '/a.m4a'), throwsException);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

typedef _Call = ({int speakerId, String text, double speed, String outputPath});

class _FakeSynthesizer implements OfflineSpeechSynthesizer {
  final calls = <_Call>[];
  bool fail = false;

  @override
  Future<Duration> synthesize({
    required OfflineVoiceEngineConfig engine,
    required int speakerId,
    required String text,
    required double speed,
    required String outputPath,
  }) async {
    if (fail) throw const OfflineSpeechException('roto');
    calls.add((
      speakerId: speakerId,
      text: text,
      speed: speed,
      outputPath: outputPath,
    ));
    return const Duration(seconds: 1);
  }

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() async {}
}
