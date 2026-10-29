import 'package:dio/dio.dart';
import 'package:sinapsis/features/ai_models/data/cloud/gemini_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// [ImageWire] de Gemini (F43), sobre la API «Interactions»
/// (`POST /v1beta/interactions` con `response_format: {type: image}`): es la
/// única que documenta hoy la guía de imágenes de Google (verificado el
/// 2026-10-28 en https://ai.google.dev/gemini-api/docs/image-generation; la
/// referencia de `generateContent` ya no trae la salida de imagen).
///
/// La decisión de F32 —nada del contenido queda guardado fuera del teléfono—
/// se cumple con **`store: false`**: Interactions guarda por defecto (un día
/// en la capa gratuita, 55 en la paga) y con `store: false` no guarda nada.
/// Un pedido de imagen no necesita la conversación anterior, así que no se
/// pierde nada.
///
/// La lista de modelos es la misma de F32 (`GeminiWire.rawModels`), de la que
/// el formato de texto descarta los de imagen: acá se quedan solo esos.
class GeminiImageWire implements ImageWire {
  GeminiImageWire({
    required Dio dio,
    required GeminiWire text,
    DateTime Function()? clock,
  }) : _dio = dio,
       _text = text,
       _clock = clock ?? DateTime.now;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  final Dio _dio;
  final GeminiWire _text;
  final DateTime Function() _clock;

  @override
  IllustrationProvider get provider => IllustrationProvider.gemini;

  /// Los que dibujan: los Gemini con «image» en el código y los «Nano
  /// Banana». Fuera los de voz, tiempo real y vectores, y los Imagen, que van
  /// por otra API (`:predict`) que la guía actual ya no documenta.
  static bool isImageModel(String id) =>
      id.startsWith('gemini-') &&
      (id.contains('image') || id.contains('nano-banana')) &&
      !RegExp('tts|live|audio|embedding').hasMatch(id);

  @override
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access) async {
    final key = access.key;
    if (key == null) {
      throw const ImageGenerationException(ImageFailure.noAccount);
    }
    final List<Map<dynamic, dynamic>> raw;
    try {
      raw = await _text.rawModels(key);
    } on CloudModelException catch (error) {
      throw refine(error, error.statusCode ?? 0, null);
    }
    final models = <ImageModelInfo>[];
    for (final model in raw) {
      final name = model['name'];
      if (name is! String || !name.startsWith('models/')) continue;
      final id = name.substring('models/'.length);
      if (!isImageModel(id)) continue;
      final display = model['displayName'];
      models.add(
        ImageModelInfo(
          id: id,
          displayName: display is String && display.isNotEmpty ? display : id,
        ),
      );
    }
    return models..sort((a, b) => a.id.compareTo(b.id));
  }

  /// El que Google recomienda para empezar (Nano Banana 2.1, US$ 0,034 la
  /// imagen 1K); si no está, el Lite (el mismo precio, solo 1K); si no, el
  /// 3.1 Flash Image; si no, el Pro; el 2.5, que Google va a apagar, al
  /// último. Los estables antes que los de prueba.
  @override
  String? recommendedImageModel(List<ImageModelInfo> models) {
    if (models.isEmpty) return null;
    const order = [
      'gemini-nano-banana-2.1',
      'gemini-3.1-flash-lite-image',
      'gemini-3.1-flash-image',
      'gemini-3-pro-image',
    ];
    for (final base in order) {
      final stable = models.where((m) => m.id == base).firstOrNull;
      if (stable != null) return stable.id;
      final preview = models
          .where((m) => m.id.startsWith('$base-'))
          .firstOrNull;
      if (preview != null) return preview.id;
    }
    final fresh = models.where((m) => !m.id.startsWith('gemini-2.')).toList();
    return (fresh.isNotEmpty ? fresh : models).last.id;
  }

  /// El tamaño como lo pide Gemini: «512» solo lo hace 3.1 Flash Image, el
  /// Lite solo «1K»; los demás, «1K» o «2K».
  static String imageSizeFor(String model, IllustrationSize size) {
    if (model.contains('flash-lite-image')) return '1K';
    return switch (size) {
      IllustrationSize.small =>
        model.startsWith('gemini-3.1-flash-image') ? '512' : '1K',
      IllustrationSize.standard => '1K',
      IllustrationSize.large => '2K',
    };
  }

  /// El cuerpo del pedido, tal como se manda.
  static Map<String, Object> bodyOf(ImageWireRequest request) => {
    'model': request.model,
    'input': [
      {'type': 'text', 'text': request.prompt},
    ],
    // Que no quede nada guardado en Google (decisión de F32).
    'store': false,
    'response_format': {
      'type': 'image',
      'mime_type': 'image/jpeg',
      'aspect_ratio': request.aspect.ratio,
      'image_size': imageSizeFor(request.model, request.size),
    },
  };

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
        '$_base/interactions',
        data: bodyOf(request),
        cancelToken: cancel,
        options: imageOptions({'x-goog-api-key': key}),
      ),
      failureFrom: (status, body, headers) => refine(
        GeminiWire.failureFrom(status, body, now: _clock(), headers: headers),
        status,
        body,
      ),
    );
    return parse(response.data, model: request.model);
  }

  /// La imagen de una interacción terminada: el primer bloque `image` de los
  /// pasos `model_output` (o de `outputs`, como lo devolvía antes).
  static GeneratedImage parse(Object? body, {required String model}) {
    if (body is! Map) {
      throw const ImageGenerationException(
        ImageFailure.unknown,
        detail: 'Respuesta sin JSON',
      );
    }
    final status = body['status'];
    final error = body['error'];
    if (status == 'failed' || error is Map) {
      final message = error is Map ? '${error['message'] ?? ''}' : '';
      throw ImageGenerationException(
        _failureOfMessage(message) ?? ImageFailure.unknown,
        detail: message.isEmpty ? '$status' : message,
      );
    }
    final blocks = <Map<dynamic, dynamic>>[];
    final steps = body['steps'];
    if (steps is List) {
      for (final step in steps) {
        if (step is! Map || step['type'] != 'model_output') continue;
        final content = step['content'];
        if (content is List) {
          blocks.addAll(content.whereType<Map<dynamic, dynamic>>());
        }
      }
    }
    final outputs = body['outputs'];
    if (outputs is List) {
      blocks.addAll(outputs.whereType<Map<dynamic, dynamic>>());
    }

    var said = '';
    for (final block in blocks) {
      if (block['type'] == 'image') {
        final bytes = decodeImageBase64(block['data']);
        if (bytes == null) continue;
        final usage = body['usage'];
        int? count(String field) {
          if (usage is! Map) return null;
          final value = usage[field];
          return value is int ? value : null;
        }

        return GeneratedImage(
          bytes: bytes,
          mimeType: imageMimeOf(bytes, declared: block['mime_type'] as String?),
          model: model,
          inputTokens: count('total_input_tokens'),
          outputTokens: count('total_output_tokens'),
        );
      }
      if (block['type'] == 'text' && block['text'] is String) {
        said += block['text'] as String;
      }
    }
    // Terminó sin imagen: si explicó algo, es que no quiso dibujarlo.
    throw ImageGenerationException(
      said.trim().isEmpty ? ImageFailure.noImage : ImageFailure.contentRefused,
      detail: said.trim().isEmpty ? '$status' : said.trim(),
    );
  }

  /// Lo propio de las imágenes que un mensaje de Google dice con palabras.
  static ImageFailure? _failureOfMessage(String message) {
    final lower = message.toLowerCase();
    // «Imagen API is only accessible to billed users», «… billing …», o el
    // 429 de la capa gratuita con «limit: 0» en un modelo que no tiene.
    if (lower.contains('billing') ||
        lower.contains('billed') ||
        lower.contains('paid tier') ||
        RegExp(r'limit:\s*0\b').hasMatch(lower)) {
      return ImageFailure.noBilling;
    }
    if (mentionsContentPolicy(message)) return ImageFailure.contentRefused;
    return null;
  }

  /// [error] (lo que `GeminiWire.failureFrom` entendió) afinado para las
  /// imágenes con lo que dice el mensaje: la falta de facturación llega como
  /// un 429 de la capa gratuita con tope cero, o como un 400 o un 403 que
  /// nombra la facturación, y un rechazo por contenido, como un 400 de
  /// seguridad.
  static ImageGenerationException refine(
    CloudModelException error,
    int status,
    Object? body,
  ) {
    final raw = body is Map ? body['error'] : null;
    final message = raw is Map ? '${raw['message'] ?? ''}' : error.detail ?? '';
    final specific = _failureOfMessage(message);
    return ImageGenerationException(
      specific ?? imageFailureOfCloud(error.failure),
      detail: error.detail,
      statusCode: error.statusCode ?? (status == 0 ? null : status),
      retryAfter: specific == null ? error.retryAfter : null,
    );
  }
}
