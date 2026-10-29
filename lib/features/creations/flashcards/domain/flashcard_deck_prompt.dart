import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Las opciones de «Tarjetas didácticas» que lee el generador (F43, paso 8),
/// además de las de fábrica (`CreationOptionValues.count`, `.difficulty`,
/// `.images`) y el tema (`CreationOptionKeys.topic`).
abstract final class DeckOptionKeys {
  /// «Sumar a mi repaso» (`bool`, prendido de fábrica, decisión F).
  static const addToReview = 'addToReview';
}

/// Cuántas tarjetas se piden con «Menos», «Estándar» y «Más».
int deckCardCount(Map<String, Object?> options) =>
    switch (options[CreationOptionValues.count]) {
      CreationOptionValues.fewer => 10,
      CreationOptionValues.more => 30,
      _ => 18,
    };

/// Cuántas ilustraciones con IA, como mucho, lleva un mazo: una por tarjeta
/// costaría demasiado; el resto lleva el dibujo de la app.
int deckIllustrationCount(Map<String, Object?> options) =>
    switch (options[CreationOptionValues.count]) {
      CreationOptionValues.fewer => 4,
      CreationOptionValues.more => 8,
      _ => 6,
    };

/// Lo que escribe la IA por tarjeta: la pregunta, la respuesta de una a tres
/// oraciones, la pista y, con imágenes, el ícono y la descripción.
const kDeckTokensPerCard = 90;
const kDeckTokensPerIllustratedCard = 120;

/// Lo que se estima que escribe la IA con [options]: para «Uso de IA» y para
/// reservarle lugar en la ventana.
int deckExpectedOutputTokens(Map<String, Object?> options) =>
    deckCardCount(options) * deckTokensPerCard(options) + 200;

int deckTokensPerCard(Map<String, Object?> options) =>
    options[CreationOptionValues.images] == true
    ? kDeckTokensPerIllustratedCard
    : kDeckTokensPerCard;

/// Cómo se le dice la dificultad a la IA.
String deckDifficultyBrief(Object? difficulty) => switch (difficulty) {
  CreationOptionValues.easy =>
    'preguntas directas sobre las ideas principales, los nombres y las '
        'definiciones, para alguien que recién empieza',
  CreationOptionValues.hard =>
    'preguntas exigentes, que pidan relacionar, comparar, explicar causas y '
        'consecuencias y recordar detalles precisos',
  _ =>
    'preguntas que pidan entender las ideas y sus relaciones, no solo '
        'repetirlas',
};

/// La tarea de pedir [count] tarjetas (de una parte del material si [part]).
String deckTask({
  required int count,
  required Object? difficulty,
  required bool illustrated,
  required bool severalSources,
  required String topic,
  required bool part,
  required int illustrations,
}) {
  final buffer = StringBuffer(
    'armar un mazo de $count tarjetas de estudio —pregunta en el frente y '
    'respuesta en el dorso— con lo más importante '
    '${part ? 'de esta parte del material' : 'del material'}: '
    '${deckDifficultyBrief(difficulty)}. Cada frente es una sola pregunta '
    'clara que se entiende sin el material; cada dorso la contesta en una a '
    'tres oraciones, sin repetir la pregunta. Sin dos tarjetas que pregunten '
    'lo mismo',
  );
  if (topic.trim().isNotEmpty) {
    buffer.write('. Concentrate en el tema «${topic.trim()}»');
  }
  if (severalSources) {
    buffer.write(
      '. En "fuente" va el título exacto del documento del que sale cada '
      'tarjeta (está en «## título» arriba de cada uno)',
    );
  }
  if (illustrated) {
    buffer.write(
      '. En "icono" va una palabra en inglés que la represente (book, '
      'science, history, idea…). En "ilustracion", solo en las $illustrations '
      'tarjetas donde una imagen más ayude a recordar, una descripción breve '
      'EN INGLÉS de una ilustración sin letras; en las demás, vacío',
    );
  }
  return buffer.toString();
}

/// La forma del JSON del mazo, dicha para el modelo: breve, para que entre
/// con Gemma.
String deckSchema({required bool illustrated, required bool severalSources}) {
  final extra = [
    if (severalSources) '"fuente": "título del documento"',
    if (illustrated) '"icono": "book"',
    if (illustrated) '"ilustracion": "a descriptive English prompt, or empty"',
  ];
  final more = extra.isEmpty ? '' : ', ${extra.join(', ')}';
  return '{"titulo": "título corto del mazo", "tarjetas": [{"frente": '
      '"la pregunta", "dorso": "la respuesta", "pista": "una pista breve, u '
      'omitila"$more}]}';
}
