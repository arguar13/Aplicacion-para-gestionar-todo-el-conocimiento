import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Lo que la infografía guarda en las opciones de su creación (F43, paso 12),
/// además de las de fábrica —la orientación, el detalle y «Ilustraciones con
/// IA» (`CreationOptionValues`)—.
abstract final class InfographicOptionKeys {
  /// El estilo visual elegido en el carrusel de la hoja: el `id` de un
  /// `InfographicStyleId` (`auto` para «Automático»).
  static const style = 'style';

  /// El diseño entero del visor (`InfographicDesign.toJson`): la paleta, la
  /// letra, la composición, los íconos y el fondo que se eligieron después.
  /// Va en las opciones y no en el contenido (decisión G): el contenido es lo
  /// que escribió la IA, y cambiar el diseño no lo toca.
  static const design = 'design';
}

/// El diseño con que se dibuja una infografía de [options]: lo guardado del
/// visor y, encima, el estilo, la orientación y el detalle de la hoja —que
/// son lo que la persona ve y cambia al volver a generar—. Nunca falla: lo
/// que falta o no se entiende queda de fábrica.
InfographicDesign infographicDesignOf(Map<String, Object?> options) {
  final saved = InfographicDesign.parse(options[InfographicOptionKeys.design]);
  return saved.copyWith(
    style:
        InfographicStyleId.fromId(options[InfographicOptionKeys.style]) ??
        saved.style,
    orientation:
        _pick(
          options[CreationOptionValues.orientation],
          InfographicOrientation.values,
          (o) => o.id,
        ) ??
        saved.orientation,
    detail:
        _pick(
          options[CreationOptionValues.detail],
          InfographicDetail.values,
          (d) => d.id,
        ) ??
        saved.detail,
  );
}

/// [options] con [design]: el diseño entero y, a la par, el estilo, la
/// orientación y el detalle que lee la hoja, para que «Volver a generar»
/// arranque con lo que se ve.
Map<String, Object?> withInfographicDesign(
  Map<String, Object?> options,
  InfographicDesign design,
) => {
  ...options,
  InfographicOptionKeys.style: design.style.id,
  CreationOptionValues.orientation: design.orientation.id,
  CreationOptionValues.detail: design.detail.id,
  InfographicOptionKeys.design: design.toJson(),
};

/// Si se pidieron ilustraciones con IA.
bool infographicWantsIllustrations(Map<String, Object?> options) =>
    options[CreationOptionValues.illustrations] == true;

/// Cuántos bloques se ven, como mucho, con cada detalle: lo que pide
/// `infographicDetailPrompt` y lo que entra en la composición más generosa.
int infographicVisibleBlocks(InfographicDetail detail) => switch (detail) {
  InfographicDetail.concise => 5,
  InfographicDetail.standard => 7,
  InfographicDetail.detailed => 9,
};

/// Cuántos bloques de un estilo dibujado llevan su ilustración: los que más
/// ganan con un dibujo, no todos —el resto va con su ícono—.
int infographicDrawnIllustrations(InfographicDetail detail) => switch (detail) {
  InfographicDetail.concise => 2,
  InfographicDetail.standard => 3,
  InfographicDetail.detailed => 4,
};

/// Cuántas ilustraciones pide una infografía de [options] (decisión H), para
/// «Uso de IA» y «Con tu IA actual», y el tope de lo que se dibuja: el
/// generador nunca pide más que esto.
///
/// - Un estilo con ilustraciones con IA —y «Automático», que con el
///   interruptor prendido elige uno de esos— lleva la cabecera y cada bloque
///   que se ve.
/// - Uno dibujado por la app lleva solo los bloques que más ganan con un
///   dibujo.
int infographicIllustrationsFor(Map<String, Object?> options) {
  final design = infographicDesignOf(options);
  final illustrated =
      design.style == InfographicStyleId.auto || design.style.isIllustrated;
  return illustrated
      ? 1 + infographicVisibleBlocks(design.detail)
      : infographicDrawnIllustrations(design.detail);
}

/// Cuánto escribe la IA con [options]: lo que piden los bloques del detalle
/// y, con ilustraciones, una oración por cada una.
int infographicOutputTokens(Map<String, Object?> options) {
  final detail = infographicDesignOf(options).detail;
  final text = switch (detail) {
    InfographicDetail.concise => 1100,
    InfographicDetail.standard => 1700,
    InfographicDetail.detailed => 2600,
  };
  return infographicWantsIllustrations(options)
      ? text + 40 * infographicIllustrationsFor(options)
      : text;
}

T? _pick<T>(Object? raw, List<T> values, String Function(T) id) {
  for (final value in values) {
    if (id(value) == raw) return value;
  }
  return null;
}
