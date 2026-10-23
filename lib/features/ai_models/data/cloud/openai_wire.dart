import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/sse.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';

/// Lo que se le suma al tope de una respuesta en los modelos que razonan
/// antes de escribir: lo razonado cuenta dentro de `max_completion_tokens`, y
/// con un tope chico la respuesta llegaría vacía.
const kOpenAiReasoningHeadroomTokens = 2048;

/// [CloudWire] de OpenAI, sobre Chat Completions (F32).
///
/// No sobre la API «Responses», que OpenAI recomienda para proyectos nuevos:
/// esa guarda las respuestas en sus servidores por defecto, y la decisión del
/// usuario es que nada del contenido quede guardado fuera del teléfono. Chat
/// Completions no guarda nada si no se le pide (`store` es falso por
/// defecto): cada pedido lleva lo conversado.
class OpenAiWire implements CloudWire {
  OpenAiWire({required Dio dio, Duration idleTimeout = kCloudIdleTimeout})
    : _dio = dio,
      _idleTimeout = idleTimeout;

  static const _base = 'https://api.openai.com/v1';

  final Dio _dio;
  final Duration _idleTimeout;

  @override
  AiProvider get provider => AiProvider.openAi;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async {
    final response = await _send(
      () => _dio.get<Object>(
        '$_base/models',
        options: _options(key, ResponseType.json),
      ),
    );
    final body = response.data;
    final data = body is Map
        ? (body['data'] as List?) ?? const []
        : const <Object?>[];
    return [
      for (final raw in data)
        if (raw is Map && raw['id'] is String)
          if (raw['id'] as String case final id when isTextModel(id))
            CloudModelInfo(id: id, displayName: displayNameOf(id)),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Los que no escriben texto por Chat Completions: voz, tiempo real,
  /// imágenes, búsqueda, vectores, moderación, los que solo andan por
  /// «Responses» (`-pro`, codex, deep-research, computer-use) y los viejos de
  /// completar texto.
  static final _notText = RegExp(
    'audio|realtime|tts|transcribe|image|search|embedding|moderation|'
    'dall-e|whisper|instruct|codex|-pro|deep-research|computer-use',
  );

  /// Las versiones fijadas con fecha (`gpt-4o-2024-08-06`, `o3-2025-04-16`):
  /// son la misma que el nombre sin fecha, que la app ya muestra.
  static final _dated = RegExp(r'-\d{4}-\d{2}-\d{2}$|-\d{4}$');

  /// Si [id] es un modelo de texto que escribe por Chat Completions.
  static bool isTextModel(String id) =>
      RegExp(r'^(gpt-|o\d)').hasMatch(id) &&
      !_notText.hasMatch(id) &&
      !_dated.hasMatch(id);

  /// Como lo escribe OpenAI: «gpt-5.2-mini» → «GPT-5.2 mini»; la serie «o»
  /// queda tal cual («o4-mini»).
  static String displayNameOf(String id) => modelLabel(id);

  /// El `gpt-N(.M)` más nuevo sin sufijo; si no hay, el primero.
  @override
  String? recommendedModel(List<CloudModelInfo> models) {
    if (models.isEmpty) return null;
    final plain = RegExp(r'^gpt-(\d+)(?:\.(\d+))?$');
    String? winner;
    var winnerKey = const (-1, -1);
    for (final model in models) {
      final match = plain.firstMatch(model.id);
      if (match == null) continue;
      // Como enteros: «5.10» es más nuevo que «5.9».
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

  /// Si [model] razona antes de escribir: la serie «o» y GPT-5 en adelante,
  /// salvo los `-chat`, que contestan directo.
  static bool reasons(String model) {
    if (RegExp(r'^o\d').hasMatch(model)) return true;
    final gpt = RegExp(r'^gpt-(\d+)').firstMatch(model);
    if (gpt == null) return false;
    return int.parse(gpt.group(1)!) >= 5 && !model.contains('-chat');
  }

  /// El cuerpo del pedido, tal como se manda.
  static Map<String, Object> bodyOf(CloudRequest request) {
    final reasoning = reasons(request.model);
    return {
      'model': request.model,
      'messages': [
        if (request.instruction.isNotEmpty)
          {
            // Los que razonan leen la instrucción como `developer`.
            'role': reasoning ? 'developer' : 'system',
            'content': request.instruction,
          },
        for (final message in request.messages)
          if (message.role == CloudRole.model)
            {'role': 'assistant', 'content': message.text}
          else if (message.images.isEmpty)
            {'role': 'user', 'content': message.text}
          else
            {
              'role': 'user',
              'content': [
                if (message.text.isNotEmpty)
                  {'type': 'text', 'text': message.text},
                for (final image in message.images)
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url':
                          'data:${imageMimeType(image)};base64,'
                          '${base64Encode(image)}',
                    },
                  },
              ],
            },
      ],
      'max_completion_tokens':
          request.maxOutputTokens +
          (reasoning ? kOpenAiReasoningHeadroomTokens : 0),
      // Razonar lo menos posible, que es lo más rápido. En los que no razonan
      // mandarlo es un error 400.
      if (reasoning) 'reasoning_effort': 'low',
      'stream': true,
      'stream_options': {'include_usage': true},
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
        '$_base/chat/completions',
        data: bodyOf(request),
        cancelToken: cancel,
        options: _options(
          key,
          ResponseType.stream,
          receiveTimeout: kCloudFirstByteTimeout,
        ),
      ),
    );
    final body = response.data;
    if (body == null) return;

    var wroteSomething = false;
    // Cierra con `[DONE]` o con un `finish_reason`: sin ninguno, se cortó.
    var finished = false;
    await for (final event in sseEvents(
      guardedCloudBody(body.stream, idle: _idleTimeout, cancel: cancel),
    )) {
      if (event.data.trim() == '[DONE]') {
        finished = true;
        break;
      }
      final Object? json;
      try {
        json = jsonDecode(event.data);
      } on FormatException {
        continue;
      }
      if (json is! Map) continue;
      if (json['error'] is Map) throw failureFrom(0, json, Headers());

      final usage = json['usage'];
      if (usage is Map) {
        final input = usage['prompt_tokens'];
        final output = usage['completion_tokens'];
        yield CloudDelta(
          inputTokens: input is int ? input : null,
          outputTokens: output is int ? output : null,
        );
      }
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices.first;
      if (choice is! Map) continue;
      final delta = choice['delta'];
      final text = delta is Map ? delta['content'] : null;
      final refusal = delta is Map ? delta['refusal'] : null;
      final finish = choice['finish_reason'];
      if (finish != null) finished = true;
      if (text is String && text.isNotEmpty) wroteSomething = true;
      if (!wroteSomething &&
          ((refusal is String && refusal.isNotEmpty) ||
              finish == 'content_filter')) {
        throw CloudModelException(
          CloudModelFailure.blocked,
          detail: refusal is String && refusal.isNotEmpty ? refusal : '$finish',
        );
      }
      final piece = text is String ? text : '';
      final truncated = finish == 'length';
      if (piece.isEmpty && !truncated) continue;
      yield CloudDelta(text: piece, truncated: truncated);
    }
    if (!finished && !(cancel?.isCancelled ?? false)) throw cloudStreamCutOff;
  }

  Options _options(String key, ResponseType type, {Duration? receiveTimeout}) =>
      cloudOptions(
        {'authorization': 'Bearer $key'},
        type,
        receiveTimeout: receiveTimeout,
      );

  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) =>
      sendCloudRequest(request, failureFrom: failureFrom);

  /// Los códigos de un 429 que dicen que se terminó el saldo o el tope de
  /// gasto: reintentar no sirve, hay que pasar a otra cuenta.
  static bool _outOfCredit(String code) =>
      code == 'insufficient_quota' ||
      code == 'credit_balance_exhausted' ||
      code.endsWith('_spend_limit_exceeded') ||
      code.endsWith('_usage_limit_exceeded');

  /// Traduce un error de OpenAI (`{"error": {message, type, code}}`) a lo que
  /// la app sabe decidir. Manda el código antes que el estado: un 429 puede
  /// ser el tope por minuto o el saldo terminado. [status] es 0 si llegó
  /// dentro del flujo.
  static CloudModelException failureFrom(
    int status,
    Object? body,
    Headers headers,
  ) {
    final error = body is Map ? body['error'] : null;
    final code = error is Map ? '${error['code'] ?? ''}' : '';
    final type = error is Map ? '${error['type'] ?? ''}' : '';
    final message = error is Map ? '${error['message'] ?? ''}' : '';
    CloudModelException fail(CloudModelFailure failure, {Duration? after}) =>
        CloudModelException(
          failure,
          detail: message.isEmpty ? (code.isEmpty ? type : code) : message,
          retryAfter: after,
          statusCode: status == 0 ? null : status,
        );

    if (_outOfCredit(code) || _outOfCredit(type)) {
      return fail(CloudModelFailure.quotaExhausted);
    }
    if (status == 429 || code == 'rate_limit_exceeded') {
      // Sin cabecera, OpenAI dice cuánto en el mensaje («try again in 6m0s»).
      return fail(
        CloudModelFailure.rateLimited,
        after: retryAfterOf(headers) ?? retryDelayInMessage(message),
      );
    }
    if (status == 401 || code == 'invalid_api_key') {
      return fail(CloudModelFailure.invalidKey);
    }
    if (status == 403 || code == 'unsupported_country_region_territory') {
      return fail(CloudModelFailure.forbidden);
    }
    if (status == 404 || code == 'model_not_found') {
      return fail(CloudModelFailure.modelNotFound);
    }
    if (code == 'context_length_exceeded') {
      return fail(CloudModelFailure.tooLong);
    }
    if (status == 408) return fail(CloudModelFailure.timeout);
    // 500, 502, 503, 504: saturado o caído de su lado.
    if (status >= 500 || type == 'server_error') {
      return fail(CloudModelFailure.unavailable, after: retryAfterOf(headers));
    }
    if (status == 400 || status == 422 || type == 'invalid_request_error') {
      return fail(CloudModelFailure.badRequest);
    }
    return fail(CloudModelFailure.unknown);
  }
}
