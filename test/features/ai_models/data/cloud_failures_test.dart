import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/anthropic_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Un paso de lo que contesta el proveedor de mentira.
typedef _Step = FutureOr<ResponseBody> Function(RequestOptions options);

/// Un proveedor de mentira para los tres formatos: contesta lo que se le
/// grabó, en orden, y anota cada pedido. Nunca sale a internet.
class _FakeProvider implements HttpClientAdapter {
  final steps = <_Step>[];
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) await requestStream.drain<void>();
    return steps.removeAt(0)(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Una respuesta que llega entera, con su estado y sus cabeceras.
_Step _reply(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
}) =>
    (_) => ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(body))),
      status,
      headers: {
        for (final entry in headers.entries) entry.key: [entry.value],
      },
    );

/// Una respuesta que manda [first] y después falla con [error] a mitad.
_Step _cutAfter(String first, Exception error) =>
    (_) => ResponseBody(
      (() async* {
        yield Uint8List.fromList(utf8.encode(first));
        throw error;
      })(),
      200,
    );

/// Una respuesta que manda [first] y después se queda callada.
_Step _silentAfter(String first) =>
    (_) => ResponseBody(
      (() async* {
        yield Uint8List.fromList(utf8.encode(first));
        await Completer<void>().future;
      })(),
      200,
    );

/// El pedido no llega al proveedor.
_Step _cannotReach(DioExceptionType type, {Object? error}) =>
    (options) =>
        throw DioException(requestOptions: options, type: type, error: error);

const _request = CloudRequest(
  model: 'modelo',
  instruction: 'Respondé en español.',
  messages: [CloudMessage(role: CloudRole.user, text: 'Hola')],
  maxOutputTokens: 256,
);

/// Cada formato, con lo que dice cuando termina bien, cuando se corta sin
/// terminar y cómo contesta con un error.
class _Format {
  _Format(this.name, this.build, {required this.whole, required this.partial});

  final String name;
  final CloudWire Function(_FakeProvider fake, Duration idle) build;

  /// Una respuesta completa, con su cierre.
  final String whole;

  /// Lo mismo, sin el cierre: se cortó.
  final String partial;
}

String _gemini(List<Map<String, Object?>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\r\n\r\n').join();

Map<String, Object?> _geminiChunk(String text, {String? finish}) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      },
      'finishReason': ?finish,
    },
  ],
};

String _openAi(List<String> events) => events.map((e) => 'data: $e\n\n').join();

String _anthropic(List<(String, Map<String, Object?>)> events) =>
    events.map((e) => 'event: ${e.$1}\ndata: ${jsonEncode(e.$2)}\n\n').join();

final _formats = [
  _Format(
    'Gemini',
    (fake, idle) => GeminiWire(
      dio: Dio()..httpClientAdapter = fake,
      clock: () => DateTime.utc(2026, 10, 23, 15),
      idleTimeout: idle,
    ),
    whole: _gemini([_geminiChunk('Hola', finish: 'STOP')]),
    partial: _gemini([_geminiChunk('Hola')]),
  ),
  _Format(
    'OpenAI',
    (fake, idle) =>
        OpenAiWire(dio: Dio()..httpClientAdapter = fake, idleTimeout: idle),
    whole: _openAi([
      jsonEncode({
        'choices': [
          {
            'delta': {'content': 'Hola'},
            'finish_reason': null,
          },
        ],
      }),
      jsonEncode({
        'choices': [
          {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
        ],
      }),
      '[DONE]',
    ]),
    partial: _openAi([
      jsonEncode({
        'choices': [
          {
            'delta': {'content': 'Hola'},
            'finish_reason': null,
          },
        ],
      }),
    ]),
  ),
  _Format(
    'Claude',
    (fake, idle) =>
        AnthropicWire(dio: Dio()..httpClientAdapter = fake, idleTimeout: idle),
    whole: _anthropic([
      (
        'content_block_delta',
        {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': 'Hola'},
        },
      ),
      (
        'message_delta',
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
          'usage': {'output_tokens': 3},
        },
      ),
      ('message_stop', {'type': 'message_stop'}),
    ]),
    partial: _anthropic([
      (
        'content_block_delta',
        {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': 'Hola'},
        },
      ),
    ]),
  ),
];

/// Lo que pasa en cada formato cuando algo sale mal (F39).
void main() {
  late _FakeProvider fake;

  setUp(() => fake = _FakeProvider());

  Future<Object?> outcome(
    _Format format,
    _Step step, {
    Duration idle = kCloudIdleTimeout,
  }) async {
    fake.steps.add(step);
    try {
      await format.build(fake, idle).stream(_request, key: 'clave').toList();
      return null;
      // Lo que se mira es qué error sale, sea cual sea.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      return error;
    }
  }

  Matcher failsWith(CloudModelFailure failure) =>
      isA<CloudModelException>().having((e) => e.failure, 'failure', failure);

  for (final format in _formats) {
    group('${format.name}: antes de la respuesta', () {
      test('sin conexión: no se llega al proveedor', () async {
        expect(
          await outcome(
            format,
            _cannotReach(
              DioExceptionType.connectionError,
              error: const SocketException('Failed host lookup'),
            ),
          ),
          failsWith(CloudModelFailure.network),
        );
      });

      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        test('la espera vencida ($type) no es falta de red', () async {
          expect(
            await outcome(format, _cannotReach(type)),
            failsWith(CloudModelFailure.timeout),
          );
        });
      }

      test('el pedido de respuesta larga da margen a las cabeceras', () async {
        fake.steps.add(_reply(format.whole));
        await format
            .build(fake, kCloudIdleTimeout)
            .stream(_request, key: 'clave')
            .toList();
        expect(fake.requests.single.receiveTimeout, kCloudFirstByteTimeout);
      });
    });

    group('${format.name}: a mitad de la respuesta', () {
      test('una respuesta completa sale bien', () async {
        expect(await outcome(format, _reply(format.whole)), isNull);
      });

      test('la conexión que se cae a mitad es una respuesta cortada', () async {
        expect(
          await outcome(
            format,
            _cutAfter(
              format.partial,
              const HttpException('Connection closed while receiving data'),
            ),
          ),
          failsWith(CloudModelFailure.cutOff),
        );
      });

      test('un socket reseteado a mitad es una respuesta cortada, no la '
          'falta de internet', () async {
        expect(
          await outcome(
            format,
            _cutAfter(
              format.partial,
              const SocketException('Connection reset by peer'),
            ),
          ),
          failsWith(CloudModelFailure.cutOff),
        );
      });

      test('el silencio entre pedazos que corta dio no es falta de red '
          '(la causa del falso «error de conexión»)', () async {
        // Dio vigila `receiveTimeout` también entre pedazos del cuerpo y
        // corta con esto; los formatos lo tomaban por «sin red».
        expect(
          await outcome(
            format,
            _cutAfter(
              format.partial,
              DioException.receiveTimeout(
                timeout: const Duration(seconds: 60),
                requestOptions: RequestOptions(path: '/x'),
              ),
            ),
          ),
          failsWith(CloudModelFailure.timeout),
        );
      });

      test('la que termina sin su cierre se cortó', () async {
        expect(
          await outcome(format, _reply(format.partial)),
          failsWith(CloudModelFailure.cutOff),
        );
      });

      test('si deja de mandar, vence la espera por silencio', () async {
        expect(
          await outcome(
            format,
            _silentAfter(format.partial),
            idle: const Duration(milliseconds: 60),
          ),
          failsWith(CloudModelFailure.timeout),
        );
      });

      test('el texto que llegó antes del corte se entrega igual', () async {
        fake.steps.add(
          _cutAfter(
            format.partial,
            const HttpException('Connection closed while receiving data'),
          ),
        );
        final seen = StringBuffer();
        try {
          await for (final delta
              in format
                  .build(fake, kCloudIdleTimeout)
                  .stream(_request, key: 'clave')) {
            seen.write(delta.text);
          }
        } on CloudModelException {
          // Es lo que se espera.
        }
        expect(seen.toString(), 'Hola');
      });

      test('cortar a propósito no es un error', () async {
        final cancel = CancelToken();
        final gate = Completer<void>();
        fake.steps.add(
          (options) => ResponseBody(
            (() async* {
              yield Uint8List.fromList(utf8.encode(format.partial));
              await gate.future;
            })(),
            200,
          ),
        );
        final done = format
            .build(fake, kCloudIdleTimeout)
            .stream(_request, key: 'clave', cancel: cancel)
            .toList();
        await pumpEventQueue();
        // Se corta mientras llega: termina sin error ni «respuesta cortada».
        cancel.cancel();
        gate.complete();
        await done;
      });
    });
  }

  // Cada proveedor dice a su manera que algo falló: qué clase de falla es.
  void table(
    String name,
    _Format format,
    List<
      ({
        String what,
        int status,
        String body,
        Map<String, String> headers,
        CloudModelFailure failure,
        Duration? retryAfter,
      })
    >
    cases,
  ) {
    group('$name: los estados y cuerpos de error', () {
      for (final c in cases) {
        test(c.what, () async {
          final error = await outcome(
            format,
            _reply(c.body, status: c.status, headers: c.headers),
          );
          expect(error, failsWith(c.failure));
          expect((error! as CloudModelException).retryAfter, c.retryAfter);
          expect((error as CloudModelException).statusCode, c.status);
        });
      }
    });
  }

  ({
    String what,
    int status,
    String body,
    Map<String, String> headers,
    CloudModelFailure failure,
    Duration? retryAfter,
  })
  c(
    String what,
    int status,
    String body,
    CloudModelFailure failure, {
    Map<String, String> headers = const {},
    Duration? retryAfter,
  }) => (
    what: what,
    status: status,
    body: body,
    headers: headers,
    failure: failure,
    retryAfter: retryAfter,
  );

  String googleError(
    int code,
    String status,
    String message, [
    List<Object?>? details,
  ]) => jsonEncode({
    'error': {
      'code': code,
      'status': status,
      'message': message,
      'details': ?details,
    },
  });

  table('Gemini', _formats[0], [
    c(
      '429 por día: cuota agotada',
      429,
      googleError(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded', [
        {
          '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
          'violations': [
            {'quotaId': 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'},
          ],
        },
      ]),
      CloudModelFailure.quotaExhausted,
      retryAfter: const Duration(hours: 16),
    ),
    c(
      '429 por minuto con lo que pide esperar: tope por minuto',
      429,
      googleError(429, 'RESOURCE_EXHAUSTED', 'Slow down', [
        {'retryDelay': '7s'},
      ]),
      CloudModelFailure.rateLimited,
      retryAfter: const Duration(seconds: 7),
    ),
    c(
      '429 con la cabecera retry-after',
      429,
      googleError(429, 'RESOURCE_EXHAUSTED', 'Slow down'),
      CloudModelFailure.rateLimited,
      headers: {'retry-after': '9'},
      retryAfter: const Duration(seconds: 9),
    ),
    c(
      '429 que dice «per day» en el mensaje: cuota agotada',
      429,
      googleError(429, 'RESOURCE_EXHAUSTED', 'Limit of 20 requests per day'),
      CloudModelFailure.quotaExhausted,
      retryAfter: const Duration(hours: 16),
    ),
    c(
      '500: caído de su lado',
      500,
      googleError(500, 'INTERNAL', 'Internal error'),
      CloudModelFailure.unavailable,
    ),
    c(
      '503: saturado, con lo que pide esperar',
      503,
      googleError(503, 'UNAVAILABLE', 'The model is overloaded', [
        {'retryDelay': '12s'},
      ]),
      CloudModelFailure.unavailable,
      retryAfter: const Duration(seconds: 12),
    ),
    c(
      '504: no llegó a tiempo',
      504,
      googleError(504, 'DEADLINE_EXCEEDED', 'Deadline'),
      CloudModelFailure.unavailable,
    ),
    c(
      '401: clave inválida',
      401,
      googleError(401, 'UNAUTHENTICATED', 'bad'),
      CloudModelFailure.invalidKey,
    ),
    c(
      '403: sin permiso',
      403,
      googleError(403, 'PERMISSION_DENIED', 'no'),
      CloudModelFailure.forbidden,
    ),
    c(
      '400: pedido inválido',
      400,
      googleError(400, 'INVALID_ARGUMENT', 'Unknown field'),
      CloudModelFailure.badRequest,
    ),
    c(
      '400: el texto no entra',
      400,
      googleError(
        400,
        'INVALID_ARGUMENT',
        'The input token count exceeds the maximum number of tokens',
      ),
      CloudModelFailure.tooLong,
    ),
    c(
      '408: la espera venció',
      408,
      googleError(408, 'DEADLINE_EXCEEDED', 'slow'),
      CloudModelFailure.timeout,
    ),
  ]);

  String openAiError(String message, {String? code, String type = 'error'}) =>
      jsonEncode({
        'error': {'message': message, 'type': type, 'code': code},
      });

  table('OpenAI', _formats[1], [
    c(
      '429 sin saldo: cuota agotada',
      429,
      openAiError('You exceeded', code: 'insufficient_quota'),
      CloudModelFailure.quotaExhausted,
    ),
    c(
      '429 por minuto con retry-after',
      429,
      openAiError('Rate limit', code: 'rate_limit_exceeded'),
      CloudModelFailure.rateLimited,
      headers: {'retry-after': '2'},
      retryAfter: const Duration(seconds: 2),
    ),
    c(
      '429 que dice cuánto en el mensaje',
      429,
      openAiError(
        'Rate limit reached. Please try again in 6m0s.',
        code: 'rate_limit_exceeded',
      ),
      CloudModelFailure.rateLimited,
      retryAfter: const Duration(minutes: 6),
    ),
    for (final status in [500, 502, 503, 504])
      c(
        '$status: saturado o caído',
        status,
        openAiError('The server had an error', type: 'server_error'),
        CloudModelFailure.unavailable,
      ),
    c(
      '401: clave inválida',
      401,
      openAiError('Incorrect API key', code: 'invalid_api_key'),
      CloudModelFailure.invalidKey,
    ),
    c(
      '403: sin permiso',
      403,
      openAiError('Not allowed'),
      CloudModelFailure.forbidden,
    ),
    c(
      '400: pedido inválido',
      400,
      openAiError('Bad field', type: 'invalid_request_error'),
      CloudModelFailure.badRequest,
    ),
    c(
      '400: el texto no entra',
      400,
      openAiError('Too long', code: 'context_length_exceeded'),
      CloudModelFailure.tooLong,
    ),
    c(
      '408: la espera venció',
      408,
      openAiError('Request timed out'),
      CloudModelFailure.timeout,
    ),
  ]);

  String claudeError(String type, String message) => jsonEncode({
    'type': 'error',
    'error': {'type': type, 'message': message},
  });

  table('Claude', _formats[2], [
    c(
      '429 con retry-after: tope por minuto',
      429,
      claudeError('rate_limit_error', 'Number of requests'),
      CloudModelFailure.rateLimited,
      headers: {'retry-after': '30'},
      retryAfter: const Duration(seconds: 30),
    ),
    c(
      '400 sin saldo: cuota agotada',
      400,
      claudeError('invalid_request_error', 'Your credit balance is too low'),
      CloudModelFailure.quotaExhausted,
    ),
    c(
      '429 con el tope de uso: cuota agotada',
      429,
      claudeError(
        'rate_limit_error',
        'You have reached your specified API usage limits.',
      ),
      CloudModelFailure.quotaExhausted,
    ),
    c(
      '529: sobrecargado',
      529,
      claudeError('overloaded_error', 'Overloaded'),
      CloudModelFailure.unavailable,
    ),
    for (final status in [500, 502, 503, 504])
      c(
        '$status: caído',
        status,
        claudeError('api_error', 'Internal'),
        CloudModelFailure.unavailable,
      ),
    c(
      '401: clave inválida',
      401,
      claudeError('authentication_error', 'invalid x-api-key'),
      CloudModelFailure.invalidKey,
    ),
    c(
      '403: sin permiso',
      403,
      claudeError('permission_error', 'no'),
      CloudModelFailure.forbidden,
    ),
    c(
      '400: pedido inválido',
      400,
      claudeError('invalid_request_error', 'messages: field required'),
      CloudModelFailure.badRequest,
    ),
    c(
      '408: la espera venció',
      408,
      claudeError('timeout_error', 'slow'),
      CloudModelFailure.timeout,
    ),
  ]);

  test('un error que llega dentro de la respuesta en vivo también se '
      'clasifica', () async {
    final error = await outcome(
      _formats[2],
      _reply(
        _anthropic([
          (
            'error',
            {
              'type': 'error',
              'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
            },
          ),
        ]),
      ),
    );
    expect(error, failsWith(CloudModelFailure.unavailable));
  });

  test(
    'listar los modelos no pide la espera larga de las respuestas',
    () async {
      fake.steps.add(_reply(jsonEncode({'data': <Object?>[]})));
      await _formats[1].build(fake, kCloudIdleTimeout).listModels('clave');
      expect(fake.requests.single.receiveTimeout, isNull);
    },
  );
}
