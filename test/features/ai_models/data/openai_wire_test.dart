import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';

import '../../../support/fake_cloud_server.dart';

const _request = CloudRequest(
  model: 'gpt-5.2',
  instruction: 'Respondé en español.',
  messages: [CloudMessage(role: CloudRole.user, text: '¿Qué es Roma?')],
  maxOutputTokens: 512,
);

Map<String, Object?> _chunk({String? text, String? refusal, String? finish}) =>
    {
      'id': 'chatcmpl-1',
      'object': 'chat.completion.chunk',
      'model': 'gpt-5.2',
      'choices': [
        {
          'index': 0,
          'delta': {'content': ?text, 'refusal': ?refusal},
          'finish_reason': finish,
        },
      ],
    };

Map<String, Object?> _usage({int input = 120, int output = 45}) => {
  'id': 'chatcmpl-1',
  'object': 'chat.completion.chunk',
  'choices': <Object>[],
  'usage': {
    'prompt_tokens': input,
    'completion_tokens': output,
    'total_tokens': input + output,
  },
};

void main() {
  late FakeCloudServer openAi;
  late OpenAiWire wire;

  setUp(() {
    openAi = FakeCloudServer();
    wire = OpenAiWire(dio: Dio()..httpClientAdapter = openAi);
  });

  group('el pedido', () {
    test('la clave va en la cabecera, nunca en la dirección', () async {
      openAi.reply(plainSse([_chunk(text: 'Hola', finish: 'stop')]));

      await wire.stream(_request, key: 'sk-SECRETA').drain<void>();

      final sent = openAi.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(sent.headers['authorization'], 'Bearer sk-SECRETA');
      expect(sent.uri.toString(), isNot(contains('SECRETA')));
    });

    test('la instrucción, lo conversado con sus roles y las fotos', () async {
      openAi.reply(plainSse([_chunk(text: 'ok', finish: 'stop')]));
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

      await wire
          .stream(
            CloudRequest(
              model: 'gpt-4.1',
              instruction: 'Instrucción',
              messages: [
                const CloudMessage(role: CloudRole.user, text: 'Antes'),
                const CloudMessage(role: CloudRole.model, text: 'Respuesta'),
                CloudMessage(role: CloudRole.user, text: 'Mirá', images: [png]),
              ],
              maxOutputTokens: 100,
            ),
            key: 'k',
          )
          .drain<void>();

      final body = openAi.bodies.single;
      expect(body['model'], 'gpt-4.1');
      expect(body['stream'], isTrue);
      expect(body['stream_options'], {'include_usage': true});
      final messages = body['messages'] as List;
      expect(messages.take(3), [
        {'role': 'system', 'content': 'Instrucción'},
        {'role': 'user', 'content': 'Antes'},
        {'role': 'assistant', 'content': 'Respuesta'},
      ]);
      expect((messages.last as Map)['content'], [
        {'type': 'text', 'text': 'Mirá'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'},
        },
      ]);
    });

    test('los que razonan: `developer`, lo mínimo y margen en el tope', () {
      for (final model in ['gpt-5.2', 'gpt-5-mini', 'o3', 'o4-mini']) {
        final body = OpenAiWire.bodyOf(
          CloudRequest(
            model: model,
            instruction: 'x',
            messages: const [],
            maxOutputTokens: 48,
          ),
        );
        expect(body['reasoning_effort'], 'low', reason: model);
        expect(
          body['max_completion_tokens'],
          48 + kOpenAiReasoningHeadroomTokens,
          reason: model,
        );
        expect((body['messages']! as List).first, {
          'role': 'developer',
          'content': 'x',
        }, reason: model);
      }
    });

    test('los que no razonan: `system`, sin `reasoning_effort` ni '
        'margen', () {
      for (final model in ['gpt-4.1', 'gpt-4o-mini', 'gpt-5-chat-latest']) {
        final body = OpenAiWire.bodyOf(
          CloudRequest(
            model: model,
            instruction: 'x',
            messages: const [],
            maxOutputTokens: 48,
          ),
        );
        expect(body.containsKey('reasoning_effort'), isFalse, reason: model);
        expect(body['max_completion_tokens'], 48, reason: model);
        expect((body['messages']! as List).first, {
          'role': 'system',
          'content': 'x',
        }, reason: model);
      }
    });
  });

  group('la respuesta', () {
    test('llega de a pedazos, sin partir acentos ni emojis, y el [DONE] la '
        'cierra', () async {
      final answer = plainSse([
        _chunk(text: ''),
        _chunk(text: 'Roma fue la ciudad más '),
        _chunk(text: 'poderosa de la Antigüedad 🏛️.'),
        _chunk(finish: 'stop'),
      ]);
      final afterDone = plainSse([
        _chunk(text: 'después del final'),
      ], done: false);
      openAi.reply('$answer$afterDone', chunk: 3);

      final deltas = await wire.stream(_request, key: 'k').toList();

      expect(
        deltas.map((d) => d.text).join(),
        'Roma fue la ciudad más poderosa de la Antigüedad 🏛️.',
      );
    });

    test('al final trae los tokens del pedido y de la respuesta', () async {
      openAi.reply(
        plainSse([
          _chunk(text: 'Hola'),
          _chunk(finish: 'stop'),
          _usage(input: 140, output: 60),
        ]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.last.inputTokens, 140);
      expect(deltas.last.outputTokens, 60);
    });

    test('cortada por el tope, lo dice', () async {
      openAi.reply(
        plainSse([
          _chunk(text: 'Una respuesta lar'),
          _chunk(finish: 'length'),
          _usage(),
        ]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.any((d) => d.truncated), isTrue);
    });

    Matcher blocked() => throwsA(
      isA<CloudModelException>().having(
        (e) => e.failure,
        'failure',
        CloudModelFailure.blocked,
      ),
    );

    test('si se niega sin escribir nada, es «bloqueado»', () {
      openAi.reply(
        plainSse([
          _chunk(refusal: 'No puedo ayudar con eso.'),
          _chunk(finish: 'stop'),
        ]),
      );
      expect(wire.stream(_request, key: 'k').drain<void>(), blocked());
    });

    test('y si el filtro lo corta sin escribir nada, también', () {
      openAi.reply(plainSse([_chunk(finish: 'content_filter')]));
      expect(wire.stream(_request, key: 'k').drain<void>(), blocked());
    });

    test('un error a mitad del flujo se traduce por su código', () {
      openAi.reply(
        plainSse([
          _chunk(text: 'Hola'),
          {
            'error': {
              'message': 'The server had an error.',
              'type': 'server_error',
              'code': null,
            },
          },
        ], done: false),
      );

      expect(
        wire.stream(_request, key: 'k').drain<void>(),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.unavailable,
          ),
        ),
      );
    });
  });

  group('los errores', () {
    Future<CloudModelException> errorOf(
      int status,
      Object body, {
      Map<String, String> headers = const {},
    }) async {
      openAi.reply(jsonEncode(body), status: status, headers: headers);
      try {
        await wire.stream(_request, key: 'k').drain<void>();
      } on CloudModelException catch (e) {
        return e;
      }
      fail('no falló');
    }

    Map<String, Object?> error(String? code, {String type = '', String? m}) => {
      'error': {
        'message': m ?? 'mensaje de $code',
        'type': type,
        'param': null,
        'code': code,
      },
    };

    test('un 429 por minuto: esperar lo que dice `retry-after`', () async {
      final e = await errorOf(
        429,
        error('rate_limit_exceeded', type: 'requests'),
        headers: {'retry-after': '1.5'},
      );
      expect(e.failure, CloudModelFailure.rateLimited);
      expect(e.retryAfter, const Duration(milliseconds: 1500));
      expect(e.otherAccountMayWork, isFalse);
    });

    test('un 429 sin saldo o pasado del tope de gasto: agotada, y vale '
        'probar con otra cuenta', () async {
      for (final code in [
        'insufficient_quota',
        'credit_balance_exhausted',
        'organization_spend_limit_exceeded',
        'project_usage_limit_exceeded',
      ]) {
        final e = await errorOf(429, error(code, type: code));
        expect(e.failure, CloudModelFailure.quotaExhausted, reason: code);
        expect(e.otherAccountMayWork, isTrue, reason: code);
      }
    });

    test('la clave, el país, el modelo, lo largo y el servidor', () async {
      Future<CloudModelFailure> failureOf(int status, Object body) async =>
          (await errorOf(status, body)).failure;

      expect(
        await failureOf(
          401,
          error('invalid_api_key', type: 'invalid_request_error'),
        ),
        CloudModelFailure.invalidKey,
      );
      expect(
        await failureOf(403, error('unsupported_country_region_territory')),
        CloudModelFailure.forbidden,
      );
      expect(
        await failureOf(404, error('model_not_found')),
        CloudModelFailure.modelNotFound,
      );
      expect(
        await failureOf(
          400,
          error('context_length_exceeded', type: 'invalid_request_error'),
        ),
        CloudModelFailure.tooLong,
      );
      expect(
        await failureOf(503, error(null, type: 'server_error')),
        CloudModelFailure.unavailable,
      );
      expect(
        await failureOf(400, error('invalid_value')),
        CloudModelFailure.unknown,
      );
      expect(await failureOf(418, 'no es JSON'), CloudModelFailure.unknown);
    });

    test('sin conexión: «red»', () {
      final offline = OpenAiWire(
        dio: Dio()..httpClientAdapter = OfflineCloudServer(),
      );
      expect(
        offline.stream(_request, key: 'k').drain<void>(),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.network,
          ),
        ),
      );
    });
  });

  group('los modelos', () {
    test('solo los de texto que escriben por Chat Completions', () async {
      Map<String, Object> model(String id) => {
        'id': id,
        'object': 'model',
        'created': 1760000000,
        'owned_by': 'system',
      };
      openAi.reply(
        jsonEncode({
          'object': 'list',
          'data': [
            for (final id in [
              'gpt-5.2',
              'gpt-5.2-mini',
              'gpt-5.2-2026-08-07',
              'gpt-5.2-pro',
              'gpt-5.2-codex',
              'gpt-4o-mini-tts',
              'gpt-4o-realtime-preview',
              'gpt-4o-audio-preview',
              'gpt-4o-search-preview',
              'gpt-4o-transcribe',
              'gpt-image-1',
              'gpt-3.5-turbo-instruct',
              'gpt-3.5-turbo-0125',
              'o3',
              'o4-mini-deep-research',
              'text-embedding-3-large',
              'omni-moderation-latest',
              'dall-e-3',
              'whisper-1',
              'chatgpt-4o-latest',
            ])
              model(id),
          ],
        }),
      );

      final models = await wire.listModels('sk-SECRETA');

      expect(models.map((m) => m.id), ['gpt-5.2', 'gpt-5.2-mini', 'o3']);
      expect(models.map((m) => m.displayName), [
        'GPT-5.2',
        'GPT-5.2 mini',
        'o3',
      ]);
      expect(models.first.inputTokens, isNull);
      expect(openAi.requests.single.uri.toString(), isNot(contains('SECRETA')));
    });

    test('el nombre que se muestra', () {
      expect(OpenAiWire.displayNameOf('gpt-4o-mini'), 'GPT-4o mini');
      expect(OpenAiWire.displayNameOf('gpt-5'), 'GPT-5');
      expect(OpenAiWire.displayNameOf('o4-mini'), 'o4-mini');
    });

    test('el recomendado: el GPT más nuevo sin sufijo', () {
      List<CloudModelInfo> of(List<String> ids) => [
        for (final id in ids) CloudModelInfo(id: id, displayName: id),
      ];

      expect(
        wire.recommendedModel(
          of(['gpt-4.1', 'gpt-5', 'gpt-5.2', 'gpt-5.2-mini', 'gpt-6-mini']),
        ),
        'gpt-5.2',
      );
      expect(wire.recommendedModel(of(['gpt-5.9', 'gpt-5.10'])), 'gpt-5.10');
      expect(wire.recommendedModel(of(['o3', 'o4-mini'])), 'o3');
      expect(wire.recommendedModel(const []), isNull);
    });
  });
}
