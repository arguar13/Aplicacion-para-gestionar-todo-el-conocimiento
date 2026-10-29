import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_prompt.dart'
    show deckDifficultyBrief;
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';

/// Cuántas preguntas se piden con «Menos», «Estándar» y «Más».
int quizQuestionCount(Map<String, Object?> options) =>
    switch (options[CreationOptionValues.count]) {
      CreationOptionValues.fewer => 6,
      CreationOptionValues.more => 20,
      _ => 12,
    };

/// Cuántas ilustraciones con IA, como mucho, lleva un cuestionario.
int quizIllustrationCount(Map<String, Object?> options) =>
    switch (options[CreationOptionValues.count]) {
      CreationOptionValues.fewer => 3,
      CreationOptionValues.more => 7,
      _ => 5,
    };

/// Los tipos de pregunta elegidos, en el orden de la hoja; ninguno válido,
/// opción única.
List<QuizQuestionType> quizQuestionTypes(Map<String, Object?> options) {
  final raw = options[CreationOptionValues.questionTypes];
  final chosen = raw is List ? raw.whereType<String>().toSet() : <String>{};
  final types = [
    for (final type in QuizQuestionType.values)
      if (chosen.contains(type.storageKey)) type,
  ];
  return types.isEmpty ? const [QuizQuestionType.single] : types;
}

/// Lo que escribe la IA por pregunta: con opciones, la explicación de cada
/// una de las cuatro; escritas, la respuesta y su explicación.
int quizTokensPerQuestion(Map<String, Object?> options) {
  final types = quizQuestionTypes(options);
  final withOptions = types.where((t) => t.hasOptions).length;
  final perType =
      (withOptions * 260 + (types.length - withOptions) * 140) ~/ types.length;
  return perType + (options[CreationOptionValues.images] == true ? 30 : 0);
}

/// Lo que se estima que escribe la IA con [options].
int quizExpectedOutputTokens(Map<String, Object?> options) =>
    quizQuestionCount(options) * quizTokensPerQuestion(options) + 200;

/// Cómo se le dice cada tipo a la IA, con el nombre que va en "tipo".
String _typeBrief(QuizQuestionType type) => switch (type) {
  QuizQuestionType.single =>
    '"opcion_unica": cuatro opciones y UNA sola correcta; las incorrectas, '
        'creíbles y del mismo material',
  QuizQuestionType.multiple =>
    '"seleccion_multiple": cuatro opciones y DOS o TRES correctas',
  QuizQuestionType.fillBlank =>
    '"completar": una oración del material con $kQuizBlank en lugar de una o '
        'pocas palabras clave; en "respuesta" van esas palabras exactas y en '
        '"alternativas" otras formas que también valen',
  QuizQuestionType.shortAnswer =>
    '"respuesta_breve": una pregunta que se contesta en una o dos oraciones; '
        'en "respuesta" va la respuesta esperada',
};

/// La tarea de pedir [count] preguntas.
String quizTask({
  required int count,
  required List<QuizQuestionType> types,
  required Object? difficulty,
  required bool illustrated,
  required bool severalSources,
  required String topic,
  required bool part,
  required int illustrations,
}) {
  final buffer =
      StringBuffer(
          'armar un cuestionario de $count preguntas para probar lo aprendido '
          '${part ? 'en esta parte del material' : 'en el material'}: '
          '${deckDifficultyBrief(difficulty)}. ',
        )
        ..write(
          types.length == 1
              ? 'Todas de tipo ${_typeBrief(types.single)}'
              : 'Mezclá, repartidas parejo, estos tipos: '
                    '${types.map(_typeBrief).join('; ')}',
        )
        ..write(
          '. En las de opciones, cada opción lleva su "explicacion": por qué '
          'es correcta o por qué no. Cada pregunta lleva además su '
          '"explicacion" general. Sin dos preguntas sobre lo mismo',
        );
  if (topic.trim().isNotEmpty) {
    buffer.write('. Concentrate en el tema «${topic.trim()}»');
  }
  if (severalSources) {
    buffer.write(
      '. En "fuente" va el título exacto del documento del que sale cada '
      'pregunta (está en «## título» arriba de cada uno)',
    );
  }
  if (illustrated) {
    buffer.write(
      '. En "icono" va una palabra en inglés que la represente. En '
      '"ilustracion", solo en las $illustrations preguntas donde una imagen '
      'ayude, una descripción breve EN INGLÉS de una ilustración sin letras '
      'que no revele la respuesta; en las demás, vacío',
    );
  }
  return buffer.toString();
}

/// La forma del JSON del cuestionario, breve.
String quizSchema({
  required List<QuizQuestionType> types,
  required bool illustrated,
  required bool severalSources,
}) {
  final withOptions = types.any((t) => t.hasOptions);
  final typed = types.any((t) => t.isTyped);
  final fields = [
    '"tipo": "${types.map(_typeName).join('|')}"',
    '"pregunta": "…"',
    if (withOptions)
      '"opciones": [{"texto": "…", "correcta": true, "explicacion": "…"}]',
    if (typed) '"respuesta": "…"',
    if (types.contains(QuizQuestionType.fillBlank)) '"alternativas": ["…"]',
    '"explicacion": "…"',
    if (severalSources) '"fuente": "título del documento"',
    if (illustrated) '"icono": "science"',
    if (illustrated) '"ilustracion": "English prompt, or empty"',
  ];
  return '{"titulo": "título corto", "preguntas": [{${fields.join(', ')}}]}';
}

String _typeName(QuizQuestionType type) => switch (type) {
  QuizQuestionType.single => 'opcion_unica',
  QuizQuestionType.multiple => 'seleccion_multiple',
  QuizQuestionType.fillBlank => 'completar',
  QuizQuestionType.shortAnswer => 'respuesta_breve',
};
