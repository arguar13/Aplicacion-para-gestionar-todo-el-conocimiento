/// Quién escribe las respuestas de la IA (F32): Gemma en el teléfono o un
/// modelo en la nube. Uno solo a la vez hace todo lo que la app le pide a un
/// modelo de lenguaje.
enum AiProvider {
  /// Gemini, de Google, con claves de Google AI Studio. Por defecto: tiene
  /// una capa gratuita.
  gemini,

  /// Gemma corriendo en el teléfono, sin internet (lo de siempre).
  gemma,

  /// Los modelos de OpenAI, con créditos pagos.
  openAi,

  /// Los modelos de Claude, de Anthropic, con créditos pagos.
  anthropic;

  /// El proveedor que la app usa si nunca se eligió otro.
  static const fallback = AiProvider.gemini;

  /// Si las respuestas se escriben fuera del teléfono: el texto de cada
  /// pedido viaja al proveedor (el contenido sigue guardado solo acá).
  bool get isCloud => this != AiProvider.gemma;

  /// Si usarlo pide una clave de API.
  bool get needsKey => isCloud;

  /// Si tiene capa gratuita: con los demás, cada pedido se paga.
  bool get hasFreeTier => this == AiProvider.gemini || this == AiProvider.gemma;

  /// Dónde se crea una clave nueva, para el botón «Conseguir una clave».
  String? get keysUrl => switch (this) {
    AiProvider.gemini => 'https://aistudio.google.com/apikey',
    AiProvider.openAi => 'https://platform.openai.com/api-keys',
    AiProvider.anthropic => 'https://console.anthropic.com/settings/keys',
    AiProvider.gemma => null,
  };

  /// Cómo se guarda en las preferencias. Estable: cambiar el nombre del enum
  /// no cambia lo guardado.
  String get storageKey => switch (this) {
    AiProvider.gemini => 'gemini',
    AiProvider.gemma => 'gemma',
    AiProvider.openAi => 'openai',
    AiProvider.anthropic => 'anthropic',
  };

  /// El proveedor de [key], o `null` si no es ninguno conocido (lo guardó una
  /// versión futura, o se tocó a mano).
  static AiProvider? fromStorageKey(String? key) {
    for (final provider in values) {
      if (provider.storageKey == key) return provider;
    }
    return null;
  }
}
