/// Qué tan segura dice estar la IA de algo que propone (F27): lo que el modelo
/// de lenguaje contesta cuando se le pide «alta», «media» o «baja».
///
/// Es lo que dice el modelo, no una probabilidad medida: un modelo chico se
/// equivoca con aplomo. Por eso nunca decide solo qué se aplica; se combina
/// con algo medido —el parecido de los embeddings, que la cita esté en el
/// texto, que el valor ya exista en el vocabulario—.
enum AiCertainty {
  high,
  medium,
  low;

  /// La palabra que escribió el modelo, sin distinguir mayúsculas; `null` si
  /// no es ninguna de las tres.
  static AiCertainty? parse(String token) =>
      switch (token.trim().toLowerCase()) {
        'alta' => AiCertainty.high,
        'media' => AiCertainty.medium,
        'baja' => AiCertainty.low,
        _ => null,
      };
}
