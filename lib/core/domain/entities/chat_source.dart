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
