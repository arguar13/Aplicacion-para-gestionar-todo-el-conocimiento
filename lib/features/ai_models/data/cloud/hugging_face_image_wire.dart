import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_image_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';

/// [ImageWire] de Hugging Face (F43): los modelos abiertos de
/// [kOpenImageModels] pedidos por los proveedores de inferencia de Hugging
/// Face (`router.huggingface.co`) con el token de la persona.
///
/// Verificado el 2026-10-28 en
/// https://huggingface.co/docs/inference-providers/tasks/text-to-image y en
/// el cliente oficial (`@huggingface/inference`):
///
/// - **Qué proveedor dibuja cada modelo** lo dice el propio Hub
///   (`/api/models/{id}?expand[]=inferenceProviderMapping`): se usa el primero
///   que esté `live` para `text-to-image` de los que la app sabe hablar.
/// - **Cada proveedor tiene su formato**, como en el cliente oficial:
///   `hf-inference` devuelve los bytes de la imagen; Nscale, el de imágenes
///   de OpenAI; fal.ai, una cola que se consulta hasta que termina y una
///   dirección de donde bajar la imagen; Replicate, la predicción esperada
///   con `Prefer: wait` y la dirección de la imagen.
/// - **Lo cobra Hugging Face** con sus créditos: las cuentas gratis no traen
///   (hay que comprarlos), PRO trae US$ 2 por mes. Sin créditos contesta 402.
class HuggingFaceImageWire implements ImageWire {
  HuggingFaceImageWire({
    required Dio dio,
    Duration pollInterval = const Duration(milliseconds: 500),
    int maxPolls = 360,
  }) : _dio = dio,
       _pollInterval = pollInterval,
       _maxPolls = maxPolls;

  static const _hub = 'https://huggingface.co';
  static const _router = 'https://router.huggingface.co';

  /// Los proveedores de inferencia que la app sabe usar, en el orden en que
  /// se prefieren: los que contestan de una antes que la cola.
  static const supportedProviders = [
    'hf-inference',
    'nscale',
    'fal-ai',
    'replicate',
  ];

  final Dio _dio;

  /// Cada cuánto se pregunta por la cola de fal.ai, como el cliente oficial.
  final Duration _pollInterval;

  /// Cuántas veces, como mucho: 360 de medio segundo son los tres minutos de
  /// `kCloudFirstByteTimeout`.
  final int _maxPolls;

  @override
  IllustrationProvider get provider => IllustrationProvider.huggingFace;

  /// Prueba el token (`whoami`) y arma la lista curada con el proveedor que
  /// hoy dibuja cada modelo; los que ningún proveedor conocido dibuja no van.
  @override
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access) async {
    final key = access.key;
    if (key == null) {
      throw const ImageGenerationException(ImageFailure.noAccount);
    }
    await sendImageRequest<Object>(
      () => _dio.get<Object>('$_hub/api/whoami-v2', options: _options(key)),
      failureFrom: failureFrom,
    );
    final models = <ImageModelInfo>[];
    for (final model in kOpenImageModels) {
      final response = await sendImageRequest<Object>(
        () => _dio.get<Object>(
          '$_hub/api/models/${model.repoId}',
          queryParameters: const {'expand[]': 'inferenceProviderMapping'},
          options: _options(key),
        ),
        failureFrom: failureFrom,
      );
      final route = routeOf(response.data);
      if (route == null) continue;
      models.add(
        ImageModelInfo(id: model.repoId, displayName: model.name, route: route),
      );
    }
    return models;
  }

  /// El camino para dibujar con lo que dijo el Hub de un modelo
  /// («fal-ai|fal-ai/flux/schnell»), o `null` si ningún proveedor conocido lo
  /// dibuja ahora a partir de texto. El Hub lo da como mapa o como lista.
  static String? routeOf(Object? body) {
    final mapping = body is Map ? body['inferenceProviderMapping'] : null;
    final entries = <({String provider, Map<dynamic, dynamic> info})>[];
    if (mapping is Map) {
      for (final MapEntry(:key, :value) in mapping.entries) {
        if (key is String && value is Map) {
          entries.add((provider: key, info: value));
        }
      }
    } else if (mapping is List) {
      for (final value in mapping) {
        if (value is Map && value['provider'] is String) {
          entries.add((provider: value['provider'] as String, info: value));
        }
      }
    }
    for (final provider in supportedProviders) {
      for (final entry in entries) {
        if (entry.provider != provider) continue;
        final info = entry.info;
        final id = info['providerId'];
        if (info['status'] == 'live' &&
            info['task'] == 'text-to-image' &&
            id is String &&
            id.isNotEmpty) {
          return '$provider|$id';
        }
      }
    }
    return null;
  }

  /// FLUX.1 schnell si está (rápido y de licencia libre); si no, el
  /// primero de la lista curada.
  @override
  String? recommendedImageModel(List<ImageModelInfo> models) {
    if (models.isEmpty) return null;
    return models
            .where((m) => m.id == 'black-forest-labs/FLUX.1-schnell')
            .firstOrNull
            ?.id ??
        models.first.id;
  }

  @override
  Future<GeneratedImage> generate(
    ImageWireRequest request,
    ImageWireAccess access, {
    CancelToken? cancel,
  }) async {
    final key = access.key;
    if (key == null) {
      throw const ImageGenerationException(ImageFailure.noAccount);
    }
    final route = request.route;
    final bar = route?.indexOf('|') ?? -1;
    if (route == null || bar <= 0) {
      throw const ImageGenerationException(
        ImageFailure.modelNotFound,
        detail: 'Sin proveedor de inferencia',
      );
    }
    final inference = route.substring(0, bar);
    final providerId = route.substring(bar + 1);
    final pixels = pixelsOf(request.aspect, request.size);
    return switch (inference) {
      'hf-inference' => _hfInference(request, key, pixels, cancel),
      'nscale' => _nscale(request, providerId, key, pixels, cancel),
      'fal-ai' => _fal(request, providerId, key, pixels, cancel),
      'replicate' => _replicate(request, providerId, key, pixels, cancel),
      _ => throw ImageGenerationException(
        ImageFailure.modelNotFound,
        detail: 'Proveedor desconocido: $inference',
      ),
    };
  }

  Future<GeneratedImage> _hfInference(
    ImageWireRequest request,
    String key,
    ({int width, int height}) pixels,
    CancelToken? cancel,
  ) async {
    final response = await sendImageRequest<List<int>>(
      () => _dio.post<List<int>>(
        '$_router/hf-inference/models/${request.model}',
        data: {
          'inputs': request.prompt,
          'parameters': {'width': pixels.width, 'height': pixels.height},
        },
        cancelToken: cancel,
        options: _options(key, type: ResponseType.bytes),
      ),
      failureFrom: failureFrom,
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw const ImageGenerationException(ImageFailure.noImage);
    }
    final bytes = Uint8List.fromList(data);
    return GeneratedImage(
      bytes: bytes,
      mimeType: imageMimeOf(
        bytes,
        declared: response.headers.value(Headers.contentTypeHeader),
      ),
      model: request.model,
    );
  }

  Future<GeneratedImage> _nscale(
    ImageWireRequest request,
    String providerId,
    String key,
    ({int width, int height}) pixels,
    CancelToken? cancel,
  ) async {
    final response = await sendImageRequest<Object>(
      () => _dio.post<Object>(
        '$_router/nscale/v1/images/generations',
        data: {
          'model': providerId,
          'prompt': request.prompt,
          'response_format': 'b64_json',
          'size': '${pixels.width}x${pixels.height}',
        },
        cancelToken: cancel,
        options: _options(key),
      ),
      failureFrom: failureFrom,
    );
    return OpenAiImageWire.parse(response.data, model: request.model);
  }

  Future<GeneratedImage> _fal(
    ImageWireRequest request,
    String providerId,
    String key,
    ({int width, int height}) pixels,
    CancelToken? cancel,
  ) async {
    final queued = await sendImageRequest<Object>(
      () => _dio.post<Object>(
        '$_router/fal-ai/$providerId',
        queryParameters: const {'_subdomain': 'queue'},
        data: {
          'prompt': request.prompt,
          'image_size': {'width': pixels.width, 'height': pixels.height},
        },
        cancelToken: cancel,
        options: _options(key),
      ),
      failureFrom: failureFrom,
    );
    var result = queued.data;
    if (result is! Map || result['images'] == null) {
      // En la cola: como el cliente oficial, se consulta el estado en el
      // camino de `response_url` (vía el router) hasta que termina.
      final responseUrl = result is Map ? result['response_url'] : null;
      if (responseUrl is! String) {
        throw const ImageGenerationException(
          ImageFailure.unknown,
          detail: 'Sin response_url',
        );
      }
      final path = Uri.parse(responseUrl).path;
      var status = result is Map ? '${result['status'] ?? ''}' : '';
      var polls = 0;
      while (status != 'COMPLETED') {
        if (polls++ >= _maxPolls) {
          throw const ImageGenerationException(ImageFailure.timeout);
        }
        if (status == 'FAILED' || status == 'ERROR') {
          throw const ImageGenerationException(ImageFailure.unavailable);
        }
        await Future<void>.delayed(_pollInterval);
        if (cancel?.isCancelled ?? false) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(),
            reason: cancel!.cancelError,
          );
        }
        final polled = await sendImageRequest<Object>(
          () => _dio.get<Object>(
            '$_router/fal-ai$path/status',
            queryParameters: const {'_subdomain': 'queue'},
            cancelToken: cancel,
            options: _options(key),
          ),
          failureFrom: failureFrom,
        );
        final body = polled.data;
        status = body is Map ? '${body['status'] ?? ''}' : '';
      }
      final done = await sendImageRequest<Object>(
        () => _dio.get<Object>(
          '$_router/fal-ai$path',
          queryParameters: const {'_subdomain': 'queue'},
          cancelToken: cancel,
          options: _options(key),
        ),
        failureFrom: failureFrom,
      );
      result = done.data;
    }
    if (result is Map) {
      final nsfw = result['has_nsfw_concepts'];
      if (nsfw is List && nsfw.contains(true)) {
        throw const ImageGenerationException(
          ImageFailure.contentRefused,
          detail: 'has_nsfw_concepts',
        );
      }
    }
    final images = result is Map ? result['images'] : null;
    final first = images is List && images.isNotEmpty ? images.first : null;
    final url = first is Map ? first['url'] : null;
    if (url is! String || url.isEmpty) {
      throw const ImageGenerationException(ImageFailure.noImage);
    }
    final declared = first is Map ? first['content_type'] as String? : null;
    return _download(url, request.model, cancel, declared: declared);
  }

  Future<GeneratedImage> _replicate(
    ImageWireRequest request,
    String providerId,
    String key,
    ({int width, int height}) pixels,
    CancelToken? cancel,
  ) async {
    // Con versión fijada («dueño/modelo:versión») va a `/v1/predictions`.
    final colon = providerId.indexOf(':');
    final response = await sendImageRequest<Object>(
      () => _dio.post<Object>(
        colon < 0
            ? '$_router/replicate/v1/models/$providerId/predictions'
            : '$_router/replicate/v1/predictions',
        data: {
          if (colon >= 0) 'version': providerId.substring(colon + 1),
          'input': {
            'prompt': request.prompt,
            'width': pixels.width,
            'height': pixels.height,
          },
        },
        cancelToken: cancel,
        options: _options(key, extra: const {'Prefer': 'wait'}),
      ),
      failureFrom: failureFrom,
    );
    final body = response.data;
    final status = body is Map ? body['status'] : null;
    if (status == 'failed' || status == 'canceled') {
      final message = body is Map ? '${body['error'] ?? ''}' : '';
      throw ImageGenerationException(
        mentionsContentPolicy(message)
            ? ImageFailure.contentRefused
            : ImageFailure.unavailable,
        detail: message,
      );
    }
    final output = body is Map ? body['output'] : null;
    final url = output is String
        ? output
        : output is List && output.isNotEmpty && output.first is String
        ? output.first as String
        : null;
    if (url == null || url.isEmpty) {
      // `Prefer: wait` espera hasta un minuto; si no terminó, se venció.
      throw ImageGenerationException(
        status == 'succeeded' ? ImageFailure.noImage : ImageFailure.timeout,
        detail: '$status',
      );
    }
    return _download(url, request.model, cancel);
  }

  /// Baja la imagen terminada de la dirección que dio el proveedor, sin el
  /// token: es una dirección pública y temporal de su almacenamiento.
  Future<GeneratedImage> _download(
    String url,
    String model,
    CancelToken? cancel, {
    String? declared,
  }) async {
    final response = await sendImageRequest<List<int>>(
      () => _dio.get<List<int>>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          receiveTimeout: kCloudFirstByteTimeout,
        ),
      ),
      failureFrom: failureFrom,
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw const ImageGenerationException(ImageFailure.noImage);
    }
    final bytes = Uint8List.fromList(data);
    return GeneratedImage(
      bytes: bytes,
      mimeType: imageMimeOf(
        bytes,
        declared: declared ?? response.headers.value(Headers.contentTypeHeader),
      ),
      model: model,
    );
  }

  Options _options(
    String key, {
    ResponseType type = ResponseType.json,
    Map<String, String> extra = const {},
  }) => imageOptions({'authorization': 'Bearer $key', ...extra}, type: type);

  /// Traduce un error de Hugging Face o de su proveedor de inferencia: el
  /// estado manda (401 el token, 402 los créditos, 403 el permiso del
  /// token), y el mensaje afina un 400 de contenido.
  static ImageGenerationException failureFrom(
    int status,
    Object? body,
    Headers headers,
  ) {
    final raw = body is Map ? (body['error'] ?? body['detail']) : null;
    final message = raw is Map ? '${raw['message'] ?? raw}' : '${raw ?? ''}';
    ImageGenerationException fail(ImageFailure failure, {Duration? after}) =>
        ImageGenerationException(
          failure,
          detail: message.isEmpty ? '$status' : message,
          statusCode: status,
          retryAfter: after,
        );

    if (status == 401) return fail(ImageFailure.invalidKey);
    if (status == 402) return fail(ImageFailure.noCredits);
    if (status == 403) return fail(ImageFailure.forbidden);
    if (status == 404) return fail(ImageFailure.modelNotFound);
    if (status == 429) {
      return fail(ImageFailure.rateLimited, after: retryAfterOf(headers));
    }
    if (status == 408 || status == 504) return fail(ImageFailure.timeout);
    if (status >= 500) {
      return fail(ImageFailure.unavailable, after: retryAfterOf(headers));
    }
    if (status == 400 || status == 422) {
      return fail(
        mentionsContentPolicy(message)
            ? ImageFailure.contentRefused
            : ImageFailure.badRequest,
      );
    }
    return fail(ImageFailure.unknown);
  }
}
