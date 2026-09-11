import 'package:freezed_annotation/freezed_annotation.dart';

part 'highlight.freezed.dart';

/// Un fragmento marcado dentro de un texto, con una nota opcional.
///
/// Es lo que hacía Glasp, pero adentro y sin cuenta: subrayar lo que importa
/// de un artículo o de una transcripción, y anotar por qué.
@freezed
sealed class Highlight with _$Highlight {
  const factory Highlight({
    required String id,

    /// Apunta a una rendition y no al elemento: el mismo contenido puede
    /// existir como transcripción y como artículo, y un subrayado pertenece a
    /// un texto concreto, con sus posiciones concretas.
    required String renditionId,
    required int startOffset,
    required int endOffset,

    /// El texto subrayado, copiado.
    ///
    /// Es deliberadamente redundante con las posiciones: si la rendition se
    /// regenera —una transcripción rehecha con un modelo mejor— los índices
    /// dejan de apuntar a donde apuntaban, y sin esta copia el subrayado se
    /// perdería. Guardarlo cuesta unos bytes; perderlo cuesta el trabajo de
    /// haber leído.
    required String excerpt,
    required DateTime createdAt,
    String? note,
  }) = _Highlight;
}
