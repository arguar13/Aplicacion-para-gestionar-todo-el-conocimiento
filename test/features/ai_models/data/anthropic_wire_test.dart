import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/anthropic_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';

import '../../../support/fake_cloud_server.dart';

const _request = CloudRequest(
  model: 'claude-opus-5-5',
  instruction: 'Respondé en español.',
  messages: [CloudMessage(role: CloudRole.user, text: '¿Qué es Roma?')],
  maxOutputTokens: 512,
);

Map<String, Object?> _start({int input = 120}) => {
  'type': 'message_start',
  'message': {
    'id': 'msg_1',
    'type': 'message',
    'role': 'assistant',
    'model': 'claude-opus-5-5',
    'content': <Object>[],
    'usage': {'input_tokens': input, 'output_tokens': 1},
  },
};

Map<String, Object?> _text(String text) => {
  'type': 'content_block_delta',
  'index': 0,
  'delta': {'type': 'text_delta', 'text': text},
};

Map<String, Object?> _stop(String reason, {int output = 30}) => {
  'type': 'message_delta',
  'delta': {'stop_reason': reason},
  'usage': {'output_tokens': output},
};

const _end = {'type': 'message_stop'};

void main() {
  late FakeCloudServer anthropic;
  late AnthropicWire wire;

  setUp(() {
    anthropic = FakeCloudServer();
    wire = AnthropicWire(dio: Dio()..httpClientAdapter = anthropic);
  });

  group('el pedido', () {
    test('la clave y la versión van en las cabeceras, nunca en la '
        'dirección', () async {
      anthropic.reply(namedSse([_start(), _text('Hola'), _stop('end_turn')]));

      await wire.stream(_request, key: 'sk-ant-SECRETA').drain<void>();

      final sent = anthropic.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['x-api-key'], 'sk-ant-SECRETA');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(sent.uri.toString(), isNot(contains('SECRETA')));
    });

    test('la instrucción, lo conversado con sus roles y las fotos antes del '
        'texto', () async {
      anthropic.reply(namedSse([_start(), _text('ok'), _stop('end_turn')]));
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

      await wire
          .stream(
            CloudRequest(
              model: 'claude-opus-5-5',
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

      final body = anthropic.bodies.single;
      expect(body['system'], 'Instrucción');
      expect(body['stream'], isTrue);
      final messages = body['messages'] as List;
      expect(messages.map((m) => (m as Map)['role']), [
        'user',
        'assistant',
        'user',
      ]);
      expect((messages.first as Map)['content'], [
        {'type': 'text', 'text': 'Antes'},
      ]);
      final last = (messages.last as Map)['content'] as List;
      expect(last.first, {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': base64Encode(png),
        },
      });
      expect(last[1], {'type': 'text', 'text': 'Mirá'});
    });

    test('los 5.x piensan lo mínimo, sin `thinking` y con margen en el '
        'tope', () {
      for (final model in [
        'claude-opus-5-5',
        'claude-opus-5',
        'claude-sonnet-5-5',
        'claude-haiku-5-5',
        'claude-fable-5-1',
      ]) {
        final body = AnthropicWire.bodyOf(
          CloudRequest(
            model: model,
            instruction: 'x',
            messages: const [],
            maxOutputTokens: 48,
          ),
        );
        expect(body['output_config'], {'effort': 'low'}, reason: model);
        expect(body.containsKey('thinking'), isFalse, reason: model);
        expect(
          body['max_tokens'],
          48 + kAnthropicThinkingHeadroomTokens,
          reason: model,
        );
      }
    });

    test('los 4.x, ni `effort` ni margen', () {
      final body = AnthropicWire.bodyOf(
        const CloudRequest(
          model: 'claude-opus-4-8',
          instruction: 'x',
          messages: [],
          maxOutputTokens: 48,
        ),
      );
      expect(body.containsKey('output_config'), isFalse);
      expect(body['max_tokens'], 48);
    });

    test('el respaldo automático va solo en los modelos que lo admiten, '
        'con su cabecera', () async {
      for (final (model, fallback) in [
        ('claude-opus-5-5', true),
        ('claude-fable-5-1', true),
        ('claude-opus-5', true),
        ('claude-sonnet-5-5', true),
        ('claude-haiku-5-5', false),
        ('claude-opus-4-8', false),
      ]) {
        anthropic.reply(namedSse([_start(), _text('ok'), _stop('end_turn')]));
        await wire
            .stream(
              CloudRequest(
                model: model,
                instruction: 'x',
                messages: const [
                  CloudMessage(role: CloudRole.user, text: 'hola'),
                ],
                maxOutputTokens: 48,
              ),
              key: 'k',
            )
            .drain<void>();
        expect(
          anthropic.bodies.last['fallbacks'],
          fallback ? 'default' : isNull,
          reason: model,
        );
        expect(
          anthropic.requests.last.headers['anthropic-beta'],
          fallback ? kAnthropicFallbackBeta : isNull,
          reason: model,
        );
      }
    });
  });

  group('la respuesta', () {
    test('llega de a pedazos, sin partir acentos ni emojis, y sin lo '
        'pensado', () async {
      anthropic.reply(
        namedSse([
          _start(),
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'thinking', 'thinking': ''},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': 'Pienso que…'},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'signature_delta', 'signature': 'abc'},
          },
          _text('Roma fue la ciudad más '),
          _text('poderosa de la Antigüedad 🏛️.'),
          _stop('end_turn'),
          _end,
        ]),
        chunk: 3,
      );

      final deltas = await wire.stream(_request, key: 'k').toList();

      expect(
        deltas.map((d) => d.text).join(),
        'Roma fue la ciudad más poderosa de la Antigüedad 🏛️.',
      );
    });

    test('trae los tokens del pedido al empezar y los de la respuesta al '
        'final', () async {
      anthropic.reply(
        namedSse([
          _start(input: 140),
          _text('Hola'),
          _stop('end_turn', output: 45),
          _end,
        ]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.first.inputTokens, 140);
      expect(deltas.last.outputTokens, 45);
      expect(deltas.last.truncated, isFalse);
    });

    test('si otro modelo la retoma por el respaldo, el texto sigue', () async {
      anthropic.reply(
        namedSse([
          _start(),
          _text('Una parte '),
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'fallback',
              'from': {'model': 'claude-opus-5-5'},
              'to': {'model': 'claude-opus-4-8'},
            },
          },
          {'type': 'content_block_stop', 'index': 1},
          _text('y el resto.'),
          _stop('end_turn'),
          _end,
        ]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.map((d) => d.text).join(), 'Una parte y el resto.');
    });

    test('cortada por el tope, lo dice', () async {
      anthropic.reply(
        namedSse([_start(), _text('Una respuesta lar'), _stop('max_tokens')]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.last.truncated, isTrue);
    });

    test('si la rechaza por sus reglas, es «bloqueado» aunque haya escrito '
        'algo', () {
      anthropic.reply(
        namedSse([_start(), _text('Empiezo'), _stop('refusal'), _end]),
      );

      expect(
        wire.stream(_request, key: 'k').drain<void>(),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.blocked,
          ),
        ),
      );
    });

    test('un error a mitad del flujo se traduce por su tipo', () {
      anthropic.reply(
        namedSse([
          _start(),
          _text('Hola'),
          {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          },
        ]),
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
      anthropic.reply(jsonEncode(body), status: status, headers: headers);
      try {
        await wire.stream(_request, key: 'k').drain<void>();
      } on CloudModelException catch (e) {
        return e;
      }
      fail('no falló');
    }

    Map<String, Object> error(String type, [String message = '']) => {
      'type': 'error',
      'error': {'type': type, 'message': message},
    };

    test('el tope por minuto: esperar lo que dice `retry-after`', () async {
      final e = await errorOf(
        429,
        error('rate_limit_error', 'Number of request tokens has exceeded.'),
        headers: {'retry-after': '12'},
      );
      expect(e.failure, CloudModelFailure.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 12));
      expect(e.otherAccountMayWork, isFalse);
    });

    test('sin saldo: agotada, y vale probar con otra cuenta', () async {
      final billing = await errorOf(402, error('billing_error'));
      expect(billing.failure, CloudModelFailure.quotaExhausted);
      expect(billing.otherAccountMayWork, isTrue);

      final credit = await errorOf(
        400,
        error(
          'invalid_request_error',
          'Your credit balance is too low to access the Anthropic API.',
        ),
      );
      expect(credit.failure, CloudModelFailure.quotaExhausted);
    });

    test('la clave, el permiso, el modelo, lo largo y el servidor', () async {
      Future<CloudModelFailure> failureOf(int status, Object body) async =>
          (await errorOf(status, body)).failure;

      expect(
        await failureOf(
          401,
          error('authentication_error', 'invalid x-api-key'),
        ),
        CloudModelFailure.invalidKey,
      );
      expect(
        await failureOf(403, error('permission_error')),
        CloudModelFailure.forbidden,
      );
      expect(
        await failureOf(404, error('not_found_error', 'model: claude-x')),
        CloudModelFailure.modelNotFound,
      );
      expect(
        await failureOf(413, error('request_too_large')),
        CloudModelFailure.tooLong,
      );
      expect(
        await failureOf(
          400,
          error(
            'invalid_request_error',
            'prompt is too long: 1200000 tokens > 1000000 maximum',
          ),
        ),
        CloudModelFailure.tooLong,
      );
      expect(
        await failureOf(529, error('overloaded_error', 'Overloaded')),
        CloudModelFailure.unavailable,
      );
      expect(
        await failureOf(500, error('api_error')),
        CloudModelFailure.unavailable,
      );
      expect(
        await failureOf(400, error('invalid_request_error', 'otra cosa')),
        CloudModelFailure.badRequest,
      );
      expect(await failureOf(418, 'no es JSON'), CloudModelFailure.unknown);
    });

    test('sin conexión: «red»', () {
      final offline = AnthropicWire(
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
    Map<String, Object> model(String id, {int input = 1000000}) => {
      'type': 'model',
      'id': id,
      'display_name': 'Nombre de $id',
      'created_at': '2026-09-01T00:00:00Z',
      'max_input_tokens': input,
      'max_tokens': 128000,
    };

    test('de todas las páginas, con lo que lee y escribe cada uno', () async {
      anthropic
        ..reply(
          jsonEncode({
            'data': [model('claude-opus-5-5'), model('claude-sonnet-5-5')],
            'has_more': true,
            'first_id': 'claude-opus-5-5',
            'last_id': 'claude-sonnet-5-5',
          }),
        )
        ..reply(
          jsonEncode({
            'data': [model('claude-haiku-4-5', input: 200000)],
            'has_more': false,
            'first_id': 'claude-haiku-4-5',
            'last_id': 'claude-haiku-4-5',
          }),
        );

      final models = await wire.listModels('sk-ant-SECRETA');

      expect(models.map((m) => m.id), [
        'claude-haiku-4-5',
        'claude-opus-5-5',
        'claude-sonnet-5-5',
      ]);
      expect(models.first.inputTokens, 200000);
      expect(models.first.outputTokens, 128000);
      expect(models[1].displayName, 'Nombre de claude-opus-5-5');
      expect(
        anthropic.requests.last.uri.queryParameters['after_id'],
        'claude-sonnet-5-5',
      );
      expect(anthropic.requests.first.uri.queryParameters['limit'], '1000');
      expect(
        anthropic.requests.every((r) => !r.uri.toString().contains('SECRETA')),
        isTrue,
      );
    });

    test('el recomendado: Opus 5.5; si no, el Opus más nuevo', () {
      List<CloudModelInfo> of(List<String> ids) => [
        for (final id in ids) CloudModelInfo(id: id, displayName: id),
      ];

      expect(
        wire.recommendedModel(
          of(['claude-fable-5-1', 'claude-opus-5', 'claude-opus-5-5']),
        ),
        'claude-opus-5-5',
      );
      expect(
        wire.recommendedModel(
          of(['claude-opus-4-8', 'claude-opus-5', 'claude-sonnet-5-5']),
        ),
        'claude-opus-5',
      );
      expect(
        wire.recommendedModel(of(['claude-opus-4-7', 'claude-opus-4-8'])),
        'claude-opus-4-8',
      );
      expect(
        wire.recommendedModel(of(['claude-haiku-4-5', 'claude-sonnet-5'])),
        'claude-haiku-4-5',
      );
      expect(wire.recommendedModel(const []), isNull);
    });
  });
}
