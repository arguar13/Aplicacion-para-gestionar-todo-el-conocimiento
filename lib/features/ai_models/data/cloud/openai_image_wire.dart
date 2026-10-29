import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/openai_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// [ImageWire] de OpenAI (F43), sobre la Image API (`POST
/// /v1/images/generations`): devuelve la imagen en base64
/// (`data[0].b64_json`) y lo gastado en `usage`, y no guarda nada. Verificado
/// el 2026-10-28 en
/// https://developers.openai.com/api/docs/guides/image-generation.
///
/// Los modelos «GPT Image» piden la organización verificada en la consola de
/// OpenAI: sin eso contesta 403 nombrando la verificación, y eso se dice con
/// esas palabras.
class OpenAiImageWire implements ImageWire {
  OpenAiImageWire({required Dio dio}) : _dio = dio;

  static const _base = 'https://api.openai.com/v1';

  final Dio _dio;

  @override
  IllustrationProvider get provider => IllustrationProvider.openAi;

  /// Los que dibujan por la Image API. Las versiones fijadas con fecha son la
  /// misma que el nombre sin fecha.
  static bool isImageModel(String id) =>
      RegExp('^(gpt-image-|chatgpt-image-|dall-e-)').hasMatch(id) &&
      !RegExp(r'-\d{4}-\d{2}-\d{2}$').hasMatch(id);

  @override
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access) async {
    final key = access.key;
    if (key == null) {
      throw const ImageGenerationException(ImageFailure.noAccount);
    }
    final response = await sendImageRequest<Object>(
      () => _dio.get<Object>('$_base/models', options: _options(key)),
      failureFrom: failureFrom,
    );
    final body = response.data;
    final data = body is Map
        ? (body['data'] as List?) ?? const []
        : const <Object?>[];
    return [
      for (final raw in data)
        if (raw is Map && raw['id'] is String)
          if (raw['id'] as String case final id when isImageModel(id))
            ImageModelInfo(id: id, displayName: displayNameOf(id)),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// «gpt-image-2.5-flare» → «GPT Image 2.5 Flare».
  static String displayNameOf(String id) {
    if (id.startsWith('dall-e-')) return 'DALL·E ${id.substring(7)}';
    final words = id.split('-');
    return [
      for (final word in words)
        if (word == 'gpt')
          'GPT'
        else if (word.isEmpty)
          word
        else
          word[0].toUpperCase() + word.substring(1),
    ].join(' ');
  }

  /// El rápido de la generación más nueva («Flare»); si no hay, el GPT Image
  /// más nuevo que no sea el chico; si no, el Mini; DALL·E al último.
  @override
  String? recommendedImageModel(List<ImageModelInfo> models) {
    if (models.isEmpty) return null;
    (int, int) version(String id) {
      final match = RegExp(r'^gpt-image-(\d+)(?:\.(\d+))?').firstMatch(id);
      if (match == null) return (-1, -1);
      return (
        int.parse(match.group(1)!),
        int.tryParse(match.group(2) ?? '') ?? 0,
      );
    }

    int compare((int, int) a, (int, int) b) =>
        a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);
    final gpt = models.where((m) => m.id.startsWith('gpt-image-')).toList()
      ..sort((a, b) => compare(version(b.id), version(a.id)));
    if (gpt.isNotEmpty) {
      final newest = version(gpt.first.id);
      final sameGeneration = gpt.where((m) => version(m.id) == newest);
      final flare = sameGeneration.where((m) => m.id.endsWith('-flare'));
      if (flare.isNotEmpty) return flare.first.id;
      final full = gpt.where((m) => !m.id.contains('mini'));
      return (full.isNotEmpty ? full.first : gpt.first).id;
    }
    return models.first.id;
  }

  /// El tamaño como lo acepta toda la familia: los tres de siempre. La lámina
  /// la recorta la app.
  static String sizeFor(IllustrationAspect aspect) => switch (aspect) {
    IllustrationAspect.square => '1024x1024',
    IllustrationAspect.tall => '1024x1536',
    IllustrationAspect.wide || IllustrationAspect.classic => '1536x1024',
  };

  /// La calidad: el tamaño de la app se traduce en cuánto detalle (y cuántos
  /// tokens) lleva la imagen.
  static String qualityFor(IllustrationSize size) => switch (size) {
    IllustrationSize.small => 'low',
    IllustrationSize.standard => 'medium',
    IllustrationSize.large => 'high',
  };

  /// El cuerpo del pedido, tal como se manda. DALL·E no entiende la calidad
  /// ni el formato de los GPT Image.
  static Map<String, Object> bodyOf(ImageWireRequest request) {
    final gpt = !request.model.startsWith('dall-e');
    return {
      'model': request.model,
      'prompt': request.prompt,
      'n': 1,
      'size': gpt ? sizeFor(request.aspect) : '1024x1024',
      if (gpt) 'quality': qualityFor(request.size),
      // JPEG: una ilustración no necesita transparencia y pesa la décima
      // parte que un PNG.
      if (gpt) 'output_format': 'jpeg',
      if (!gpt) 'response_format': 'b64_json',
    };
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
    final response = await sendImageRequest<Object>(
      () => _dio.post<Object>(
        '$_base/images/generations',
        data: bodyOf(request),
        cancelToken: cancel,
        options: _options(key),
      ),
      failureFrom: failureFrom,
    );
    return parse(response.data, model: request.model);
  }

  /// La imagen de una respuesta de la Image API (también el formato de
  /// imágenes de los proveedores compatibles, como el de Nscale en Hugging
  /// Face).
  static GeneratedImage parse(Object? body, {required String model}) {
    final data = body is Map ? body['data'] : null;
    final first = data is List && data.isNotEmpty ? data.first : null;
    final bytes = first is Map ? decodeImageBase64(first['b64_json']) : null;
    if (bytes == null) {
      throw const ImageGenerationException(
        ImageFailure.noImage,
        detail: 'Sin b64_json',
      );
    }
    final usage = body is Map ? body['usage'] : null;
    int? count(String field) {
      if (usage is! Map) return null;
      final value = usage[field];
      return value is int ? value : null;
    }

    return GeneratedImage(
      bytes: bytes,
      mimeType: imageMimeOf(bytes),
      model: model,
      inputTokens: count('input_tokens'),
      outputTokens: count('output_tokens'),
    );
  }

  Options _options(String key) =>
      imageOptions({'authorization': 'Bearer $key'});

  /// Traduce un error de la Image API: primero lo propio de las imágenes
  /// —la organización sin verificar, el rechazo por contenido, el saldo—, y
  /// lo demás como lo entiende `OpenAiWire.failureFrom`.
  static ImageGenerationException failureFrom(
    int status,
    Object? body,
    Headers headers,
  ) {
    final error = body is Map ? body['error'] : null;
    final code = error is Map ? '${error['code'] ?? ''}' : '';
    final type = error is Map ? '${error['type'] ?? ''}' : '';
    final message = error is Map ? '${error['message'] ?? ''}' : '';
    final lower = message.toLowerCase();
    ImageGenerationException fail(ImageFailure failure) =>
        ImageGenerationException(
          failure,
          detail: message.isEmpty ? (code.isEmpty ? type : code) : message,
          statusCode: status == 0 ? null : status,
        );

    // «Your organization must be verified to use the model `gpt-image-…`».
    if (lower.contains('organization') && lower.contains('verif')) {
      return fail(ImageFailure.orgUnverified);
    }
    if (code == 'moderation_blocked' ||
        code == 'content_policy_violation' ||
        type == 'image_generation_user_error' ||
        (status == 400 && mentionsContentPolicy(message))) {
      return fail(ImageFailure.contentRefused);
    }
    if (code == 'insufficient_quota' ||
        code == 'billing_hard_limit_reached' ||
        code == 'credit_balance_exhausted') {
      return fail(ImageFailure.noCredits);
    }
    return imageExceptionOf(OpenAiWire.failureFrom(status, body, headers));
  }
}
