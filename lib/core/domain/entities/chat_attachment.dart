import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_attachment.freezed.dart';

/// Qué se hace con un adjunto del chat según su tipo.
///
/// Una imagen se le manda al modelo tal cual —cuando el modelo activo
/// entiende imágenes, ver `GemmaChatModel`—, para que describa o responda
/// sobre lo que muestra. Un documento no: un PDF o un DOCX no es algo que
/// un modelo de lenguaje "mire", así que en vez de mandarlo entero se
/// extrae su texto con los mismos `DocumentParser` que ya usa la
/// biblioteca (ver `document_transformer.dart`) y ese texto se suma como
/// contexto extra de la pregunta — la misma idea que una fuente de la
/// bóveda, solo que ad hoc y sin guardarla ahí.
enum ChatAttachmentKind { image, document }

/// Un archivo que se sumó a un mensaje del chat: una foto o un documento
/// elegidos con el selector del sistema, igual que al capturar algo para
/// la bóveda.
///
/// Los bytes en sí no viven acá — ver [relativePath] — para que un mensaje
/// con una foto de varios megas no infle cada consulta a la base de datos
/// que solo necesita saber "qué se adjuntó", no "con qué bytes exactos".
@freezed
sealed class ChatAttachment with _$ChatAttachment {
  const factory ChatAttachment({
    required String name,
    required ChatAttachmentKind kind,

    /// Dónde quedó guardado, relativo al `FileStore` — el mismo almacén que
    /// ya usa cualquier archivo original de la bóveda.
    required String relativePath,

    /// Para un documento: el texto que se le pudo sacar, si el formato es
    /// alguno de los que esta app sabe leer. `null` para una imagen, o para
    /// un documento en un formato sin lector — un `.zip`, por ejemplo—: ahí
    /// el archivo queda adjunto igual, guardado, pero sin nada que sumar a
    /// la conversación.
    String? extractedText,
  }) = _ChatAttachment;
}

/// JSON a mano y no `@JsonSerializable`, mismo motivo que
/// `encodeContentBlocks`: es la única entidad de este tamaño que hace falta
/// guardar como texto en una columna, y sumar el paquete entero para esto
/// sería más superficie nueva que estas pocas líneas.
String encodeChatAttachments(List<ChatAttachment> attachments) {
  return jsonEncode(attachments.map(_attachmentToJson).toList());
}

/// El inverso de [encodeChatAttachments]. Un adjunto de un tipo que esta
/// versión no reconoce se descarta en silencio en vez de romper el mensaje
/// entero — degradar antes que fallar, igual que el resto de la app.
List<ChatAttachment> decodeChatAttachments(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json) as List<dynamic>;
  return decoded
      .map((raw) => _attachmentFromJson(raw as Map<String, dynamic>))
      .whereType<ChatAttachment>()
      .toList();
}

Map<String, dynamic> _attachmentToJson(ChatAttachment attachment) => {
  'name': attachment.name,
  'kind': attachment.kind.name,
  'relativePath': attachment.relativePath,
  if (attachment.extractedText != null)
    'extractedText': attachment.extractedText,
};

ChatAttachment? _attachmentFromJson(Map<String, dynamic> json) {
  final kindName = json['kind'] as String?;
  final kind = ChatAttachmentKind.values
      .where((k) => k.name == kindName)
      .firstOrNull;
  final name = json['name'] as String?;
  final relativePath = json['relativePath'] as String?;
  if (kind == null || name == null || relativePath == null) return null;

  return ChatAttachment(
    name: name,
    kind: kind,
    relativePath: relativePath,
    extractedText: json['extractedText'] as String?,
  );
}
