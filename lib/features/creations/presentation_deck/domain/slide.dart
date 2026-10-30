import 'package:freezed_annotation/freezed_annotation.dart';

part 'slide.freezed.dart';

/// Los veinte diseños de diapositiva: los doce de F43 («Plantillas →
/// Presentación») y los ocho de F45. La IA elige cuál va en cada una; la
/// plantilla decide cómo se ve.
///
/// [jsonName] es lo que viaja en el JSON de la IA y lo que se guarda: no
/// cambia aunque cambie el nombre del valor.
enum SlideLayout {
  cover('cover'),
  section('section'),
  bullets('bullets'),
  twoColumns('two_columns'),
  quote('quote'),
  bigNumber('big_number'),
  steps('steps'),
  comparison('comparison'),
  timeline('timeline'),
  imageText('image_text'),
  conceptGrid('concept_grid'),
  closing('closing'),

  // F45.
  fullQuote('full_quote'),
  imageGrid('image_grid'),
  conceptMap('concept_map'),
  questions('questions'),
  statGrid('stat_grid'),
  cycle('cycle'),
  matrix('matrix'),
  definition('definition');

  const SlideLayout(this.jsonName);

  final String jsonName;
}

/// Una columna con su encabezado y sus puntos: los dos lados de «dos
/// columnas» y de la comparación.
@freezed
abstract class SlideColumn with _$SlideColumn {
  const factory SlideColumn({
    @Default('') String heading,
    @Default(<String>[]) List<String> points,
  }) = _SlideColumn;
}

/// Un paso de la línea de pasos.
@freezed
abstract class SlideStep with _$SlideStep {
  const factory SlideStep({required String title, @Default('') String detail}) =
      _SlideStep;
}

/// Un hito de la cronología: la fecha tal como la escribe el texto («1492»,
/// «Siglo XIII», «Día 3»), no una fecha calculada.
@freezed
abstract class TimelineEvent with _$TimelineEvent {
  const factory TimelineEvent({
    required String date,
    required String title,
    @Default('') String detail,
  }) = _TimelineEvent;
}

/// Una tarjeta de la cuadrícula de conceptos, con el nombre de su ícono del
/// juego de lo creado (ver `CreationIcons`), o null para el de reserva.
@freezed
abstract class SlideConcept with _$SlideConcept {
  const factory SlideConcept({
    required String title,
    @Default('') String detail,
    String? icon,
  }) = _SlideConcept;
}

/// Una imagen de la cuadrícula de imágenes (F45): su epígrafe y el ícono
/// del juego de lo creado con que se dibuja mientras no haya una de verdad.
@freezed
abstract class SlideImage with _$SlideImage {
  const factory SlideImage({required String caption, String? icon}) =
      _SlideImage;
}

/// Una cifra del panel de cifras (F45), como en la cifra destacada: el
/// número tal como se escribe, qué es y un detalle.
@freezed
abstract class SlideStat with _$SlideStat {
  const factory SlideStat({
    required String value,
    @Default('') String label,
    @Default('') String detail,
  }) = _SlideStat;
}

/// Una diapositiva: su contenido, y nada de su diseño (decisión G). El
/// diseño —plantilla, paleta, letra— va aparte, en `DeckDesign`, así se
/// cambia sin volver a pedirle nada a la IA.
///
/// Todas comparten tres cosas:
///
/// - [speakerNotes], lo que se dice en voz alta (en el formato «Del
///   presentador» es lo principal);
/// - [illustrationPrompt], lo que la IA pediría dibujar, si la diapositiva
///   gana con una ilustración;
/// - [illustrationRef], la ilustración ya hecha —la ruta o la clave del
///   archivo—, o null mientras no haya una: entonces se dibuja una
///   composición con los colores de la plantilla en su lugar.
@freezed
sealed class Slide with _$Slide {
  /// La portada.
  const factory Slide.cover({
    required String title,
    @Default('') String subtitle,

    /// La línea chica de arriba del título («Estudio · Éxodo»).
    @Default('') String kicker,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = CoverSlide;

  /// El comienzo de una parte.
  const factory Slide.section({
    required String title,
    @Default('') String subtitle,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = SectionSlide;

  /// Un título con sus viñetas.
  const factory Slide.bullets({
    required String title,
    @Default(<String>[]) List<String> bullets,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = BulletsSlide;

  /// Dos columnas, cada una con su encabezado y sus puntos.
  const factory Slide.twoColumns({
    required String title,
    @Default(SlideColumn()) SlideColumn left,
    @Default(SlideColumn()) SlideColumn right,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = TwoColumnsSlide;

  /// Una cita, con quién la dijo y de dónde sale.
  const factory Slide.quote({
    required String quote,
    @Default('') String author,
    @Default('') String source,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = QuoteSlide;

  /// Una cifra destacada: el número tal como se escribe («3.000.000»,
  /// «40 %», «x2»), qué es y un detalle.
  const factory Slide.bigNumber({
    required String value,
    @Default('') String title,
    @Default('') String label,
    @Default('') String detail,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = BigNumberSlide;

  /// Una línea de pasos, en orden.
  const factory Slide.steps({
    required String title,
    @Default(<SlideStep>[]) List<SlideStep> steps,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = StepsSlide;

  /// Dos cosas frente a frente y, si la hay, la conclusión.
  const factory Slide.comparison({
    required String title,
    @Default(SlideColumn()) SlideColumn left,
    @Default(SlideColumn()) SlideColumn right,
    @Default('') String conclusion,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = ComparisonSlide;

  /// Una cronología de hitos.
  const factory Slide.timeline({
    required String title,
    @Default(<TimelineEvent>[]) List<TimelineEvent> events,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = TimelineSlide;

  /// Una imagen grande con su texto al lado.
  const factory Slide.imageText({
    required String title,
    @Default('') String body,
    @Default(<String>[]) List<String> bullets,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = ImageTextSlide;

  /// Una cuadrícula de conceptos, cada uno con su ícono.
  const factory Slide.conceptGrid({
    required String title,
    @Default(<SlideConcept>[]) List<SlideConcept> concepts,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = ConceptGridSlide;

  /// El cierre: lo que hay que llevarse.
  const factory Slide.closing({
    required String title,
    @Default('') String subtitle,
    @Default(<String>[]) List<String> takeaways,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = ClosingSlide;

  /// Una cita a toda página (F45): la frase enorme sobre un campo de
  /// color, o sobre su ilustración.
  const factory Slide.fullQuote({
    required String quote,
    @Default('') String author,
    @Default('') String source,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = FullQuoteSlide;

  /// Una cuadrícula de imágenes (F45), cada una con su epígrafe. La
  /// ilustración de la diapositiva va en la primera; las demás las dibuja
  /// la app con su ícono.
  const factory Slide.imageGrid({
    required String title,
    @Default(<SlideImage>[]) List<SlideImage> images,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = ImageGridSlide;

  /// Un mapa de conceptos (F45): la idea del centro y sus ramas.
  const factory Slide.conceptMap({
    required String title,

    /// La idea del centro; vacía, el título.
    @Default('') String center,
    @Default(<SlideConcept>[]) List<SlideConcept> nodes,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = ConceptMapSlide;

  /// Un cierre con preguntas (F45): para pensar o conversar al final.
  const factory Slide.questions({
    required String title,
    @Default('') String subtitle,
    @Default(<String>[]) List<String> questions,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = QuestionsSlide;

  /// Un panel de cifras (F45): dos a cuatro cifras destacadas juntas.
  const factory Slide.statGrid({
    required String title,
    @Default(<SlideStat>[]) List<SlideStat> stats,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = StatGridSlide;

  /// Un ciclo (F45): pasos que vuelven a empezar, en una rueda.
  const factory Slide.cycle({
    required String title,

    /// Lo que gira, en el medio de la rueda; vacío, nada.
    @Default('') String center,
    @Default(<SlideStep>[]) List<SlideStep> steps,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = CycleSlide;

  /// Una matriz de dos por dos (F45): cuatro cuadrantes, de arriba a la
  /// izquierda a abajo a la derecha, con el nombre de cada eje.
  const factory Slide.matrix({
    required String title,
    @Default('') String xAxis,
    @Default('') String yAxis,
    @Default(<SlideColumn>[]) List<SlideColumn> quadrants,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = MatrixSlide;

  /// Una definición (F45): el término grande, qué es y un ejemplo.
  const factory Slide.definition({
    required String term,
    @Default('') String definition,
    @Default('') String example,

    /// La línea chica de arriba del término (la disciplina, la categoría).
    @Default('') String kicker,
    String? illustrationPrompt,
    String? illustrationRef,
    @Default('') String speakerNotes,
  }) = DefinitionSlide;

  const Slide._();

  SlideLayout get layout => switch (this) {
    CoverSlide() => SlideLayout.cover,
    SectionSlide() => SlideLayout.section,
    BulletsSlide() => SlideLayout.bullets,
    TwoColumnsSlide() => SlideLayout.twoColumns,
    QuoteSlide() => SlideLayout.quote,
    BigNumberSlide() => SlideLayout.bigNumber,
    StepsSlide() => SlideLayout.steps,
    ComparisonSlide() => SlideLayout.comparison,
    TimelineSlide() => SlideLayout.timeline,
    ImageTextSlide() => SlideLayout.imageText,
    ConceptGridSlide() => SlideLayout.conceptGrid,
    ClosingSlide() => SlideLayout.closing,
    FullQuoteSlide() => SlideLayout.fullQuote,
    ImageGridSlide() => SlideLayout.imageGrid,
    ConceptMapSlide() => SlideLayout.conceptMap,
    QuestionsSlide() => SlideLayout.questions,
    StatGridSlide() => SlideLayout.statGrid,
    CycleSlide() => SlideLayout.cycle,
    MatrixSlide() => SlideLayout.matrix,
    DefinitionSlide() => SlideLayout.definition,
  };

  /// El título que se ve —en una cita, la cita misma—: para la miniatura,
  /// el índice y el pie.
  String get headline => switch (this) {
    CoverSlide(:final title) ||
    SectionSlide(:final title) ||
    BulletsSlide(:final title) ||
    TwoColumnsSlide(:final title) ||
    StepsSlide(:final title) ||
    ComparisonSlide(:final title) ||
    TimelineSlide(:final title) ||
    ImageTextSlide(:final title) ||
    ConceptGridSlide(:final title) ||
    ClosingSlide(:final title) ||
    ImageGridSlide(:final title) ||
    QuestionsSlide(:final title) ||
    CycleSlide(:final title) ||
    MatrixSlide(:final title) => title,
    QuoteSlide(:final quote) || FullQuoteSlide(:final quote) => quote,
    BigNumberSlide(:final title, :final value) => title.isEmpty ? value : title,
    ConceptMapSlide(:final title, :final center) =>
      title.isEmpty ? center : title,
    StatGridSlide(:final title, :final stats) =>
      title.isNotEmpty || stats.isEmpty ? title : stats.first.value,
    DefinitionSlide(:final term) => term,
  };

  /// Si la diapositiva quiere una ilustración: la pidió la IA o ya tiene una.
  bool get wantsIllustration =>
      illustrationRef != null || (illustrationPrompt?.isNotEmpty ?? false);
}
