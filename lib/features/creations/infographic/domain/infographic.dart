import 'package:freezed_annotation/freezed_annotation.dart';

part 'infographic.freezed.dart';

/// Los ocho tipos de bloque de una infografía (F43, «Plantillas →
/// Infografía»). La IA elige qué tipo es cada cosa que cuenta; la
/// composición y el estilo deciden cómo se ve.
///
/// [jsonName] es lo que viaja en el JSON de la IA y lo que se guarda: no
/// cambia aunque cambie el nombre del valor.
enum InfographicBlockKind {
  stat('stat'),
  fact('fact'),
  step('step'),
  comparison('comparison'),
  event('event'),
  concept('concept'),
  quote('quote'),
  chart('chart');

  const InfographicBlockKind(this.jsonName);

  final String jsonName;
}

/// Los cuatro gráficos que dibuja la app (F43: «Gráficos dibujados por la
/// app cuando el contenido trae números»).
enum InfographicChartKind {
  /// Barras horizontales, una por dato, con su rótulo y su cifra.
  bars('bars'),

  /// Un anillo: un porcentaje solo, o las partes de un todo.
  ring('ring'),

  /// Barras de avance: cuánto de un total.
  progress('progress'),

  /// Íconos que se pintan: «7 de cada 10».
  pictogram('pictogram');

  const InfographicChartKind(this.jsonName);

  final String jsonName;
}

/// Cuánto pesa un bloque, para el detalle elegido (ver
/// `InfographicDetail`): lo esencial se ve siempre; lo de apoyo, desde
/// «Estándar»; lo de más, solo en «Detallado».
enum InfographicLevel {
  essential(1),
  supporting(2),
  extra(3);

  const InfographicLevel(this.value);

  final int value;

  static InfographicLevel? fromValue(int? value) {
    for (final level in values) {
      if (level.value == value) return level;
    }
    return null;
  }
}

/// Un lado de una comparación: su nombre y lo que lo define.
@freezed
abstract class InfographicSide with _$InfographicSide {
  const factory InfographicSide({
    @Default('') String heading,
    @Default(<String>[]) List<String> points,
    String? icon,
  }) = _InfographicSide;
}

/// Un dato de un gráfico: su rótulo, su número y cómo se escribe («40 %»,
/// «3.000.000», «x2»). [display] vacío: se escribe el número.
@freezed
abstract class InfographicDatum with _$InfographicDatum {
  const factory InfographicDatum({
    required String label,
    required double value,
    @Default('') String display,
  }) = _InfographicDatum;
}

/// Un bloque de la lámina: su contenido, y nada de su diseño (decisión G).
///
/// Todos comparten tres cosas:
///
/// - [level], cuánto pesa (ver [InfographicLevel]): decide qué se ve con
///   cada detalle sin volver a pedirle nada a la IA;
/// - [illustrationPrompt], lo que la IA pediría dibujar si el bloque gana con
///   una ilustración (los estilos con ilustraciones con IA);
/// - [illustrationRef], la ilustración ya hecha —la ruta o la clave del
///   archivo—, o null mientras no haya una: entonces se dibuja la de
///   reserva con los colores del estilo.
@freezed
sealed class InfographicBlock with _$InfographicBlock {
  /// Una cifra destacada: el número tal como se escribe, qué es y un
  /// detalle.
  const factory InfographicBlock.stat({
    required String value,
    @Default('') String label,
    @Default('') String detail,
    String? icon,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = StatBlock;

  /// Una idea, un hecho o un dato clave, con su ícono.
  const factory InfographicBlock.fact({
    required String title,
    @Default('') String detail,
    String? icon,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = FactBlock;

  /// Un paso de un proceso; el orden es el de la lista.
  const factory InfographicBlock.step({
    required String title,
    @Default('') String detail,
    String? icon,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = StepBlock;

  /// Dos cosas frente a frente y, si la hay, la conclusión.
  const factory InfographicBlock.comparison({
    @Default('') String title,
    @Default(InfographicSide()) InfographicSide left,
    @Default(InfographicSide()) InfographicSide right,
    @Default('') String conclusion,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = ComparisonBlock;

  /// Un hito: la fecha tal como la escribe el texto («1492», «Siglo XIII»,
  /// «Día 3»), no una fecha calculada.
  const factory InfographicBlock.event({
    required String date,
    required String title,
    @Default('') String detail,
    String? icon,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = EventBlock;

  /// Un concepto del tema, con su ícono: los nodos del mapa de conceptos.
  const factory InfographicBlock.concept({
    required String title,
    @Default('') String detail,
    String? icon,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = ConceptBlock;

  /// Una cita textual del material, con quién la dijo y de dónde sale.
  const factory InfographicBlock.quote({
    required String quote,
    @Default('') String author,
    @Default('') String source,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = QuoteBlock;

  /// Un gráfico con los números del material. [chartKind] null: lo elige la
  /// app según los datos (ver `InfographicChartData.kindOf`).
  const factory InfographicBlock.chart({
    @Default('') String title,
    InfographicChartKind? chartKind,
    @Default(<InfographicDatum>[]) List<InfographicDatum> data,

    /// La unidad de los números («%», «años», «km»), si la hay.
    @Default('') String unit,

    /// El total contra el que se mide (el 100 de un avance, las 10 de «7 de
    /// cada 10»); null si no hay uno.
    double? total,
    @Default('') String detail,

    /// El ícono que se repite en el pictograma; null, una persona.
    String? icon,
    @Default(InfographicLevel.essential) InfographicLevel level,
    String? illustrationPrompt,
    String? illustrationRef,
  }) = ChartBlock;

  const InfographicBlock._();

  InfographicBlockKind get kind => switch (this) {
    StatBlock() => InfographicBlockKind.stat,
    FactBlock() => InfographicBlockKind.fact,
    StepBlock() => InfographicBlockKind.step,
    ComparisonBlock() => InfographicBlockKind.comparison,
    EventBlock() => InfographicBlockKind.event,
    ConceptBlock() => InfographicBlockKind.concept,
    QuoteBlock() => InfographicBlockKind.quote,
    ChartBlock() => InfographicBlockKind.chart,
  };

  /// El texto principal del bloque: para el nodo de un mapa, la semántica y
  /// el índice.
  String get headline => switch (this) {
    StatBlock(:final value, :final label) =>
      label.isEmpty ? value : '$value $label',
    FactBlock(:final title) ||
    StepBlock(:final title) ||
    ConceptBlock(:final title) => title,
    EventBlock(:final date, :final title) =>
      title.isEmpty ? date : (date.isEmpty ? title : '$date · $title'),
    ComparisonBlock(:final title, :final left, :final right) =>
      title.isNotEmpty ? title : '${left.heading} / ${right.heading}',
    QuoteBlock(:final quote) => quote,
    ChartBlock(:final title, :final data) =>
      title.isNotEmpty
          ? title
          : data.map((d) => d.label).where((l) => l.isNotEmpty).join(', '),
  };

  /// El nombre del ícono que eligió la IA, si el tipo lleva uno.
  String? get iconName => switch (this) {
    StatBlock(:final icon) ||
    FactBlock(:final icon) ||
    StepBlock(:final icon) ||
    EventBlock(:final icon) ||
    ConceptBlock(:final icon) ||
    ChartBlock(:final icon) => icon,
    ComparisonBlock() || QuoteBlock() => null,
  };

  /// Si el bloque quiere una ilustración: la pidió la IA o ya tiene una.
  bool get wantsIllustration =>
      illustrationRef != null || (illustrationPrompt?.isNotEmpty ?? false);

  /// Si el bloque trae números para un gráfico o una cifra.
  bool get isNumeric => this is ChartBlock || this is StatBlock;
}

/// Una infografía: el contenido que escribe la IA (decisión G), una lámina
/// con su título, sus bloques, una idea para llevarse y de dónde sale. Se
/// guarda como JSON en «Lo creado» —ver `InfographicJson`—, y el diseño va
/// aparte, en `InfographicDesign`.
@freezed
abstract class Infographic with _$Infographic {
  const factory Infographic({
    required String title,
    @Default('') String subtitle,

    /// La línea chica de arriba del título («Estudio · Éxodo»).
    @Default('') String kicker,
    @Default(<InfographicBlock>[]) List<InfographicBlock> blocks,

    /// La idea para llevarse, en la franja de abajo.
    @Default('') String takeaway,

    /// De dónde sale: el documento o el autor, en letra chica al pie.
    @Default('') String source,

    /// El estilo que sugirió la IA según el tema (el `id` de un estilo), para
    /// «Automático»; null si no sugirió ninguno.
    String? styleHint,

    /// La composición que sugirió la IA (el `jsonName` de una), para
    /// «Automática»; null si no sugirió ninguna.
    String? compositionHint,

    /// La ilustración grande de la cabecera, en los estilos con
    /// ilustraciones con IA.
    String? illustrationPrompt,
    String? illustrationRef,
  }) = _Infographic;

  const Infographic._();

  /// Si la cabecera quiere una ilustración.
  bool get wantsIllustration =>
      illustrationRef != null || (illustrationPrompt?.isNotEmpty ?? false);
}
