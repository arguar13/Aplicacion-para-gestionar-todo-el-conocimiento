import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_source.freezed.dart';

/// Un fragmento de la bóveda que respalda una respuesta del chat: de qué
/// elemento sale y qué parte de su contenido es la relevante.
///
/// Existe para que ninguna respuesta del chat se muestre sin decir de dónde
/// salió —el mismo principio de procedencia (principio 2 en
/// docs/arquitectura.md) que ya rige cada elemento guardado, aplicado ahora
/// a lo que el chat contesta—.
@freezed
sealed class ChatSource with _$ChatSource {
  const factory ChatSource({
    required String itemId,
    required String itemTitle,
    required String excerpt,
  }) = _ChatSource;
}

/// Codifica una lista de fuentes para guardarlas en una sola columna de
/// texto — mismo criterio que `encodeContentBlocks` para los bloques de una
/// nota: una lista chica, propia de un solo mensaje, que nunca se consulta
/// por su cuenta.
String encodeChatSources(List<ChatSource> sources) {
  return jsonEncode(sources.map(_sourceToJson).toList());
}

List<ChatSource> decodeChatSources(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json) as List<dynamic>;
  return decoded
      .map((raw) => _sourceFromJson(raw as Map<String, dynamic>))
      .whereType<ChatSource>()
      .toList();
}

Map<String, dynamic> _sourceToJson(ChatSource source) => {
  'itemId': source.itemId,
  'itemTitle': source.itemTitle,
  'excerpt': source.excerpt,
};

ChatSource? _sourceFromJson(Map<String, dynamic> json) {
  final itemId = json['itemId'] as String?;
  final itemTitle = json['itemTitle'] as String?;
  final excerpt = json['excerpt'] as String?;
  if (itemId == null || itemTitle == null || excerpt == null) return null;

  return ChatSource(itemId: itemId, itemTitle: itemTitle, excerpt: excerpt);
}
