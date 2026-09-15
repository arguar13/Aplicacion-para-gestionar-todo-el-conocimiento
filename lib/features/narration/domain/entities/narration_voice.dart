import 'package:freezed_annotation/freezed_annotation.dart';

part 'narration_voice.freezed.dart';

/// Una voz del motor de texto a voz del sistema: quién la lee y en qué
/// acento.
///
/// Solo [name] y [locale] —el resto de lo que puede traer una voz según la
/// plataforma (calidad, género, identificador de iOS...) no se usa acá: con
/// esos dos alcanza para elegirla y para volver a pedirla después, y son
/// los únicos dos campos que trae cualquier voz en cualquier plataforma
/// soportada.
@freezed
sealed class NarrationVoice with _$NarrationVoice {
  const factory NarrationVoice({
    required String name,

    /// El idioma y variante de la voz, como la entrega el sistema: `es-ES`,
    /// `en-US`, `en-GB`... Es lo que distingue un acento de otro cuando dos
    /// voces comparten idioma.
    required String locale,
  }) = _NarrationVoice;
}
