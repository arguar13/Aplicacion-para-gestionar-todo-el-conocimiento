import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/sse.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';

/// Una respuesta grabada: estado y cuerpo, que llega de a `chunk` bytes.
typedef _Reply = ({int status, String body, int chunk});

/// Un Google de mentira: devuelve las respuestas en orden y anota cada pedido.
class _FakeGoogle implements HttpClientAdapter {
  final replies = <_Reply>[];
  final requests = <RequestOptions>[];
  final bodies = <Map<String, dynamic>>[];

  void reply(String body, {int status = 200, int chunk = 5}) =>
      replies.add((status: status, body: body, chunk: chunk));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        [],
        (all, c) => all..addAll(c),
      );
      bodies.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    }
    final next = replies.removeAt(0);
    final bytes = utf8.encode(next.body);
    return ResponseBody(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += next.chunk)
          Uint8List.fromList(
            bytes.sublist(i, (i + next.chunk).clamp(0, bytes.length)),
          ),
      ]),
      next.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Los eventos de una respuesta que termina bien: Gemini cierra con un
/// `finishReason`; sin él, la respuesta se cortó (F39).
String _sse(List<Map<String, Object?>> events) => [
  ...events,
  {
    'candidates': [
      {'finishReason': 'STOP'},
    ],
  },
].map((e) => 'data: ${jsonEncode(e)}\r\n\r\n').join();

Map<String, Object?> _textChunk(String text, {String? finish}) => {
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

const _request = CloudRequest(
  model: 'gemini-3.8-flash',
  instruction: 'Respondé en español.',
  messages: [CloudMessage(role: CloudRole.user, text: '¿Qué es Roma?')],
  maxOutputTokens: 512,
);

void main() {
  late _FakeGoogle google;
  late GeminiWire wire;
  final now = DateTime.utc(2026, 10, 16, 15);

  setUp(() {
    google = _FakeGoogle();
    wire = GeminiWire(dio: Dio()..httpClientAdapter = google, clock: () => now);
  });

  group('el pedido', () {
    test('la clave va en la cabecera y nunca en la dirección', () async {
      google.reply(_sse([_textChunk('Hola')]));

      await wire.stream(_request, key: 'AIzaSECRETA').drain<void>();

      final sent = google.requests.single;
      expect(sent.headers['x-goog-api-key'], 'AIzaSECRETA');
      expect(sent.uri.toString(), isNot(contains('AIzaSECRETA')));
      expect(
        sent.uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.8-flash:streamGenerateContent?alt=sse',
      );
      expect(sent.method, 'POST');
    });

    test('la instrucción, lo conversado con sus roles y las fotos', () async {
      google.reply(_sse([_textChunk('ok')]));
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

      await wire
          .stream(
            CloudRequest(
              model: 'gemini-3.8-flash',
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

      final body = google.bodies.single;
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'Instrucción'},
        ],
      });
      final contents = body['contents'] as List;
      expect(contents.map((c) => (c as Map)['role']), [
        'user',
        'model',
        'user',
      ]);
      final last = (contents.last as Map)['parts'] as List;
      expect(last.first, {'text': 'Mirá'});
      expect((last[1] as Map)['inlineData'], {
        'mimeType': 'image/png',
        'data': base64Encode(png),
      });
    });

    test('Gemini 3 y 4 piensan lo mínimo, con margen en el tope', () {
      for (final model in ['gemini-3.8-flash', 'gemini-4-argon']) {
        final config =
            GeminiWire.bodyOf(
                  CloudRequest(
                    model: model,
                    instruction: 'x',
                    messages: const [],
                    maxOutputTokens: 48,
                  ),
                )['generationConfig']!
                as Map;
        expect(config['thinkingConfig'], {'thinkingLevel': 'low'});
        expect(config['maxOutputTokens'], 48 + kGeminiThinkingHeadroomTokens);
      }
    });

    test('2.5 Flash apaga el pensamiento y no necesita margen; 2.5 Pro no '
        'se puede apagar', () {
      Map<dynamic, dynamic> config(String model) =>
          GeminiWire.bodyOf(
                CloudRequest(
                  model: model,
                  instruction: 'x',
                  messages: const [],
                  maxOutputTokens: 48,
                ),
              )['generationConfig']!
              as Map;

      expect(config('gemini-2.5-flash')['thinkingConfig'], {
        'thinkingBudget': 0,
      });
      expect(config('gemini-2.5-flash')['maxOutputTokens'], 48);
      expect(config('gemini-2.5-flash-lite')['thinkingConfig'], {
        'thinkingBudget': 0,
      });
      expect(config('gemini-2.5-pro').containsKey('thinkingConfig'), isFalse);
      expect(
        config('gemini-2.5-pro')['maxOutputTokens'],
        48 + kGeminiThinkingHeadroomTokens,
      );
    });

    test('con «Pensar más» (F42), lo contrario: `high` del 3 en adelante, '
        'sin tope en el 2.5, y el margen grande; el 2.0 no cambia', () {
      Map<dynamic, dynamic> config(String model) =>
          GeminiWire.bodyOf(
                CloudRequest(
                  model: model,
                  instruction: 'x',
                  messages: const [],
                  maxOutputTokens: 48,
                  thinkMore: true,
                ),
              )['generationConfig']!
              as Map;

      for (final model in ['gemini-3.8-flash', 'gemini-4-argon']) {
        expect(config(model)['thinkingConfig'], {'thinkingLevel': 'high'});
        expect(
          config(model)['maxOutputTokens'],
          48 + kCloudThinkMoreHeadroomTokens,
        );
      }
      for (final model in ['gemini-2.5-flash', 'gemini-2.5-pro']) {
        expect(config(model)['thinkingConfig'], {'thinkingBudget': -1});
        expect(
          config(model)['maxOutputTokens'],
          48 + kCloudThinkMoreHeadroomTokens,
        );
      }
      expect(config('gemini-2.0-flash').containsKey('thinkingConfig'), isFalse);
      expect(config('gemini-2.0-flash')['maxOutputTokens'], 48);
    });
  });

  group('la respuesta', () {
    test('llega de a pedazos, sin partir acentos ni emojis', () async {
      google.reply(
        _sse([
          _textChunk('Roma fue la ciudad más '),
          _textChunk('poderosa de la Antigüedad 🏛️.', finish: 'STOP'),
        ]),
        chunk: 3,
      );

      final deltas = await wire.stream(_request, key: 'k').toList();

      expect(
        deltas.map((d) => d.text).join(),
        'Roma fue la ciudad más poderosa de la Antigüedad 🏛️.',
      );
    });

    test('lo que el modelo «pensó» no llega al texto', () async {
      google.reply(
        _sse([
          {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Pienso que…', 'thought': true},
                    {'text': 'La respuesta.'},
                  ],
                },
              },
            ],
          },
        ]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.map((d) => d.text).join(), 'La respuesta.');
    });

    test('al final trae los tokens del pedido y de la respuesta, con lo '
        'pensado', () async {
      google.reply(
        _sse([
          _textChunk('Hola'),
          {
            ..._textChunk('', finish: 'STOP'),
            'usageMetadata': {
              'promptTokenCount': 120,
              'candidatesTokenCount': 30,
              'thoughtsTokenCount': 15,
              'totalTokenCount': 165,
            },
          },
        ]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.last.inputTokens, 120);
      expect(deltas.last.outputTokens, 45);
    });

    test('cortada por el tope, lo dice', () async {
      google.reply(
        _sse([_textChunk('Una respuesta lar', finish: 'MAX_TOKENS')]),
      );

      final deltas = await wire.stream(_request, key: 'k').toList();
      expect(deltas.last.truncated, isTrue);
    });

    test('si el proveedor no quiere contestar el pedido, es «bloqueado»', () {
      google.reply(
        _sse([
          {
            'promptFeedback': {'blockReason': 'SAFETY'},
          },
        ]),
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

    test('y si corta sin escribir nada por sus reglas, también', () {
      google.reply(_sse([_textChunk('', finish: 'SAFETY')]));

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
  });

  group('los errores', () {
    Future<CloudModelFailure> failureOf(int status, Object body) async {
      google.reply(jsonEncode(body), status: status);
      try {
        await wire.stream(_request, key: 'k').drain<void>();
      } on CloudModelException catch (e) {
        return e.failure;
      }
      fail('no falló');
    }

    Map<String, Object> quotaError(String quotaId, {String delay = '23s'}) => {
      'error': {
        'code': 429,
        'message': 'You exceeded your current quota.',
        'status': 'RESOURCE_EXHAUSTED',
        'details': [
          {
            '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
            'violations': [
              {
                'quotaMetric':
                    'generativelanguage.googleapis.com/generate_content_requests',
                'quotaId': quotaId,
              },
            ],
          },
          {
            '@type': 'type.googleapis.com/google.rpc.RetryInfo',
            'retryDelay': delay,
          },
        ],
      },
    };

    test('el tope del día: agotada hasta la medianoche del Pacífico', () async {
      google.reply(
        jsonEncode(
          quotaError('GenerateRequestsPerDayPerProjectPerModel-FreeTier'),
        ),
        status: 429,
      );
      try {
        await wire.stream(_request, key: 'k').drain<void>();
        fail('no falló');
      } on CloudModelException catch (e) {
        expect(e.failure, CloudModelFailure.quotaExhausted);
        // 16/10 15:00 UTC → 17/10 7:00 UTC.
        expect(e.retryAfter, const Duration(hours: 16));
        expect(e.otherAccountMayWork, isTrue);
      }
    });

    test('el tope por minuto: esperar lo que dice', () async {
      google.reply(
        jsonEncode(
          quotaError(
            'GenerateRequestsPerMinutePerProjectPerModel-FreeTier',
            delay: '7.5s',
          ),
        ),
        status: 429,
      );
      try {
        await wire.stream(_request, key: 'k').drain<void>();
        fail('no falló');
      } on CloudModelException catch (e) {
        expect(e.failure, CloudModelFailure.rateLimited);
        expect(e.retryAfter, const Duration(milliseconds: 7500));
        expect(e.otherAccountMayWork, isFalse);
      }
    });

    test('la clave inválida, el permiso, el modelo y el servidor', () async {
      expect(
        await failureOf(400, {
          'error': {
            'code': 400,
            'message': 'API key not valid. Please pass a valid API key.',
            'status': 'INVALID_ARGUMENT',
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                'reason': 'API_KEY_INVALID',
              },
            ],
          },
        }),
        CloudModelFailure.invalidKey,
      );
      expect(
        await failureOf(403, {
          'error': {'code': 403, 'status': 'PERMISSION_DENIED'},
        }),
        CloudModelFailure.forbidden,
      );
      expect(
        await failureOf(400, {
          'error': {
            'code': 400,
            'message': 'User location is not supported for the API use.',
            'status': 'FAILED_PRECONDITION',
          },
        }),
        CloudModelFailure.forbidden,
      );
      expect(
        await failureOf(404, {
          'error': {'code': 404, 'status': 'NOT_FOUND'},
        }),
        CloudModelFailure.modelNotFound,
      );
      expect(
        await failureOf(400, {
          'error': {
            'code': 400,
            'message':
                'The input token count (1200000) exceeds the maximum number '
                'of tokens allowed (1048576).',
            'status': 'INVALID_ARGUMENT',
          },
        }),
        CloudModelFailure.tooLong,
      );
      expect(
        await failureOf(503, {
          'error': {'code': 503, 'status': 'UNAVAILABLE'},
        }),
        CloudModelFailure.unavailable,
      );
      expect(await failureOf(418, 'no es JSON'), CloudModelFailure.unknown);
    });

    test('sin conexión: «red»', () async {
      final offline = GeminiWire(
        dio: Dio()..httpClientAdapter = _Offline(),
        clock: () => now,
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
    Map<String, Object> model(String id, {List<String>? methods}) => {
      'name': 'models/$id',
      'displayName': 'Nombre de $id',
      'inputTokenLimit': 1048576,
      'outputTokenLimit': 65536,
      'supportedGenerationMethods':
          methods ?? ['generateContent', 'countTokens'],
    };

    test('solo los de texto que escriben, de todas las páginas', () async {
      google
        ..reply(
          jsonEncode({
            'models': [
              model('gemini-3.8-flash'),
              model('gemini-3.8-flash-tts'),
              model('gemini-embedding-001', methods: ['embedContent']),
              model('gemini-3.1-flash-image'),
            ],
            'nextPageToken': 'p2',
          }),
        )
        ..reply(
          jsonEncode({
            'models': [
              model('gemini-3.5-flash-lite'),
              model('gemini-3.8-live'),
              model('veo-3.1-generate-preview'),
            ],
          }),
        );

      final models = await wire.listModels('AIzaSECRETA');

      expect(models.map((m) => m.id), [
        'gemini-3.5-flash-lite',
        'gemini-3.8-flash',
      ]);
      expect(models.last.displayName, 'Nombre de gemini-3.8-flash');
      expect(models.last.inputTokens, 1048576);
      expect(google.requests.last.uri.queryParameters['pageToken'], 'p2');
      expect(
        google.requests.every((r) => !r.uri.toString().contains('AIzaSECRETA')),
        isTrue,
      );
    });

    test('el recomendado: el Flash estable más nuevo', () {
      List<CloudModelInfo> of(List<String> ids) => [
        for (final id in ids) CloudModelInfo(id: id, displayName: id),
      ];

      expect(
        wire.recommendedModel(
          of([
            'gemini-2.5-flash',
            'gemini-3.5-flash-lite',
            'gemini-3.6-flash',
            'gemini-3.8-flash',
            'gemini-3-flash-preview',
            'gemini-3.1-pro-preview',
          ]),
        ),
        'gemini-3.8-flash',
      );
      expect(
        wire.recommendedModel(
          of(['gemini-3.9-flash-preview', 'gemini-3.8-flash']),
        ),
        'gemini-3.9-flash-preview',
      );
      expect(
        wire.recommendedModel(
          of(['gemini-3.8-flash-preview', 'gemini-3.8-flash']),
        ),
        'gemini-3.8-flash',
      );
      expect(
        wire.recommendedModel(of(['gemini-3.5-flash-lite', 'gemini-4-argon'])),
        'gemini-3.5-flash-lite',
      );
      expect(
        wire.recommendedModel(of(['gemini-3.9-flash', 'gemini-3.10-flash'])),
        'gemini-3.10-flash',
      );
      expect(wire.recommendedModel(of(['gemini-4-argon'])), 'gemini-4-argon');
      expect(wire.recommendedModel(const []), isNull);
    });
  });

  group('los eventos de una respuesta en vivo', () {
    Stream<Uint8List> bytes(String text, {int chunk = 2}) {
      final all = utf8.encode(text);
      return Stream.fromIterable([
        for (var i = 0; i < all.length; i += chunk)
          Uint8List.fromList(all.sublist(i, (i + chunk).clamp(0, all.length))),
      ]);
    }

    test('junta líneas de datos, lee el nombre y salta comentarios', () async {
      final events = await sseEvents(
        bytes(
          ': un comentario\n'
          'event: mensaje\n'
          'data: línea uno\n'
          'data: línea dos\n'
          '\n'
          'data:sin espacio\r\n'
          '\r\n'
          'data: el último, sin línea vacía',
        ),
      ).toList();

      expect(events, [
        (event: 'mensaje', data: 'línea uno\nlínea dos'),
        (event: null, data: 'sin espacio'),
        (event: null, data: 'el último, sin línea vacía'),
      ]);
    });
  });
}

class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => Future.error(
    DioException.connectionError(requestOptions: options, reason: 'sin red'),
  );

  @override
  void close({bool force = false}) {}
}
