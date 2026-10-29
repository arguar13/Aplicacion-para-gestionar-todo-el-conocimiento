import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/hugging_face_image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';

import '../../../support/fake_cloud_server.dart';

final _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2];

/// Lo que dice el Hub de un modelo (como lo devolvía el 2026-10-28).
String _mapping(Map<String, Object?> providers) =>
    jsonEncode({'id': 'x', 'inferenceProviderMapping': providers});

Map<String, Object?> _live(String id, {String task = 'text-to-image'}) => {
  'status': 'live',
  'providerId': id,
  'task': task,
};

ImageWireRequest _request(String route) => ImageWireRequest(
  model: 'black-forest-labs/FLUX.1-schnell',
  prompt: 'Un faro',
  aspect: IllustrationAspect.wide,
  route: route,
);

void main() {
  late FakeCloudServer hf;
  late HuggingFaceImageWire wire;
  const access = ImageWireAccess(key: 'hf_SECRETO');

  setUp(() {
    hf = FakeCloudServer();
    wire = HuggingFaceImageWire(
      dio: Dio()..httpClientAdapter = hf,
      pollInterval: Duration.zero,
      maxPolls: 3,
    );
  });

  group('los modelos', () {
    test('prueba el token y arma la lista curada con el proveedor que hoy '
        'dibuja cada uno; el que ninguno dibuja desde texto no va', () async {
      hf
        ..reply(jsonEncode({'name': 'armando'}))
        // FLUX.1 [schnell]: Nscale antes que fal.ai (contesta de una).
        ..reply(
          _mapping({
            'fal-ai': _live('fal-ai/flux/schnell'),
            'nscale': _live('black-forest-labs/FLUX.1-schnell'),
            'deepinfra': {'status': 'error', 'providerId': 'x', 'task': 't'},
          }),
        )
        // Z-Image: solo proveedores que la app no habla, y fal.ai.
        ..reply(
          _mapping({
            'wavespeed': _live('wavespeed-ai/z-image/turbo'),
            'fal-ai': _live('fal-ai/z-image/turbo'),
          }),
        )
        // SD 3.5: Replicate (fal.ai con error).
        ..reply(
          _mapping({
            'fal-ai': {
              'status': 'error',
              'providerId': 'fal-ai/sd35',
              'task': 'text-to-image',
            },
            'replicate': _live('stability-ai/stable-diffusion-3.5-large'),
          }),
        )
        // Sana: solo para editar imágenes, no desde texto.
        ..reply(
          _mapping({
            'fal-ai': _live('fal-ai/sana/edit', task: 'image-to-image'),
          }),
        );

      final models = await wire.listImageModels(access);

      expect(hf.requests.first.uri.toString(), contains('/api/whoami-v2'));
      expect(hf.requests.first.headers['authorization'], 'Bearer hf_SECRETO');
      expect(
        hf.requests[1].uri.toString(),
        startsWith(
          'https://huggingface.co/api/models/black-forest-labs/FLUX.1-schnell',
        ),
      );
      expect(hf.requests[1].uri.queryParameters, {
        'expand[]': 'inferenceProviderMapping',
      });
      expect(models.map((m) => (m.id, m.route)), [
        (
          'black-forest-labs/FLUX.1-schnell',
          'nscale|black-forest-labs/FLUX.1-schnell',
        ),
        ('Tongyi-MAI/Z-Image-Turbo', 'fal-ai|fal-ai/z-image/turbo'),
        (
          'stabilityai/stable-diffusion-3.5-large',
          'replicate|stability-ai/stable-diffusion-3.5-large',
        ),
      ]);
      expect(models.first.displayName, kOpenImageModels.first.name);
      expect(
        wire.recommendedImageModel(models),
        'black-forest-labs/FLUX.1-schnell',
      );
    });

    test('el Hub también puede dar la lista como arreglo', () {
      expect(
        HuggingFaceImageWire.routeOf({
          'inferenceProviderMapping': [
            {'provider': 'fal-ai', ..._live('fal-ai/qwen-image')},
          ],
        }),
        'fal-ai|fal-ai/qwen-image',
      );
      expect(HuggingFaceImageWire.routeOf({'id': 'x'}), isNull);
    });

    test('un token malo: la clave', () {
      hf.reply(jsonEncode({'error': 'Invalid credentials'}), status: 401);
      expect(
        wire.listImageModels(access),
        throwsA(_failure(ImageFailure.invalidKey)),
      );
    });
  });

  group('dibujar', () {
    test('hf-inference: los bytes tal cual, con el ancho y el alto', () async {
      hf.replyBytes(_png);

      final image = await wire.generate(
        _request('hf-inference|black-forest-labs/FLUX.1-schnell'),
        access,
      );

      expect(
        hf.requests.single.uri.toString(),
        'https://router.huggingface.co/hf-inference/models/'
        'black-forest-labs/FLUX.1-schnell',
      );
      expect(hf.bodies.single, {
        'inputs': 'Un faro',
        'parameters': {'width': 1024, 'height': 576},
      });
      expect(image.bytes, _png);
      expect(image.mimeType, 'image/png');
    });

    test('Nscale: el formato de imágenes de OpenAI', () async {
      hf.reply(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(_png)},
          ],
        }),
      );

      final image = await wire.generate(
        _request('nscale|black-forest-labs/FLUX.1-schnell'),
        access,
      );

      expect(
        hf.requests.single.uri.toString(),
        'https://router.huggingface.co/nscale/v1/images/generations',
      );
      expect(hf.bodies.single, {
        'model': 'black-forest-labs/FLUX.1-schnell',
        'prompt': 'Un faro',
        'response_format': 'b64_json',
        'size': '1024x576',
      });
      expect(image.bytes, _png);
    });

    test('fal.ai: la cola, el estado hasta que termina, el resultado y la '
        'imagen bajada sin el token', () async {
      hf
        ..reply(
          jsonEncode({
            'request_id': 'r1',
            'status': 'IN_QUEUE',
            'response_url': 'https://queue.fal.run/fal-ai/flux/requests/r1',
          }),
        )
        ..reply(jsonEncode({'status': 'IN_PROGRESS'}))
        ..reply(jsonEncode({'status': 'COMPLETED'}))
        ..reply(
          jsonEncode({
            'images': [
              {
                'url': 'https://v3.fal.media/files/faro.png',
                'content_type': 'image/png',
              },
            ],
            'has_nsfw_concepts': [false],
          }),
        )
        ..replyBytes(_png);

      final image = await wire.generate(
        _request('fal-ai|fal-ai/flux/schnell'),
        access,
      );

      final urls = [for (final r in hf.requests) r.uri.toString()];
      String queue(String path) =>
          'https://router.huggingface.co/fal-ai$path?_subdomain=queue';
      expect(urls, [
        queue('/fal-ai/flux/schnell'),
        queue('/fal-ai/flux/requests/r1/status'),
        queue('/fal-ai/flux/requests/r1/status'),
        queue('/fal-ai/flux/requests/r1'),
        'https://v3.fal.media/files/faro.png',
      ]);
      expect(hf.bodies.first, {
        'prompt': 'Un faro',
        'image_size': {'width': 1024, 'height': 576},
      });
      expect(hf.requests.last.headers.containsKey('authorization'), isFalse);
      expect(image.bytes, _png);
      expect(image.mimeType, 'image/png');
    });

    test('fal.ai que nunca termina: se vence', () {
      hf.reply(
        jsonEncode({
          'request_id': 'r1',
          'status': 'IN_QUEUE',
          'response_url': 'https://queue.fal.run/fal-ai/flux/requests/r1',
        }),
      );
      for (var i = 0; i < 3; i++) {
        hf.reply(jsonEncode({'status': 'IN_PROGRESS'}));
      }
      expect(
        wire.generate(_request('fal-ai|fal-ai/flux/schnell'), access),
        throwsA(_failure(ImageFailure.timeout)),
      );
    });

    test('fal.ai con contenido marcado: rechazado por contenido', () {
      hf.reply(
        jsonEncode({
          'images': [
            {'url': 'https://v3.fal.media/files/x.png'},
          ],
          'has_nsfw_concepts': [true],
        }),
      );
      expect(
        wire.generate(_request('fal-ai|fal-ai/flux/schnell'), access),
        throwsA(_failure(ImageFailure.contentRefused)),
      );
    });

    test('Replicate: espera con Prefer: wait y baja la imagen', () async {
      hf
        ..reply(
          jsonEncode({
            'status': 'succeeded',
            'output': ['https://replicate.delivery/x/faro.webp'],
          }),
        )
        ..replyBytes(_png);

      await wire.generate(
        _request('replicate|stability-ai/stable-diffusion-3.5-large'),
        access,
      );

      expect(
        hf.requests.first.uri.toString(),
        'https://router.huggingface.co/replicate/v1/models/'
        'stability-ai/stable-diffusion-3.5-large/predictions',
      );
      expect(hf.requests.first.headers['Prefer'], 'wait');
      expect(hf.bodies.first, {
        'input': {'prompt': 'Un faro', 'width': 1024, 'height': 576},
      });
    });

    test('sin camino: el modelo no está', () {
      expect(
        wire.generate(_request('sin-barra'), access),
        throwsA(_failure(ImageFailure.modelNotFound)),
      );
    });
  });

  group('los errores', () {
    test('402: sin créditos de Hugging Face', () {
      hf.reply(
        jsonEncode({
          'error': 'You have exceeded your monthly included credits.',
        }),
        status: 402,
      );
      expect(
        wire.generate(_request('nscale|m'), access),
        throwsA(_failure(ImageFailure.noCredits)),
      );
    });

    test('403: el token sin el permiso de inferencia', () {
      hf.reply(jsonEncode({'error': 'Insufficient permissions'}), status: 403);
      expect(
        wire.generate(_request('nscale|m'), access),
        throwsA(_failure(ImageFailure.forbidden)),
      );
    });

    test('400 por contenido; 400 de otra cosa', () {
      expect(
        HuggingFaceImageWire.failureFrom(400, {
          'error': {'message': 'NSFW content detected'},
        }, Headers()).failure,
        ImageFailure.contentRefused,
      );
      expect(
        HuggingFaceImageWire.failureFrom(400, {
          'detail': 'width must be a multiple of 8',
        }, Headers()).failure,
        ImageFailure.badRequest,
      );
      expect(
        HuggingFaceImageWire.failureFrom(429, null, Headers()).failure,
        ImageFailure.rateLimited,
      );
      expect(
        HuggingFaceImageWire.failureFrom(503, null, Headers()).failure,
        ImageFailure.unavailable,
      );
    });
  });
}

Matcher _failure(ImageFailure failure) => isA<ImageGenerationException>()
    .having((e) => e.failure, 'failure', failure);
