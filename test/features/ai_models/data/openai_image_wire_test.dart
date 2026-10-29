import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_image_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

import '../../../support/fake_cloud_server.dart';

final _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 5, 6, 7];

/// La respuesta de la Image API como la documenta OpenAI (2026-10-28).
String _images() => jsonEncode({
  'created': 1761660000,
  'data': [
    {'b64_json': base64Encode(_jpeg)},
  ],
  'usage': {
    'input_tokens': 50,
    'output_tokens': 1056,
    'total_tokens': 1106,
    'input_tokens_details': {'text_tokens': 50, 'image_tokens': 0},
  },
});

String _error({required String message, String? type, String? code}) =>
    jsonEncode({
      'error': {'message': message, 'type': ?type, 'code': ?code},
    });

const _request = ImageWireRequest(
  model: 'gpt-image-2.5-flare',
  prompt: 'Un faro al atardecer',
  aspect: IllustrationAspect.wide,
);

void main() {
  late FakeCloudServer openAi;
  late OpenAiImageWire wire;

  setUp(() {
    openAi = FakeCloudServer();
    wire = OpenAiImageWire(dio: Dio()..httpClientAdapter = openAi);
  });

  test('el pedido: la Image API, la clave en la cabecera, el tamaño de la '
      'familia, la calidad por tamaño y JPEG', () async {
    openAi.reply(_images());

    await wire.generate(_request, const ImageWireAccess(key: 'sk-SECRETA'));

    final sent = openAi.requests.single;
    expect(sent.uri.toString(), 'https://api.openai.com/v1/images/generations');
    expect(sent.headers['authorization'], 'Bearer sk-SECRETA');
    expect(openAi.bodies.single, {
      'model': 'gpt-image-2.5-flare',
      'prompt': 'Un faro al atardecer',
      'n': 1,
      'size': '1536x1024',
      'quality': 'medium',
      'output_format': 'jpeg',
    });
    expect(OpenAiImageWire.sizeFor(IllustrationAspect.tall), '1024x1536');
    expect(OpenAiImageWire.sizeFor(IllustrationAspect.square), '1024x1024');
    expect(OpenAiImageWire.qualityFor(IllustrationSize.small), 'low');
    expect(OpenAiImageWire.qualityFor(IllustrationSize.large), 'high');
  });

  test('DALL·E: sin calidad ni formato de GPT Image, y en base64', () {
    final body = OpenAiImageWire.bodyOf(
      const ImageWireRequest(model: 'dall-e-3', prompt: 'x'),
    );
    expect(body.containsKey('quality'), isFalse);
    expect(body['response_format'], 'b64_json');
  });

  test('la respuesta: los bytes de b64_json y los tokens de usage', () async {
    openAi.reply(_images());

    final image = await wire.generate(
      _request,
      const ImageWireAccess(key: 'k'),
    );

    expect(image.bytes, _jpeg);
    expect(image.mimeType, 'image/jpeg');
    expect(image.inputTokens, 50);
    expect(image.outputTokens, 1056);
  });

  test('sin b64_json: no devolvió imagen', () {
    expect(
      () => OpenAiImageWire.parse({'data': <Object>[]}, model: 'm'),
      throwsA(_failure(ImageFailure.noImage)),
    );
  });

  group('los errores', () {
    Future<void> expectFailure(
      String body,
      int status,
      ImageFailure failure,
    ) async {
      openAi.reply(body, status: status);
      await expectLater(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(failure)),
      );
    }

    test('la organización sin verificar, con esas palabras', () async {
      await expectFailure(
        _error(
          message:
              'Your organization must be verified to use the model '
              '`gpt-image-2.5-flare`. Please go to: '
              'https://platform.openai.com/settings/organization/general '
              'and click on Verify Organization.',
          type: 'invalid_request_error',
        ),
        403,
        ImageFailure.orgUnverified,
      );
    });

    test('rechazado por moderación', () async {
      await expectFailure(
        _error(
          message: 'Your request was rejected by the safety system.',
          type: 'image_generation_user_error',
          code: 'moderation_blocked',
        ),
        400,
        ImageFailure.contentRefused,
      );
    });

    test('rechazado por moderación, aunque venga solo el código', () async {
      await expectFailure(
        _error(message: 'Blocked.', code: 'moderation_blocked'),
        400,
        ImageFailure.contentRefused,
      );
    });

    test('sin saldo: sin créditos (no el tope por minuto)', () async {
      await expectFailure(
        _error(
          message: 'You exceeded your current quota.',
          type: 'insufficient_quota',
          code: 'insufficient_quota',
        ),
        429,
        ImageFailure.noCredits,
      );
    });

    test('el tope por minuto', () async {
      await expectFailure(
        _error(
          message: 'Rate limit reached. Please try again in 6s.',
          code: 'rate_limit_exceeded',
        ),
        429,
        ImageFailure.rateLimited,
      );
    });

    test('la clave mala', () async {
      await expectFailure(
        _error(message: 'Incorrect API key.', code: 'invalid_api_key'),
        401,
        ImageFailure.invalidKey,
      );
    });

    test('un 403 que no es la verificación: sin permiso', () async {
      await expectFailure(
        _error(message: 'Country not supported.'),
        403,
        ImageFailure.forbidden,
      );
    });

    test('caído de su lado', () async {
      await expectFailure(
        _error(message: 'Server error', type: 'server_error'),
        503,
        ImageFailure.unavailable,
      );
    });
  });

  test('los modelos de imagen: los GPT Image y DALL·E, sin los de texto ni '
      'las versiones fijadas; el recomendado, el Flare más nuevo', () async {
    openAi.reply(
      jsonEncode({
        'data': [
          {'id': 'gpt-5.2'},
          {'id': 'gpt-image-1-mini'},
          {'id': 'gpt-image-2.5-flare'},
          {'id': 'gpt-image-2.5-flare-2026-09-08'},
          {'id': 'gpt-image-2.5-sunburst'},
          {'id': 'dall-e-3'},
          {'id': 'whisper-1'},
        ],
      }),
    );

    final models = await wire.listImageModels(const ImageWireAccess(key: 'k'));

    expect(models.map((m) => m.id), [
      'dall-e-3',
      'gpt-image-1-mini',
      'gpt-image-2.5-flare',
      'gpt-image-2.5-sunburst',
    ]);
    expect(
      models.firstWhere((m) => m.id == 'gpt-image-2.5-flare').displayName,
      'GPT Image 2.5 Flare',
    );
    expect(wire.recommendedImageModel(models), 'gpt-image-2.5-flare');
    ImageModelInfo m(String id) => ImageModelInfo(id: id, displayName: id);
    expect(
      wire.recommendedImageModel([m('gpt-image-1-mini'), m('gpt-image-1.5')]),
      'gpt-image-1.5',
    );
    expect(wire.recommendedImageModel([m('dall-e-3')]), 'dall-e-3');
  });
}

Matcher _failure(ImageFailure failure) => isA<ImageGenerationException>()
    .having((e) => e.failure, 'failure', failure);
