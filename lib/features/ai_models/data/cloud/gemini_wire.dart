import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/sse.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_thinking.dart';
import 'package:sinapsis/features/ai_models/domain/services/quota_day.dart';

/// Lo que se le suma al tope de una respuesta cuando el modelo «piensa» antes
/// de escribir: lo pensado cuenta dentro de `maxOutputTokens`, y con un tope
/// chico (elegir un tema: una línea) la respuesta llegaría vacía.
const kGeminiThinkingHeadroomTokens = 2048;

/// [CloudWire] de Gemini, sobre `generateContent` (F32).
///
/// No sobre la API «Interactions», que Google recomienda para proyectos nuevos:
/// esa guarda las conversaciones en sus servidores por defecto (un día en la
/// capa gratuita), y la decisión del usuario es que nada del contenido quede
/// guardado fuera del teléfono. `generateContent` no guarda nada: cada pedido
/// lleva lo conversado. Google dice que «sigue totalmente soportada».
///
/// La clave va en la cabecera `x-goog-api-key`, nunca en la dirección: las
/// direcciones se registran.
class GeminiWire implements CloudWire {
  GeminiWire({
    required Dio dio,
    DateTime Function()? clock,
    Duration idleTimeout = kCloudIdleTimeout,
  }) : _dio = dio,
       _clock = clock ?? DateTime.now,
       _idleTimeout = idleTimeout;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  final Dio _dio;
  final DateTime Function() _clock;
  final Duration _idleTimeout;

  @override
  AiProvider get provider => AiProvider.gemini;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async {
    final models = <CloudModelInfo>[];
    for (final raw in await rawModels(key)) {
      final info = _modelInfo(raw);
      if (info != null) models.add(info);
    }
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  /// La lista de modelos de [key] tal como la da Google, todas las páginas:
  /// de acá salen los de texto ([listModels]) y, aparte, los de imagen (F43,
  /// `GeminiImageWire`), sin que unos se mezclen con los otros.
  Future<List<Map<dynamic, dynamic>>> rawModels(String key) async {
    final models = <Map<dynamic, dynamic>>[];
    String? page;
    do {
      final response = await _send(
        () => _dio.get<Object>(
          '$_base/models',
          queryParameters: {'pageSize': 1000, 'pageToken': ?page},
          options: _options(key, ResponseType.json),
        ),
      );
      final body = response.data;
      if (body is! Map) break;
      for (final raw in (body['models'] as List?) ?? const []) {
        if (raw is Map) models.add(raw);
      }
      final next = body['nextPageToken'];
      page = next is String && next.isNotEmpty ? next : null;
    } while (page != null);
    return models;
  }

  /// Solo los modelos de texto que escriben respuestas: fuera los de voz,
  /// imágenes, tiempo real, transcribir, vectores y robots.
  static final _notText = RegExp(
    'tts|image|live|audio|transcribe|embedding|robotics|translate|'
    'computer-use|omni|nano-banana|aqa',
  );

  static CloudModelInfo? _modelInfo(Map<dynamic, dynamic> raw) {
    final name = raw['name'];
    if (name is! String || !name.startsWith('models/gemini-')) return null;
    final methods = raw['supportedGenerationMethods'];
    if (methods is! List || !methods.contains('generateContent')) return null;
    final id = name.substring('models/'.length);
    if (_notText.hasMatch(id)) return null;
    final display = raw['displayName'];
    final input = raw['inputTokenLimit'];
    final output = raw['outputTokenLimit'];
    return CloudModelInfo(
      id: id,
      displayName: display is String && display.isNotEmpty ? display : id,
      inputTokens: input is int ? input : null,
      outputTokens: output is int ? output : null,
    );
  }

  /// El más nuevo de los «Flash» (rápidos y capaces); si no hay, el más nuevo
  /// de los «Flash-Lite»; si no, el primero. Los estables antes que los de
  /// prueba (`-preview`, `-exp`).
  @override
  String? recommendedModel(List<CloudModelInfo> models) {
    if (models.isEmpty) return null;
    final flash = RegExp(
      r'^gemini-(\d+)(?:\.(\d+))?-flash(-preview.*|-exp.*)?$',
    );
    final lite = RegExp(
      r'^gemini-(\d+)(?:\.(\d+))?-flash-lite(-preview.*|-exp.*)?$',
    );
    String? best(RegExp pattern) {
      String? winner;
      var winnerKey = const (-1, -1, 0);
      for (final model in models) {
        final match = pattern.firstMatch(model.id);
        if (match == null) continue;
        // La versión como enteros: «3.10» es más nueva que «3.9».
        final key = (
          int.parse(match.group(1)!),
          int.tryParse(match.group(2) ?? '') ?? 0,
          match.group(3) == null ? 1 : 0,
        );
        if (key.$1 > winnerKey.$1 ||
            (key.$1 == winnerKey.$1 && key.$2 > winnerKey.$2) ||
            (key.$1 == winnerKey.$1 &&
                key.$2 == winnerKey.$2 &&
                key.$3 > winnerKey.$3)) {
          winner = model.id;
          winnerKey = key;
        }
      }
      return winner;
    }

    return best(flash) ?? best(lite) ?? models.first.id;
  }

  /// Cómo pensar según el modelo: lo menos posible, que es lo más rápido.
  /// Gemini 3 y 4 usan `thinkingLevel` (y no se apaga); 2.5 usa
  /// `thinkingBudget`, que en Flash y Flash-Lite se apaga con 0 y en Pro no se
  /// puede apagar. Mandar los dos juntos es un error 400.
  ///
  /// Con [thinkMore] («Pensar más», F42), lo contrario: `thinkingLevel: high`
  /// del 3 en adelante y, en el 2.5, `thinkingBudget: -1`, que deja pensar lo
  /// que el modelo crea necesario.
  static Map<String, Object>? thinkingFor(
    String model, {
    bool thinkMore = false,
  }) {
    final generation = geminiGeneration(model);
    if (generation == null) return null;
    final (major, minor) = generation;
    if (thinkMore && geminiThinks(model)) {
      return major >= 3 ? {'thinkingLevel': 'high'} : {'thinkingBudget': -1};
    }
    if (major >= 3) return {'thinkingLevel': 'low'};
    if (major == 2 && minor >= 5 && !model.contains('-pro')) {
      return {'thinkingBudget': 0};
    }
    return null;
  }

  /// Si el modelo piensa aunque se le pida lo mínimo.
  static bool thinksAnyway(String model) {
    final thinking = thinkingFor(model);
    if (thinking != null) return thinking.containsKey('thinkingLevel');
    return model.startsWith('gemini-2.5-pro');
  }

  /// El cuerpo del pedido, tal como se manda.
  static Map<String, Object> bodyOf(CloudRequest request) {
    final deep = request.thinkMore && geminiThinks(request.model);
    final thinking = thinkingFor(request.model, thinkMore: deep);
    return {
      'systemInstruction': {
        'parts': [
          {'text': request.instruction},
        ],
      },
      'contents': [
        for (final message in request.messages)
          {
            'role': message.role == CloudRole.user ? 'user' : 'model',
            'parts': [
              if (message.text.isNotEmpty) {'text': message.text},
              for (final image in message.images)
                {
                  'inlineData': {
                    'mimeType': imageMimeType(image),
                    'data': base64Encode(image),
                  },
                },
            ],
          },
      ],
      'generationConfig': {
        'maxOutputTokens':
            request.maxOutputTokens +
            (deep
                ? kCloudThinkMoreHeadroomTokens
                : thinksAnyway(request.model)
                ? kGeminiThinkingHeadroomTokens
                : 0),
        'thinkingConfig': ?thinking,
      },
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
        '$_base/models/${Uri.encodeComponent(request.model)}'
        ':streamGenerateContent',
        queryParameters: const {'alt': 'sse'},
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
    // Gemini cierra con un `finishReason`: sin él, la respuesta se cortó.
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
      if (json['error'] is Map) {
        throw failureFrom(
          (json['error'] as Map)['code'] as int? ?? 500,
          json,
          now: _clock(),
        );
      }
      final feedback = json['promptFeedback'];
      if (feedback is Map && feedback['blockReason'] != null) {
        throw CloudModelException(
          CloudModelFailure.blocked,
          detail: '${feedback['blockReason']}',
        );
      }
      final text = StringBuffer();
      var truncated = false;
      String? finish;
      final candidates = json['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final candidate = candidates.first;
        if (candidate is Map) {
          final parts = (candidate['content'] as Map?)?['parts'];
          if (parts is List) {
            for (final part in parts) {
              if (part is! Map || part['thought'] == true) continue;
              final piece = part['text'];
              if (piece is String) text.write(piece);
            }
          }
          finish = candidate['finishReason'] as String?;
          if (finish != null) finished = true;
          truncated = finish == 'MAX_TOKENS';
        }
      }
      final usage = json['usageMetadata'];
      int? input;
      int? output;
      if (usage is Map) {
        input = usage['promptTokenCount'] as int?;
        final candidatesTokens = usage['candidatesTokenCount'] as int?;
        final thoughts = usage['thoughtsTokenCount'] as int?;
        if (candidatesTokens != null || thoughts != null) {
          output = (candidatesTokens ?? 0) + (thoughts ?? 0);
        }
      }
      if (text.isNotEmpty) wroteSomething = true;
      if (!wroteSomething && finish != null && _blockedFinish(finish)) {
        throw CloudModelException(CloudModelFailure.blocked, detail: finish);
      }
      if (text.isEmpty && input == null && output == null && !truncated) {
        continue;
      }
      yield CloudDelta(
        text: text.toString(),
        inputTokens: input,
        outputTokens: output,
        truncated: truncated,
      );
    }
    if (!finished && !(cancel?.isCancelled ?? false)) throw cloudStreamCutOff;
  }

  static bool _blockedFinish(String finish) => const {
    'SAFETY',
    'RECITATION',
    'BLOCKLIST',
    'PROHIBITED_CONTENT',
    'SPII',
  }.contains(finish);

  Options _options(String key, ResponseType type, {Duration? receiveTimeout}) =>
      cloudOptions(
        {'x-goog-api-key': key},
        type,
        receiveTimeout: receiveTimeout,
      );

  /// Manda el pedido y, si el proveedor contestó con un error, lo traduce.
  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) =>
      sendCloudRequest(
        request,
        failureFrom: (status, body, headers) =>
            failureFrom(status, body, now: _clock(), headers: headers),
      );

  /// Traduce un error de Gemini (`{"error": {code, message, status,
  /// details}}`) a lo que la app sabe decidir.
  ///
  /// El 429 trae, en `details`, cuál tope se pasó: si su `quotaId` es «por
  /// día» (`…PerDay…`), la cuota de esa cuenta se terminó hasta la medianoche
  /// del Pacífico; si no, es el tope por minuto y alcanza con esperar lo que
  /// dice `RetryInfo.retryDelay`.
  static CloudModelException failureFrom(
    int status,
    Object? body, {
    required DateTime now,
    Headers? headers,
  }) {
    final error = body is Map ? body['error'] : null;
    final message = error is Map ? '${error['message'] ?? ''}' : '';
    final code = error is Map ? '${error['status'] ?? ''}' : '';
    final details = error is Map && error['details'] is List
        ? (error['details'] as List).whereType<Map<dynamic, dynamic>>().toList()
        : const <Map<dynamic, dynamic>>[];
    String reasonOf() {
      for (final detail in details) {
        final reason = detail['reason'];
        if (reason is String) return reason;
      }
      return '';
    }

    Duration? retryDelay() {
      for (final detail in details) {
        final delay = detail['retryDelay'];
        if (delay is String) {
          final seconds = double.tryParse(delay.replaceAll('s', ''));
          if (seconds != null) {
            return Duration(milliseconds: (seconds * 1000).round());
          }
        }
      }
      return null;
    }

    bool perDay() {
      for (final detail in details) {
        final violations = detail['violations'];
        if (violations is! List) continue;
        for (final violation in violations) {
          if (violation is! Map) continue;
          final id = '${violation['quotaId'] ?? ''}'.toLowerCase();
          if (id.contains('perday')) return true;
        }
      }
      return false;
    }

    final lower = message.toLowerCase();
    CloudModelException fail(CloudModelFailure failure, {Duration? after}) =>
        CloudModelException(
          failure,
          detail: message.isEmpty ? code : message,
          retryAfter: after,
          statusCode: status,
        );

    // Lo que pide esperar: lo que dice el cuerpo, o la cabecera.
    Duration? waitAsked() =>
        retryDelay() ?? (headers == null ? null : retryAfterOf(headers));

    if (status == 429 || code == 'RESOURCE_EXHAUSTED') {
      // Por día, lo dice el tope que se pasó o, sin detalle, el mensaje.
      if (perDay() || lower.contains('per day') || lower.contains('perday')) {
        return fail(
          CloudModelFailure.quotaExhausted,
          after: nextQuotaReset(now).difference(now.toUtc()),
        );
      }
      return fail(CloudModelFailure.rateLimited, after: waitAsked());
    }
    if (reasonOf() == 'API_KEY_INVALID' ||
        lower.contains('api key not valid') ||
        lower.contains('api key expired') ||
        status == 401) {
      return fail(CloudModelFailure.invalidKey);
    }
    if (status == 403 || code == 'PERMISSION_DENIED') {
      return fail(CloudModelFailure.forbidden);
    }
    if (code == 'FAILED_PRECONDITION') {
      // «La capa gratuita no está disponible en tu país», p. ej.
      return fail(CloudModelFailure.forbidden);
    }
    if (status == 404 || code == 'NOT_FOUND') {
      return fail(CloudModelFailure.modelNotFound);
    }
    if (status == 400 &&
        (lower.contains('token') &&
            (lower.contains('exceed') || lower.contains('maximum')))) {
      return fail(CloudModelFailure.tooLong);
    }
    if (status == 408) return fail(CloudModelFailure.timeout);
    // 500, 502, 503, 504: caído o saturado de su lado (`UNAVAILABLE`,
    // `INTERNAL`, `DEADLINE_EXCEEDED`).
    if (status >= 500) {
      return fail(CloudModelFailure.unavailable, after: waitAsked());
    }
    if (status == 400 || code == 'INVALID_ARGUMENT') {
      return fail(CloudModelFailure.badRequest);
    }
    return fail(CloudModelFailure.unknown);
  }
}
