import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Cómo se lee un informe (F43, punto 4 del plan): **interactivo**, con dos o
/// tres preguntas para probarse al final de cada sección, o **documento**,
/// para leer de corrido, imprimir o compartir.
enum ReportFormat {
  interactive(CreationOptionValues.interactive),
  document(CreationOptionValues.document);

  const ReportFormat(this.value);

  /// Lo que se guarda en las opciones (`CreationOptionValues.format`).
  final String value;

  /// El de [options]; el interactivo si falta o no se conoce, como la hoja.
  static ReportFormat of(Map<String, Object?> options) =>
      options[CreationOptionValues.format] == CreationOptionValues.document
      ? document
      : interactive;
}

/// Las plantillas de un informe (F43, punto 4 del plan): cuatro con nombre y
/// una propia, la que la persona describe con ✎.
///
/// Cada una dice a la IA qué secciones lleva y qué va en cada una
/// ([guidance]): la estructura es de la plantilla, no del azar del modelo. Las
/// secciones se titulan en el idioma de la creación; la guía está en
/// castellano, como toda instrucción de la app.
enum ReportTemplate {
  /// Lo que hay que llevarse del material, de lo general a lo particular.
  learningSummary(
    CreationOptionValues.learningSummary,
    sections: 6,
    outputTokens: 2600,
    guidance:
        'Es un RESUMEN DE APRENDIZAJE: lo que alguien tiene que llevarse del '
        'material para entenderlo. Estructura, en este orden: 1) '
        '«Introducción»: de qué trata y por qué importa, en un párrafo; 2) de '
        'tres a cinco secciones, una por cada idea central del material, con '
        'su explicación en un párrafo y sus puntos principales en viñetas; 3) '
        '«Conceptos clave»: los términos imprescindibles, en viñetas, cada uno '
        'con una frase que lo explica; 4) «Conclusión»: lo esencial en dos o '
        'tres oraciones.',
  ),

  /// Para preparar un examen: objetivos, conceptos, desarrollo y repaso.
  studyGuide(
    CreationOptionValues.studyGuide,
    sections: 7,
    outputTokens: 3200,
    guidance:
        'Es una GUÍA DE ESTUDIO para preparar un examen sobre el material. '
        'Estructura, en este orden: 1) «Objetivos de aprendizaje»: qué hay que '
        'poder explicar al terminar, en viñetas que empiezan con un verbo; 2) '
        '«Conceptos clave»: cada término en negrita con su definición breve, '
        'en viñetas; 3) de dos a cuatro secciones de desarrollo, una por tema, '
        'con lo que hay que saber de cada uno; 4) «Preguntas para repasar»: '
        'de cinco a ocho preguntas abiertas en una lista numerada, cada una '
        'con su respuesta breve en la línea siguiente; 5) «Para no '
        'confundir»: los errores frecuentes y las distinciones finas, en '
        'viñetas; 6) «Resumen final»: lo esencial en un párrafo.',
  ),

  /// Lo que hay que saber para decidir o ponerse al día, sin vueltas.
  briefing(
    CreationOptionValues.briefing,
    sections: 6,
    outputTokens: 2400,
    guidance:
        'Es un DOCUMENTO INFORMATIVO (un «briefing»): lo que alguien ocupado '
        'necesita saber del material para ponerse al día, sin vueltas. '
        'Estructura, en este orden: 1) «Resumen ejecutivo»: lo más importante '
        'en tres a cinco viñetas; 2) «Contexto»: de dónde viene el tema, en un '
        'párrafo; 3) «Puntos principales»: los hallazgos, hechos o argumentos '
        'centrales, cada uno con su explicación; 4) «Datos y citas '
        'destacados»: cifras, fechas, nombres o frases textuales del '
        'material, en viñetas; 5) «Implicancias»: qué significa todo esto; 6) '
        '«Conclusiones».',
  ),

  /// Los términos del material, en orden alfabético, con su definición.
  glossary(
    CreationOptionValues.glossary,
    sections: 8,
    outputTokens: 2800,
    guidance:
        'Es un GLOSARIO: los términos propios del material —conceptos, '
        'nombres, lugares, obras, siglas— con su definición tal como el '
        'material los usa. Entre quince y cuarenta términos, sin repetir. '
        'Cada definición, de una o dos oraciones, dice qué es y por qué '
        'importa en el material. Agrupalos en secciones por su letra '
        'inicial, en orden alfabético —la sección se titula con la letra—, y '
        'poné los términos en el campo «entries» de cada sección, también en '
        'orden alfabético; el «body» de cada sección queda vacío.',
  ),

  /// La que la persona describe con ✎: su estructura, sus secciones, su
  /// tono.
  custom(
    CreationOptionValues.custom,
    sections: 6,
    outputTokens: 3000,
    guidance:
        'Es un informe con la estructura que pidió la persona. Seguí su '
        'pedido al pie de la letra en las secciones, su orden y su tono; si '
        'no dice cuántas secciones, armá entre cuatro y siete.',
  );

  const ReportTemplate(
    this.value, {
    required this.sections,
    required this.outputTokens,
    required this.guidance,
  });

  /// Lo que se guarda en las opciones (`CreationOptionValues.template`).
  final String value;

  /// Cuántas secciones trae, más o menos: para estimar y para las preguntas.
  final int sections;

  /// Cuánto escribe la IA con esta plantilla en formato documento.
  final int outputTokens;

  /// Lo que se le dice a la IA de su estructura.
  final String guidance;

  /// La de [value]; el resumen de aprendizaje si no se conoce.
  static ReportTemplate fromValue(Object? value) {
    for (final template in values) {
      if (template.value == value) return template;
    }
    return learningSummary;
  }

  /// La de [options].
  static ReportTemplate of(Map<String, Object?> options) =>
      fromValue(options[CreationOptionValues.template]);
}

/// Lo que la persona escribió con ✎ en [options], o vacío.
String reportCustomTemplateOf(Map<String, Object?> options) {
  final value = options[CreationOptionValues.customTemplate];
  return value is String ? value.trim() : '';
}

/// Cuántas preguntas trae cada sección del interactivo, como mucho: «dos o
/// tres preguntas para probarse ahí mismo» (punto 5 del plan).
const kReportQuestionsPerSection = 3;

/// Lo que se estima que escribe la IA para cada pregunta del interactivo: la
/// pregunta, cuatro opciones con su porqué y la explicación.
const kReportTokensPerQuestion = 120;

/// Cuánto escribe la IA con [options]: lo de la plantilla y, en el
/// interactivo, sus preguntas (dos y media por sección, en promedio).
int reportOutputTokens(Map<String, Object?> options) {
  final template = ReportTemplate.of(options);
  final questions = ReportFormat.of(options) == ReportFormat.interactive
      ? (template.sections * 2.5).round() * kReportTokensPerQuestion
      : 0;
  return template.outputTokens + questions;
}
