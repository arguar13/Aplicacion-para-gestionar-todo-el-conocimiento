import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Quién dibuja las ilustraciones con IA (F43, decisión H): no es quien
/// escribe. Claude y Gemma no generan imágenes; Gemini y OpenAI sí, con las
/// mismas cuentas de F32; Hugging Face da los modelos de código abierto en la
/// nube; y un modelo chico en el teléfono («Exigente»), si se descargó.
enum IllustrationProvider {
  /// Los modelos de imagen de Gemini («Nano Banana»), con una cuenta de F32.
  /// Solo con facturación activa: la capa gratuita no los incluye.
  gemini,

  /// Los modelos «GPT Image» de OpenAI, con una cuenta de F32. Piden la
  /// organización verificada en la consola de OpenAI.
  openAi,

  /// Los modelos abiertos (FLUX, Z-Image, Stable Diffusion…) por los
  /// proveedores de inferencia de Hugging Face, con un token propio.
  huggingFace,

  /// Un modelo de imágenes chico que corre en el teléfono («Exigente»): sin
  /// clave, sin costo en dinero y sin cuota, pero lento y exigente con la
  /// batería. Lo da un `OnDeviceImageEngine`, si hay uno registrado.
  onDevice;

  /// Si usa una cuenta de las de escribir (F32) en vez de una propia.
  bool get usesTextAccount =>
      this == IllustrationProvider.gemini ||
      this == IllustrationProvider.openAi;

  /// Si corre en el teléfono: no cuesta dinero ni tiene cuota, cuesta tiempo.
  bool get isOnDevice => this == IllustrationProvider.onDevice;

  /// El proveedor de texto cuyas cuentas usa, o `null` si no usa una de F32.
  AiProvider? get textProvider => switch (this) {
    IllustrationProvider.gemini => AiProvider.gemini,
    IllustrationProvider.openAi => AiProvider.openAi,
    IllustrationProvider.huggingFace || IllustrationProvider.onDevice => null,
  };

  /// Quién dibuja con las cuentas de [provider], o `null` si [provider] no
  /// dibuja (Claude, Gemma).
  static IllustrationProvider? ofText(AiProvider provider) =>
      switch (provider) {
        AiProvider.gemini => IllustrationProvider.gemini,
        AiProvider.openAi => IllustrationProvider.openAi,
        AiProvider.anthropic || AiProvider.gemma => null,
      };

  /// Si pide una clave o un token.
  bool get needsKey => this != IllustrationProvider.onDevice;

  /// Dónde se crea una clave nueva. El token de Hugging Face, de grano fino
  /// y con el permiso de llamar a los proveedores de inferencia, como dice su
  /// documentación.
  String? get keysUrl => switch (this) {
    IllustrationProvider.gemini => AiProvider.gemini.keysUrl,
    IllustrationProvider.openAi => AiProvider.openAi.keysUrl,
    IllustrationProvider.huggingFace =>
      'https://huggingface.co/settings/tokens/new'
          '?ownUserPermissions=inference.serverless.write'
          '&tokenType=fineGrained',
    IllustrationProvider.onDevice => null,
  };

  /// Cómo se guarda en las preferencias. Estable.
  String get storageKey => switch (this) {
    IllustrationProvider.gemini => 'gemini',
    IllustrationProvider.openAi => 'openai',
    IllustrationProvider.huggingFace => 'huggingface',
    IllustrationProvider.onDevice => 'on-device',
  };

  static IllustrationProvider? fromStorageKey(String? key) {
    for (final provider in values) {
      if (provider.storageKey == key) return provider;
    }
    return null;
  }
}
