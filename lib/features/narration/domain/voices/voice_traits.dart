/// Cómo es una voz de la biblioteca (F47, paso 3): de dónde sale, cómo suena
/// y para qué conviene. Es lo que muestra su tarjeta y lo que se filtra.
///
/// Cada rasgo es **opcional** en cada voz: solo se pone lo que dice una fuente
/// —el nombre del hablante en el modelo («hfc_female», el mapa «M»/«F» de
/// Sharvard), la tabla de Kokoro, la ficha de Piper— o lo que eligió quien
/// creó la voz (paso 4). Lo que no se sabe queda sin poner, y la voz no
/// aparece al filtrar por ese rasgo: decir que una voz es «cálida» sin haberla
/// oído sería inventarlo.
library;

/// De dónde sale una voz: lo que dice su tarjeta abajo del nombre.
enum VoiceOrigin {
  /// Una voz que trae el teléfono: la del motor del sistema.
  device,

  /// Una voz neuronal que se baja a pedido y lee sin conexión (Piper o
  /// Kokoro, sobre `sherpa_onnx`).
  offline,

  /// Una voz clonada con permiso de quien habla (paso 4).
  cloned,

  /// Una voz creada describiéndola (paso 4b).
  created,
}

enum VoiceGender { female, male }

/// Para qué conviene una voz: el ícono de su tarjeta y un filtro.
enum VoicePurpose { narrate, inform, learn, converse, relax }

/// El timbre: cómo suena, más allá de lo que dice.
enum VoiceTimbre { deep, clear, velvety, bright }

/// El estilo: el tono con que lee.
enum VoiceStyle { warm, calm, expressive, energetic, authoritative }

enum VoiceAge { young, adult, senior }

/// Qué tan bien suena una voz, según quien la publicó: la calidad de
/// entrenamiento de Piper (`high`, `medium`, `low`, `x_low`) o la nota de
/// Kokoro (de A a F). Es lo que ordena «Te puede interesar».
enum VoiceQuality {
  high,
  medium,
  low;

  /// Si alcanza para recomendarla: «Te puede interesar» muestra voces del
  /// idioma del documento **con buena calidad**.
  bool get isGood => this != VoiceQuality.low;
}
