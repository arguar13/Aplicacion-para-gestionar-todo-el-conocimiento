import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';

/// Cómo se le habla a un proveedor en la nube (F32): el formato de sus
/// pedidos y respuestas, nada más. A qué cuenta se le pide, qué hacer cuando
/// se agota la cuota y cómo se cuenta lo gastado vive arriba, en
/// `CloudModelBackend`, una sola vez para todos los proveedores.
///
/// Cada formato traduce los errores de su proveedor a `CloudModelException`,
/// para que lo de arriba decida igual con Gemini, OpenAI o Claude.
abstract interface class CloudWire {
  AiProvider get provider;

  /// Los modelos de texto que [key] puede usar, como los lista el proveedor.
  Future<List<CloudModelInfo>> listModels(String key);

  /// El que la app recomienda de [models] si la persona no eligió otro: el más
  /// nuevo de los rápidos y capaces. `null` si [models] está vacía.
  String? recommendedModel(List<CloudModelInfo> models);

  /// La respuesta a [request] a medida que se escribe: cada evento trae el
  /// texto nuevo; el último, además, lo que el proveedor contó de tokens.
  /// Cortar [cancel] la termina con lo escrito hasta ahí.
  Stream<CloudDelta> stream(
    CloudRequest request, {
    required String key,
    CancelToken? cancel,
  });
}

/// Quién dice un mensaje de la charla.
enum CloudRole { user, model }

/// Un mensaje de lo que se le manda: lo conversado antes y el pedido nuevo.
@immutable
class CloudMessage {
  const CloudMessage({
    required this.role,
    required this.text,
    this.images = const [],
  });

  final CloudRole role;
  final String text;

  /// Fotos adjuntas (solo en mensajes de la persona).
  final List<Uint8List> images;
}

/// Un pedido completo: el modelo, la instrucción, lo conversado y el tope.
@immutable
class CloudRequest {
  const CloudRequest({
    required this.model,
    required this.instruction,
    required this.messages,
    required this.maxOutputTokens,
    this.thinkMore = false,
  });

  final String model;
  final String instruction;
  final List<CloudMessage> messages;

  /// Lo que puede escribir la respuesta, como lo pide la tarea (sin contar lo
  /// que el modelo «piensa» antes: cada formato le suma su margen).
  final int maxOutputTokens;

  /// Si la persona prendió «Pensar más» en el chat (F42): el modelo piensa lo
  /// que haga falta en vez de lo menos posible. Solo lo traduce un
  /// formato cuyo modelo tiene la perilla (`thinkMoreSupport`); en los demás
  /// no cambia nada del pedido.
  final bool thinkMore;
}

/// El margen para lo que piensa un modelo con «Pensar más» (F42): lo pensado
/// cuenta dentro del tope de la respuesta, y pensando a fondo un modelo usa
/// varios miles de tokens antes de escribir la primera palabra. Con el margen
/// de siempre (2048) la respuesta llegaría cortada o vacía.
const kCloudThinkMoreHeadroomTokens = 16384;

/// Un pedazo de la respuesta.
@immutable
class CloudDelta {
  const CloudDelta({
    this.text = '',
    this.inputTokens,
    this.outputTokens,
    this.truncated = false,
    this.restart = false,
  });

  /// El texto nuevo (vacío en el evento que solo trae la cuenta).
  final String text;

  /// Tokens del pedido, si el proveedor los contó en este evento.
  final int? inputTokens;

  /// Tokens de la respuesta (con lo pensado), si los contó en este evento.
  final int? outputTokens;

  /// La respuesta se cortó por el tope de largo.
  final bool truncated;

  /// Lo escrito hasta acá se descarta y la respuesta vuelve a empezar (F39):
  /// se cortó a mitad y se reintentó entera con la misma cuenta. Quien junta
  /// el texto lo vacía; el evento no trae texto.
  final bool restart;
}

/// El tipo de una foto, por sus primeros bytes. JPEG si no se reconoce: es lo
/// que la app adjunta casi siempre.
String imageMimeType(Uint8List bytes) {
  bool starts(List<int> magic) =>
      bytes.length >= magic.length &&
      Iterable<int>.generate(magic.length).every((i) => bytes[i] == magic[i]);
  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (bytes.length >= 12 &&
      starts([0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
