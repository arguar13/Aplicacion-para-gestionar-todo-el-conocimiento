import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

import '../../../support/fake_cloud_server.dart';

/// Un JPEG de mentira: los primeros bytes de uno de verdad.
final _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4];

/// Una interacción terminada como la documenta Google (2026-10-28): pasos
/// `model_output` con bloques `image` en base64, y lo gastado en `usage`.
String _interaction({
  List<Map<String, Object?>>? content,
  String status = 'completed',
  Map<String, Object?>? error,
}) => jsonEncode({
  'id': 'int-1',
  'object': 'interaction',
  'model': 'gemini-nano-banana-2.1',
  'status': status,
  'error': ?error,
  'steps': [
    {
      'type': 'model_output',
      'content':
          content ??
          [
            {
              'type': 'image',
              'mime_type': 'image/jpeg',
              'data': base64Encode(_jpeg),
            },
          ],
    },
  ],
  'usage': {
    'total_input_tokens': 42,
    'total_output_tokens': 1120,
    'total_tokens': 1162,
  },
});

/// Un error de Google, con su forma de siempre.
String _googleError(int code, String status, String message) => jsonEncode({
  'error': {'code': code, 'message': message, 'status': status},
});

const _request = ImageWireRequest(
  model: 'gemini-nano-banana-2.1',
  prompt: 'Un faro al atardecer',
  aspect: IllustrationAspect.wide,
);

void main() {
  late FakeCloudServer google;
  late GeminiImageWire wire;
  final now = DateTime.utc(2026, 10, 28, 15);

  setUp(() {
    google = FakeCloudServer();
    final dio = Dio()..httpClientAdapter = google;
    wire = GeminiImageWire(
      dio: dio,
      text: GeminiWire(dio: dio, clock: () => now),
      clock: () => now,
    );
  });

  group('el pedido', () {
    test('va a Interactions con store: false, la forma y el tamaño; la '
        'clave en la cabecera', () async {
      google.reply(_interaction());

      await wire.generate(_request, const ImageWireAccess(key: 'AIzaSECRETA'));

      final sent = google.requests.single;
      expect(sent.method, 'POST');
      expect(
        sent.uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/interactions',
      );
      expect(sent.headers['x-goog-api-key'], 'AIzaSECRETA');
      expect(sent.uri.toString(), isNot(contains('SECRETA')));
      expect(google.bodies.single, {
        'model': 'gemini-nano-banana-2.1',
        'input': [
          {'type': 'text', 'text': 'Un faro al atardecer'},
        ],
        'store': false,
        'response_format': {
          'type': 'image',
          'mime_type': 'image/jpeg',
          'aspect_ratio': '16:9',
          'image_size': '1K',
        },
      });
    });

    test('el tamaño según el modelo: el Lite solo 1K, el 512 solo en 3.1 '
        'Flash Image', () {
      expect(
        GeminiImageWire.imageSizeFor(
          'gemini-3.1-flash-lite-image',
          IllustrationSize.large,
        ),
        '1K',
      );
      expect(
        GeminiImageWire.imageSizeFor(
          'gemini-3.1-flash-image',
          IllustrationSize.small,
        ),
        '512',
      );
      expect(
        GeminiImageWire.imageSizeFor(
          'gemini-nano-banana-2.1',
          IllustrationSize.small,
        ),
        '1K',
      );
      expect(
        GeminiImageWire.imageSizeFor(
          'gemini-nano-banana-2.1',
          IllustrationSize.large,
        ),
        '2K',
      );
    });
  });

  group('la respuesta', () {
    test('la imagen del paso model_output, con su tipo y los tokens', () async {
      google.reply(_interaction());

      final image = await wire.generate(
        _request,
        const ImageWireAccess(key: 'k'),
      );

      expect(image.bytes, _jpeg);
      expect(image.mimeType, 'image/jpeg');
      expect(image.model, 'gemini-nano-banana-2.1');
      expect(image.inputTokens, 42);
      expect(image.outputTokens, 1120);
    });

    test('también la del formato anterior, en outputs', () {
      final image = GeminiImageWire.parse({
        'status': 'completed',
        'outputs': [
          {'type': 'text', 'text': 'Acá está'},
          {
            'type': 'image',
            'mime_type': 'image/png',
            'data': base64Encode([0x89, 0x50, 0x4E, 0x47, 9]),
          },
        ],
      }, model: 'm');
      expect(image.mimeType, 'image/png');
    });

    test('sin imagen y con una explicación: rechazado por su contenido', () {
      google.reply(
        _interaction(
          content: [
            {'type': 'text', 'text': 'No puedo generar esa imagen.'},
          ],
        ),
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.contentRefused)),
      );
    });

    test('sin imagen y sin nada: no devolvió ninguna imagen', () {
      expect(
        () => GeminiImageWire.parse({
          'status': 'completed',
          'steps': <Object>[],
        }, model: 'm'),
        throwsA(_failure(ImageFailure.noImage)),
      );
    });

    test('una interacción fallida por seguridad: rechazada por contenido', () {
      expect(
        () => GeminiImageWire.parse({
          'status': 'failed',
          'error': {
            'code': 'https://ai.google.dev/errors/safety',
            'message': 'Blocked by safety filters',
          },
        }, model: 'm'),
        throwsA(_failure(ImageFailure.contentRefused)),
      );
    });
  });

  group('los errores', () {
    test('la capa gratuita con tope cero en un modelo de imagen: sin '
        'facturación, no «cuota agotada»', () {
      google.reply(
        _googleError(
          429,
          'RESOURCE_EXHAUSTED',
          'Quota exceeded for metric: generativelanguage.googleapis.com/'
              'generate_content_free_tier_requests, limit: 0, model: '
              'gemini-nano-banana-2.1. Please try again in 30s.',
        ),
        status: 429,
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.noBilling)),
      );
    });

    test('un mensaje que nombra la facturación: sin facturación', () {
      google.reply(
        _googleError(
          400,
          'FAILED_PRECONDITION',
          'Image generation is only available to billed users.',
        ),
        status: 400,
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.noBilling)),
      );
    });

    test('la cuota del día de una cuenta paga: cuota agotada', () {
      google.reply(
        jsonEncode({
          'error': {
            'code': 429,
            'status': 'RESOURCE_EXHAUSTED',
            'message': 'Quota exceeded.',
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
                'violations': [
                  {'quotaId': 'GenerateRequestsPerDayPerProjectPerModel'},
                ],
              },
            ],
          },
        }),
        status: 429,
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.quotaExhausted)),
      );
    });

    test('el tope por minuto: esperar', () {
      google.reply(
        _googleError(429, 'RESOURCE_EXHAUSTED', 'Rate limit exceeded.'),
        status: 429,
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.rateLimited)),
      );
    });

    test('la clave mala', () {
      google.reply(
        _googleError(400, 'INVALID_ARGUMENT', 'API key not valid.'),
        status: 400,
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.invalidKey)),
      );
    });

    test('un 400 de seguridad: rechazado por contenido', () {
      google.reply(
        _googleError(
          400,
          'INVALID_ARGUMENT',
          'The prompt was blocked due to safety reasons.',
        ),
        status: 400,
      );
      expect(
        wire.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.contentRefused)),
      );
    });

    test('sin red', () {
      final offline = Dio()..httpClientAdapter = OfflineCloudServer();
      final cut = GeminiImageWire(
        dio: offline,
        text: GeminiWire(dio: offline),
      );
      expect(
        cut.generate(_request, const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.network)),
      );
    });

    test('sin clave no se pide nada', () {
      expect(
        wire.generate(_request, const ImageWireAccess()),
        throwsA(_failure(ImageFailure.noAccount)),
      );
      expect(google.requests, isEmpty);
    });
  });

  group('los modelos de imagen', () {
    test('de la misma lista de F32, solo los que dibujan; la de texto no '
        'los trae', () async {
      final list = jsonEncode({
        'models': [
          {
            'name': 'models/gemini-3.8-flash',
            'displayName': 'Gemini 3.8 Flash',
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/gemini-nano-banana-2.1',
            'displayName': 'Nano Banana 2.1',
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/gemini-3.1-flash-lite-image',
            'displayName': 'Nano Banana 2 Lite',
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/gemini-2.5-flash-preview-tts',
            'supportedGenerationMethods': ['generateContent'],
          },
          {
            'name': 'models/imagen-4.0-generate-001',
            'supportedGenerationMethods': ['predict'],
          },
        ],
      });
      google
        ..reply(list)
        ..reply(list);

      final images = await wire.listImageModels(
        const ImageWireAccess(key: 'k'),
      );
      final text = await GeminiWire(
        dio: Dio()..httpClientAdapter = google,
      ).listModels('k');

      expect(images.map((m) => m.id), [
        'gemini-3.1-flash-lite-image',
        'gemini-nano-banana-2.1',
      ]);
      expect(images.last.displayName, 'Nano Banana 2.1');
      expect(text.map((m) => m.id), ['gemini-3.8-flash']);
    });

    test('el recomendado: Nano Banana 2.1, después el Lite, el 2.5 al '
        'último', () {
      ImageModelInfo m(String id) => ImageModelInfo(id: id, displayName: id);
      expect(
        wire.recommendedImageModel([
          m('gemini-2.5-flash-image'),
          m('gemini-3-pro-image'),
          m('gemini-nano-banana-2.1'),
          m('gemini-3.1-flash-lite-image'),
        ]),
        'gemini-nano-banana-2.1',
      );
      expect(
        wire.recommendedImageModel([
          m('gemini-2.5-flash-image'),
          m('gemini-3.1-flash-lite-image-preview'),
        ]),
        'gemini-3.1-flash-lite-image-preview',
      );
      expect(
        wire.recommendedImageModel([
          m('gemini-2.5-flash-image'),
          m('gemini-4-flash-image'),
        ]),
        'gemini-4-flash-image',
      );
      expect(wire.recommendedImageModel(const []), isNull);
    });

    test('una clave mala al listar: la clave', () {
      google.reply(
        _googleError(400, 'INVALID_ARGUMENT', 'API key not valid.'),
        status: 400,
      );
      expect(
        wire.listImageModels(const ImageWireAccess(key: 'k')),
        throwsA(_failure(ImageFailure.invalidKey)),
      );
    });
  });
}

Matcher _failure(ImageFailure failure) => isA<ImageGenerationException>()
    .having((e) => e.failure, 'failure', failure);
