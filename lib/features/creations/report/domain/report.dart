import 'package:freezed_annotation/freezed_annotation.dart';

part 'report.freezed.dart';

/// Un informe de «Lo creado» (F43, punto 4 del plan: «Informes»): su título
/// y sus secciones, y nada de su diseño (decisión G). Lo escribe la IA en el
/// JSON de `reportJsonSchemaPrompt`; lo dibuja la app —el visor, el PDF y el
/// Markdown—, así que cambiar cómo se ve nunca vuelve a llamar a la IA.
@freezed
abstract class Report with _$Report {
  const factory Report({
    required String title,

    /// Una oración que dice de qué trata; vacía si la IA no la puso.
    @Default('') String subtitle,
    @Default(<ReportSection>[]) List<ReportSection> sections,

    /// Las palabras clave que la IA destacó en el informe: el rosa de
    /// reserva cuando las fuentes todavía no tienen las suyas (decisión 85).
    @Default(<String>[]) List<String> keywords,
  }) = _Report;

  const Report._();

  /// Cuántas preguntas trae, sumando las de todas las secciones.
  int get questionCount =>
      sections.fold(0, (sum, section) => sum + section.questions.length);

  /// Si no hay nada que leer.
  bool get isEmpty => sections.isEmpty;
}

/// Una sección del informe: su título, su texto y, según la plantilla y el
/// formato, los términos de un glosario y las preguntas para probarse.
@freezed
abstract class ReportSection with _$ReportSection {
  const factory ReportSection({
    required String title,

    /// El texto, con lo poco de Markdown que entiende el visor
    /// (`parseReportBody`): párrafos separados por una línea en blanco,
    /// viñetas con «- », listas numeradas, `### subtítulos` y `**negrita**`.
    @Default('') String body,

    /// Los términos con su definición (el glosario).
    @Default(<ReportEntry>[]) List<ReportEntry> entries,

    /// Las preguntas del final de la sección (el formato interactivo).
    @Default(<ReportQuestion>[]) List<ReportQuestion> questions,
  }) = _ReportSection;

  const ReportSection._();

  /// Si tiene algo para leer: texto o términos.
  bool get hasContent => body.trim().isNotEmpty || entries.isNotEmpty;
}

/// Un término del glosario con su definición.
@freezed
abstract class ReportEntry with _$ReportEntry {
  const factory ReportEntry({
    required String term,
    @Default('') String definition,
  }) = _ReportEntry;
}

/// Una pregunta de opción única para probarse al final de una sección: sus
/// opciones, cuál es la correcta y por qué.
@freezed
abstract class ReportQuestion with _$ReportQuestion {
  const factory ReportQuestion({
    required String question,
    required List<ReportOption> options,

    /// El lugar de la correcta en [options].
    required int answer,

    /// Por qué la correcta es la correcta.
    @Default('') String explanation,
  }) = _ReportQuestion;

  const ReportQuestion._();

  ReportOption get correct => options[answer];
}

/// Una opción de una pregunta, con su porqué: lo que se muestra debajo al
/// elegirla si no era la correcta.
@freezed
abstract class ReportOption with _$ReportOption {
  const factory ReportOption({required String text, @Default('') String why}) =
      _ReportOption;
}
