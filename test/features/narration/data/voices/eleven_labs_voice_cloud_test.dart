import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/eleven_labs_voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';

/// ElevenLabs grabada: contesta lo que se le dice, en orden, y anota cada
/// pedido con su cuerpo crudo. Nunca sale a internet.
class _Recorded implements HttpClientAdapter {
  final replies = <(int, Object, String)>[];
  final requests = <(RequestOptions, List<int>)>[];

  void json(Object body, {int status = 200}) =>
      replies.add((status, utf8.encode(jsonEncode(body)), 'application/json'));

  void bytes(List<int> body) => replies.add((200, body, 'audio/mpeg'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = <int>[];
    if (requestStream != null) await requestStream.forEach(body.addAll);
    requests.add((options, body));
    final (status, reply, type) = replies.removeAt(0);
    return ResponseBody.fromBytes(
      reply as List<int>,
      status,
      headers: {
        Headers.contentTypeHeader: [type],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Recorded server;
  late String? key;
  late ElevenLabsVoiceCloud cloud;

  setUp(() {
    server = _Recorded();
    key = 'sk-prueba';
    cloud = ElevenLabsVoiceCloud(
      dio: Dio()..httpClientAdapter = server,
      key: () async => key,
    );
  });

  RequestOptions lastRequest() => server.requests.last.$1;
  Map<String, Object?> lastJson() =>
      jsonDecode(utf8.decode(server.requests.last.$2)) as Map<String, Object?>;

  test('la clave va en xi-api-key, y nada más de la persona', () async {
    server.json({
      'tier': 'starter',
      'character_count': 1200,
      'character_limit': 30000,
      'next_character_count_reset_unix': 1798761600,
      'can_use_instant_voice_cloning': true,
      'voice_limit': 10,
      'voice_slots_used': 2,
    });
    final account = await cloud.account();
    final request = lastRequest();
    expect(
      request.uri.toString(),
      'https://api.elevenlabs.io/v1/user/subscription',
    );
    expect(request.method, 'GET');
    expect(request.headers['xi-api-key'], 'sk-prueba');
    expect(
      request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(account.tier, 'starter');
    expect(account.creditsLeft, 28800);
    expect(account.canClone, isTrue);
    expect(account.hasVoiceSlot, isTrue);
    expect(account.resetsAt, DateTime.utc(2027));
  });

  test('sin clave no se pide nada', () async {
    key = null;
    await expectLater(
      cloud.account(),
      throwsA(
        isA<VoiceCloudException>().having(
          (e) => e.failure,
          'failure',
          VoiceCloudFailure.noKey,
        ),
      ),
    );
    expect(server.requests, isEmpty);
  });

  test(
    'clonar manda el nombre y el archivo, sin limpiar el ruido allá',
    () async {
      final folder = Directory.systemTemp.createTempSync('elevenlabs-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final sample = File(p.join(folder.path, 'grabacion.wav'))
        ..writeAsBytesSync([82, 73, 70, 70]);
      server.json({'voice_id': 'v-123', 'requires_verification': false});
      final id = await cloud.cloneVoice(
        name: 'Papá',
        samplePath: sample.path,
        description: 'con permiso',
      );
      expect(id, 'v-123');
      final request = lastRequest();
      expect(request.uri.path, '/v1/voices/add');
      expect(request.method, 'POST');
      final body = latin1.decode(server.requests.last.$2);
      expect(body, contains('name="name"'));
      expect(body, contains('name="files"; filename="grabacion.wav"'));
      expect(body, contains('name="remove_background_noise"'));
      expect(body, contains('RIFF'));
    },
  );

  test('diseñar pide tres propuestas con la descripción y el texto, y trae '
      'su audio', () async {
    server.json({
      'previews': [
        {
          'audio_base_64': base64Encode([1, 2, 3]),
          'generated_voice_id': 'g-1',
          'media_type': 'audio/mpeg',
          'duration_secs': 2.5,
          'language': 'es',
        },
      ],
      'text': 'x',
    });
    final previews = await cloud.designPreviews(
      description: 'mujer serena',
      text: 'un texto de muestra',
    );
    expect(lastRequest().uri.path, '/v1/text-to-voice/design');
    expect(lastJson(), {
      'voice_description': 'mujer serena',
      'text': 'un texto de muestra',
    });
    expect(previews.single.generatedVoiceId, 'g-1');
    expect(previews.single.audio, [1, 2, 3]);
    expect(previews.single.duration, const Duration(milliseconds: 2500));
    expect(previews.single.extension, 'mp3');
  });

  test('guardar la elegida', () async {
    server.json({'voice_id': 'v-9'});
    final id = await cloud.saveDesignedVoice(
      name: 'Serena',
      description: 'mujer serena',
      generatedVoiceId: 'g-1',
    );
    expect(id, 'v-9');
    expect(lastRequest().uri.path, '/v1/text-to-voice');
    expect(lastJson(), {
      'voice_name': 'Serena',
      'voice_description': 'mujer serena',
      'generated_voice_id': 'g-1',
    });
  });

  test('leer manda solo el texto, con el modelo que habla español', () async {
    server.bytes([9, 9, 9]);
    final audio = await cloud.speak(voiceId: 'v/1', text: 'Hola.');
    expect(audio, [9, 9, 9]);
    expect(lastRequest().uri.path, '/v1/text-to-speech/v%2F1');
    expect(lastRequest().uri.queryParameters['output_format'], 'mp3_44100_128');
    expect(lastJson(), {'text': 'Hola.', 'model_id': 'eleven_multilingual_v2'});
  });

  test('un texto más largo que un pedido no sale', () async {
    await expectLater(
      cloud.speak(voiceId: 'v', text: 'a' * 10001),
      throwsA(isA<VoiceCloudException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('borrar; una voz que ya no estaba no es un error', () async {
    server.json({'status': 'ok'});
    await cloud.deleteVoice('v-1');
    expect(lastRequest().method, 'DELETE');
    expect(lastRequest().uri.path, '/v1/voices/v-1');
    server.json({
      'detail': {'code': 'voice_not_found', 'message': 'no'},
    }, status: 404);
    await cloud.deleteVoice('v-1');
  });

  group('cada error, por lo que es', () {
    Future<VoiceCloudFailure> failureOf(int status, [String? code]) async {
      server.json({
        'detail': {'code': ?code, 'message': 'algo'},
      }, status: status);
      try {
        await cloud.account();
      } on VoiceCloudException catch (error) {
        return error.failure;
      }
      fail('no falló');
    }

    test('la clave, la cuota, el plan y lo demás', () async {
      expect(
        await failureOf(401, 'invalid_api_key'),
        VoiceCloudFailure.invalidKey,
      );
      expect(
        await failureOf(401, 'quota_exceeded'),
        VoiceCloudFailure.noCredits,
      );
      expect(
        await failureOf(402, 'insufficient_credits'),
        VoiceCloudFailure.noCredits,
      );
      expect(
        await failureOf(403, 'subscription_required'),
        VoiceCloudFailure.planRequired,
      );
      expect(await failureOf(404), VoiceCloudFailure.voiceNotFound);
      expect(await failureOf(409), VoiceCloudFailure.busy);
      expect(await failureOf(429), VoiceCloudFailure.busy);
      expect(await failureOf(422), VoiceCloudFailure.rejected);
      expect(await failureOf(503), VoiceCloudFailure.unavailable);
      expect(await failureOf(418), VoiceCloudFailure.unknown);
    });

    test('sin conexión', () async {
      final broken = ElevenLabsVoiceCloud(
        dio: Dio()..httpClientAdapter = _Broken(),
        key: () async => 'k',
      );
      await expectLater(
        broken.account(),
        throwsA(
          isA<VoiceCloudException>().having(
            (e) => e.failure,
            'failure',
            VoiceCloudFailure.network,
          ),
        ),
      );
    });
  });
}

class _Broken implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw const SocketException('sin red');

  @override
  void close({bool force = false}) {}
}
