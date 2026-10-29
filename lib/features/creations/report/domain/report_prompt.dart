import 'package:sinapsis/features/creations/report/domain/report_template.dart';

/// La forma del JSON de un informe, dicha para el modelo (F43, decisión G):
/// un ejemplo con comentarios cortos. Breve —con Gemma entra junto con la
/// instrucción en la reserva del pedido—, y solo con lo que pide esta
/// creación: los términos en el glosario, las preguntas en el interactivo.
String reportJsonSchemaPrompt({
  required ReportTemplate template,
  required ReportFormat format,
}) {
  final glossary = template == ReportTemplate.glossary;
  final interactive = format == ReportFormat.interactive;
  final section = StringBuffer()
    ..writeln('    {')
    ..writeln('      "title": "título de la sección",');
  if (glossary) {
    section
      ..writeln('      "body": "",')
      ..write(
        '      "entries": [{"term": "término", '
        '"definition": "qué es y por qué importa en el material"}]',
      );
  } else {
    section.write(
      '      "body": "párrafos separados por una línea en blanco; viñetas '
      r'con \"- \" al principio de la línea; listas numeradas con \"1. \"; '
      r'\"**negrita**\" para lo importante"',
    );
  }
  if (interactive) {
    section
      ..writeln(',')
      ..writeln('      "questions": [')
      ..writeln('        {')
      ..writeln('          "question": "pregunta sobre esta sección",')
      ..writeln('          "options": [')
      ..writeln(
        '            {"text": "opción correcta", "correct": true, '
        '"why": "por qué es la correcta"},',
      )
      ..writeln(
        '            {"text": "opción incorrecta pero creíble", '
        '"correct": false, "why": "por qué no es"}',
      )
      ..writeln('          ],')
      ..writeln(
        '          "explanation": "la explicación de la respuesta, con lo '
        'que dice el material"',
      )
      ..writeln('        }')
      ..write('      ]');
  }
  section
    ..writeln()
    ..write('    }');
  return '{\n'
      '  "title": "título del informe",\n'
      '  "subtitle": "una oración que dice de qué trata",\n'
      '  "sections": [\n'
      '$section\n'
      '  ],\n'
      '  "keywords": ["las palabras clave del informe"]\n'
      '}';
}

/// La tarea de un informe con [template] y [format]: qué armar, con la
/// estructura de la plantilla y, si es la propia, lo que escribió la persona
/// con ✎ ([custom]).
String reportTask({
  required ReportTemplate template,
  required ReportFormat format,
  String custom = '',
}) {
  final buffer = StringBuffer(
    'escribir un informe bien redactado sobre el material, con secciones '
    'que tengan cada una su título. ${template.guidance}',
  );
  if (template == ReportTemplate.custom && custom.isNotEmpty) {
    buffer.write(' El pedido de la persona para su plantilla: «$custom».');
  }
  buffer.write(
    ' Los títulos de las secciones, cortos y en el idioma del informe. '
    'Usá viñetas para enumerar y negrita solo para lo esencial.',
  );
  if (format == ReportFormat.interactive) {
    buffer.write(
      ' Al final de cada sección, dos o tres preguntas de opción única para '
      'que la persona se pruebe sobre lo que acaba de leer: cuatro opciones, '
      'una sola correcta, las incorrectas creíbles y sacadas del mismo '
      'material, cada opción con su porqué en una oración y la explicación '
      'de la respuesta.',
    );
  }
  return buffer.toString();
}

/// Lo que se le pide a UNA parte del material, por partes: las secciones
/// que esa parte aporta, para que el último paso las una en la estructura de
/// la plantilla.
String reportPartTask({
  required ReportTemplate template,
  required ReportFormat format,
}) {
  final what = template == ReportTemplate.glossary
      ? 'los términos propios de esta parte con su definición'
      : 'las ideas, los hechos y los datos importantes de esta parte, en '
            'secciones con su título';
  final questions = format == ReportFormat.interactive
      ? ', con una o dos preguntas de opción única por sección'
      : '';
  return 'armar el borrador de un informe solo con esta parte del material: '
      '$what$questions. Nada de introducciones ni conclusiones generales: '
      'eso se arma al unir las partes';
}

/// Lo que se hace con los borradores de las partes: unirlos en un solo
/// informe con la estructura de la plantilla.
String reportMergeTask({
  required ReportTemplate template,
  required ReportFormat format,
  String custom = '',
}) =>
    'unir en un solo informe los borradores que se te dan —cada uno se armó '
    'con una parte del material, en orden—, sin repetir nada y sin perder '
    'nada importante, reorganizando todo en la estructura que sigue. '
    '${reportTask(template: template, format: format, custom: custom)}';
