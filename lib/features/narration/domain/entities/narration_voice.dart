import 'package:freezed_annotation/freezed_annotation.dart';

part 'narration_voice.freezed.dart';

/// Qué motor lee con una voz (F47, paso 3).
enum NarrationEngine {
  /// El motor de texto a voz del sistema: las voces que trae el teléfono.
  system,

  /// El motor sin conexión de la app (`sherpa_onnx`): una voz neuronal de
  /// Piper o de Kokoro, bajada a pedido.
  offline,
}

/// Una voz con la que se lee en voz alta: quién la lee, en qué acento y con
/// qué motor.
///
/// De una voz del sistema, solo [name] y [locale] —el resto de lo que puede
/// traer según la plataforma (calidad, género, identificador de iOS...) no se
/// usa acá: con esos dos alcanza para elegirla y para volver a pedirla
/// después, y son los únicos dos campos que trae cualquier voz en cualquier
/// plataforma soportada—. De una voz sin conexión, [name] es su identificador
/// en el catálogo (`OfflineVoice.id`), que es lo que el motor necesita para
/// encontrarla.
@freezed
sealed class NarrationVoice with _$NarrationVoice {
  const factory NarrationVoice({
    required String name,

    /// El idioma y variante de la voz: `es-ES`, `en-US`, `en-GB`... Es lo que
    /// distingue un acento de otro cuando dos voces comparten idioma, y el
    /// idioma que lee (decisión L).
    required String locale,

    @Default(NarrationEngine.system) NarrationEngine engine,
  }) = _NarrationVoice;
}
