import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/sse.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';

/// Lo que se le suma al tope de una respuesta en los modelos que siempre
/// piensan antes de escribir (los 5.x): lo pensado cuenta dentro de
/// `max_tokens`, y con un tope chico la respuesta llegaría vacía.
const kAnthropicThinkingHeadroomTokens = 2048;

/// El modelo que la app recomienda si está en la lista de la clave.
const kAnthropicRecommendedModel = 'claude-opus-5-5';

/// La cabecera beta que habilita `fallbacks: "default"`.
const kAnthropicFallbackBeta = 'server-side-fallback-2026-07-01';

/// [CloudWire] de Claude, sobre la API de mensajes de Anthropic (F32).
///
/// Por HTTP directo: Dart no tiene un SDK oficial de Anthropic. La API no
/// guarda lo conversado: cada pedido lo lleva entero.
class AnthropicWire implements CloudWire {
  AnthropicWire({required Dio dio, Duration idleTimeout = kCloudIdleTimeout})
    : _dio = dio,
      _idleTimeout = idleTimeout;

  static const _base = 'https://api.anthropic.com/v1';

  final Dio _dio;
  final Duration _idleTimeout;

  @override
  AiProvider get provider => AiProvider.anthropic;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async {
    final models = <CloudModelInfo>[];
    String? after;
    var more = false;
    do {
      final response = await _send(
        () => _dio.get<Object>(
          '$_base/models',
          queryParameters: {'limit': 1000, 'after_id': ?after},
          options: _options(key, ResponseType.json),
        ),
      );
      final body = response.data;
      if (body is! Map) break;
      final data = (body['data'] as List?) ?? const [];
      for (final raw in data) {
        if (raw is! Map) continue;
        final info = _modelInfo(raw);
        if (info != null) models.add(info);
      }
      final last = body['last_id'];
      more = body['has_more'] == true && last is String && last.isNotEmpty;
      after = more ? last : null;
    } while (more);
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  static CloudModelInfo? _modelInfo(Map<dynamic, dynamic> raw) {
    final id = raw['id'];
    if (id is! String || !id.startsWith('claude-')) return null;
    final display = raw['display_name'];
    final input = raw['max_input_tokens'];
    final output = raw['max_tokens'];
    return CloudModelInfo(
      id: id,
      displayName: display is String && display.isNotEmpty ? display : id,
      inputTokens: input is int ? input : null,
      outputTokens: output is int ? output : null,
    );
  }

  /// [kAnthropicRecommendedModel] si está; si no, el Opus más nuevo; si no,
  /// el primero.
  @override
  String? recommendedModel(List<CloudModelInfo> models) {
    if (models.isEmpty) return null;
    if (models.any((m) => m.id == kAnthropicRecommendedModel)) {
      return kAnthropicRecommendedModel;
    }
    final opus = RegExp(r'^claude-opus-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$');
    String? winner;
    var winnerKey = const (-1, -1);
    for (final model in models) {
      final match = opus.firstMatch(model.id);
      if (match == null) continue;
      final key = (
        int.parse(match.group(1)!),
        int.tryParse(match.group(2) ?? '') ?? 0,
      );
      if (key.$1 > winnerKey.$1 ||
          (key.$1 == winnerKey.$1 && key.$2 > winnerKey.$2)) {
        winner = model.id;
        winnerKey = key;
      }
    }
    return winner ?? models.first.id;
  }

  /// Si [model] es de la familia 5 (Opus, Sonnet, Haiku, Fable, Mythos):
  /// siempre piensa, y lo que piensa se regula con `effort`.
  static bool isFifthGeneration(String model) => RegExp(
    r'^claude-(opus|sonnet|haiku|fable|mythos)-5(?:$|-)',
  ).hasMatch(model);

  /// Los modelos que aceptan `fallbacks: "default"`: si el filtro de
  /// seguridad rechaza el pedido, lo reintenta otro modelo de Claude en el
  /// mismo flujo. En los demás (Haiku 5.5, los 4.x) es un error 400.
  static const fallbackModels = {
    'claude-fable-5-1',
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-sonnet-5-5',
  };

  /// El cuerpo del pedido, tal como se manda.
  static Map<String, Object> bodyOf(CloudRequest request) {
    final fifth = isFifthGeneration(request.model);
    return {
      'model': request.model,
      'max_tokens':
          request.maxOutputTokens +
          (fifth ? kAnthropicThinkingHeadroomTokens : 0),
      if (request.instruction.isNotEmpty) 'system': request.instruction,
      'messages': [
        for (final message in request.messages)
          {
            'role': message.role == CloudRole.user ? 'user' : 'assistant',
            'content': [
              for (final image in message.images)
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': imageMimeType(image),
                    'data': base64Encode(image),
                  },
                },
              if (message.text.isNotEmpty)
                {'type': 'text', 'text': message.text},
            ],
          },
      ],
      // Pensar lo menos posible, que es lo más rápido. Sin `thinking`: en
      // Opus 5.5 apagarlo es un error; `effort` es lo que lo regula.
      if (fifth) 'output_config': {'effort': 'low'},
      if (fallbackModels.contains(request.model)) 'fallbacks': 'default',
      'stream': true,
    };
  }

  @override
  Stream<CloudDelta> stream(
    CloudRequest request, {
    required String key,
    CancelToken? cancel,
  }) async* {
    final response = await _send(
      () => _dio.post<ResponseBody>(
        '$_base/messages',
        data: bodyOf(request),
        cancelToken: cancel,
        options: _options(
          key,
          ResponseType.stream,
          beta: fallbackModels.contains(request.model)
              ? kAnthropicFallbackBeta
              : null,
          receiveTimeout: kCloudFirstByteTimeout,
        ),
      ),
    );
    final body = response.data;
    if (body == null) return;

    // Cierra con `message_stop`: sin él, la respuesta se cortó.
    var finished = false;
    await for (final event in sseEvents(
      guardedCloudBody(body.stream, idle: _idleTimeout, cancel: cancel),
    )) {
      final Object? json;
      try {
        json = jsonDecode(event.data);
      } on FormatException {
        continue;
      }
      if (json is! Map) continue;
      switch (json['type']) {
        case 'message_start':
          final usage = (json['message'] as Map?)?['usage'];
          final input = usage is Map ? usage['input_tokens'] : null;
          if (input is int) yield CloudDelta(inputTokens: input);
        case 'content_block_delta':
          // Solo el texto: el pensamiento y su firma no son la respuesta.
          final delta = json['delta'];
          if (delta is Map && delta['type'] == 'text_delta') {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              yield CloudDelta(text: text);
            }
          }
        case 'message_delta':
          final stop = (json['delta'] as Map?)?['stop_reason'];
          if (stop == 'refusal') {
            // Rechazado por sus reglas (con respaldo: rechazado por todos).
            // Lo escrito hasta ahí no vale como respuesta.
            throw const CloudModelException(
              CloudModelFailure.blocked,
              detail: 'refusal',
            );
          }
          if (stop != null) finished = true;
          final usage = json['usage'];
          final output = usage is Map ? usage['output_tokens'] : null;
          yield CloudDelta(
            outputTokens: output is int ? output : null,
            truncated: stop == 'max_tokens',
          );
        case 'message_stop':
          finished = true;
        case 'error':
          throw failureFrom(0, json, Headers());
      }
    }
    if (!finished && !(cancel?.isCancelled ?? false)) throw cloudStreamCutOff;
  }

  Options _options(
    String key,
    ResponseType type, {
    String? beta,
    Duration? receiveTimeout,
  }) => cloudOptions(
    {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': ?beta,
    },
    type,
    receiveTimeout: receiveTimeout,
  );

  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) =>
      sendCloudRequest(request, failureFrom: failureFrom);

  /// Traduce un error de Anthropic (`{"type": "error", "error": {type,
  /// message}}`) a lo que la app sabe decidir. [status] es 0 si llegó dentro
  /// del flujo (entonces manda el tipo).
  static CloudModelException failureFrom(
    int status,
    Object? body,
    Headers headers,
  ) {
    final error = body is Map ? body['error'] : null;
    final type = error is Map ? '${error['type'] ?? ''}' : '';
    final message = error is Map ? '${error['message'] ?? ''}' : '';
    final lower = message.toLowerCase();
    CloudModelException fail(CloudModelFailure failure, {Duration? after}) =>
        CloudModelException(
          failure,
          detail: message.isEmpty ? type : message,
          retryAfter: after,
          statusCode: status == 0 ? null : status,
        );

    if (status == 402 ||
        type == 'billing_error' ||
        lower.contains('credit balance') ||
        lower.contains('usage limit')) {
      return fail(CloudModelFailure.quotaExhausted);
    }
    if (status == 429 || type == 'rate_limit_error') {
      return fail(CloudModelFailure.rateLimited, after: retryAfterOf(headers));
    }
    if (status == 401 || type == 'authentication_error') {
      return fail(CloudModelFailure.invalidKey);
    }
    if (status == 403 || type == 'permission_error') {
      return fail(CloudModelFailure.forbidden);
    }
    if (status == 404 || type == 'not_found_error') {
      return fail(CloudModelFailure.modelNotFound);
    }
    if (status == 413 ||
        type == 'request_too_large' ||
        lower.contains('prompt is too long')) {
      return fail(CloudModelFailure.tooLong);
    }
    if (status == 408) return fail(CloudModelFailure.timeout);
    // 500, 502, 503, 504 y el 529 de Anthropic (`overloaded_error`).
    if (status >= 500 || type == 'overloaded_error' || type == 'api_error') {
      return fail(CloudModelFailure.unavailable, after: retryAfterOf(headers));
    }
    if (status == 400 || status == 422 || type == 'invalid_request_error') {
      return fail(CloudModelFailure.badRequest);
    }
    return fail(CloudModelFailure.unknown);
  }
}
