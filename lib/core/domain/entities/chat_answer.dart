import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';

part 'chat_answer.freezed.dart';

/// La respuesta a una pregunta hecha a la bóveda.
///
/// [text] es `null` en dos situaciones bien distintas, y la pantalla las
/// distingue: sin ninguna fuente encontrada, no hay nada que contestar; con
/// fuentes pero sin el modelo de lenguaje descargado todavía, se listan las
/// fuentes igual —sin redactar una respuesta— en vez de forzar la descarga
/// de varios GB antes de que la búsqueda misma sirva de algo.
@freezed
sealed class ChatAnswer with _$ChatAnswer {
  const factory ChatAnswer({
    String? text,
    @Default(<ChatSource>[]) List<ChatSource> sources,
  }) = _ChatAnswer;
}
