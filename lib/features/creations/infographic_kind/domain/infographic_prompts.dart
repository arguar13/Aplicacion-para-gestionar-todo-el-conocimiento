import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_schema_prompt.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';

/// Lo que se le pide a la IA para una infografía (F43, paso 12): la tarea, el
/// esquema y, por partes, qué hace cada parte y cómo se unen. Vive acá, con el
/// tipo, y no en `LanguageModelTasks` (ver `StructuredWriter`).
///
/// La IA escribe el contenido; la orientación, el estilo y el dibujo los pone
/// la app (decisión G). Por eso la tarea solo le dice lo que cambia lo que
/// escribe: cuánto contar, qué estilo sugerir cuando es «Automático» y dónde
/// describir una ilustración.
abstract final class InfographicPrompts {
  /// Cuántos bloques da, como mucho, cada parte de un material largo: el
  /// paso de unir elige entre todos.
  static const blocksPerPart = 6;

  /// El tope de lo que escribe cada parte.
  static const partOutputTokens = 1200;

  /// El esquema con lo que pide el detalle.
  static String schema(InfographicDetail detail) =>
      '$infographicJsonSchemaPrompt\n${infographicDetailPrompt(detail)}';

  static const _taskLead =
      'armar una infografía —una lámina para estudiar de un vistazo— con lo '
      'más importante del material: un título, bloques del tipo que mejor '
      'cuente cada cosa, ordenados de lo más importante a lo de apoyo, y una '
      'idea para llevarse';

  static const _partLead =
      'elegir, solo con esta parte del material, hasta $blocksPerPart bloques '
      'para una infografía sobre el material entero: los más valiosos de esta '
      'parte, cada uno del tipo que mejor lo cuente y con su nivel, y un '
      'título provisional';

  static const _mergeLead =
      'armar UNA infografía con los borradores parciales que se te dan —cada '
      'uno salió de una parte del material—: elegí los mejores bloques sin '
      'repetir ideas, ordenalos de lo más importante a lo de apoyo, ajustá '
      'sus niveles para la lámina entera y escribí un título, una bajada y '
      'una idea para llevarse que abarquen todo';

  /// La tarea de una infografía con [design], con ilustraciones o sin
  /// ([illustrations] es cuántas se van a dibujar como mucho).
  static String task(InfographicDesign design, {required int illustrations}) =>
      [
        _taskLead,
        _orientation(design.orientation),
        ..._style(design, illustrations: illustrations),
        _illustrations(design, illustrations: illustrations),
      ].join('. ');

  /// Lo que arma cada parte de un material largo: sus mejores bloques.
  static String partTask(
    InfographicDesign design, {
    required int illustrations,
  }) => [
    _partLead,
    _illustrations(design, illustrations: illustrations),
  ].join('. ');

  /// Lo que hace el paso de unir: elige y ordena los mejores bloques de
  /// todas las partes.
  static String mergeTask(
    InfographicDesign design, {
    required int illustrations,
  }) => [
    _mergeLead,
    _orientation(design.orientation),
    ..._style(design, illustrations: illustrations),
    _illustrations(design, illustrations: illustrations),
  ].join('. ');

  /// Lee la respuesta final; un `FormatException` con el porqué hace que se
  /// le pida a la IA que la corrija (una sola vez).
  static Infographic parse(Object? json) {
    final sheet = InfographicJson.tryDecode(json);
    if (sheet == null) {
      throw const FormatException('no hay ningún bloque legible en "blocks"');
    }
    if (sheet.blocks.length < 2) {
      throw const FormatException('hacen falta al menos 4 bloques en "blocks"');
    }
    return sheet;
  }

  /// Lee el borrador de una parte: alcanza con un bloque.
  static Infographic parsePart(Object? json) {
    final sheet = InfographicJson.tryDecode(json);
    if (sheet == null) {
      throw const FormatException('no hay ningún bloque legible en "blocks"');
    }
    return sheet;
  }

  static String _orientation(InfographicOrientation orientation) =>
      switch (orientation) {
        InfographicOrientation.portrait =>
          'La lámina es vertical, para leerla en el teléfono de arriba abajo',
        InfographicOrientation.landscape =>
          'La lámina es horizontal, para leerla de izquierda a derecha',
        InfographicOrientation.square =>
          'La lámina es cuadrada: preferí pocos bloques bien repartidos',
      };

  static List<String> _style(
    InfographicDesign design, {
    required int illustrations,
  }) {
    // Con un estilo elegido, la sugerencia de la IA no decide nada ahora; se
    // la deja sugerir igual, por si después se pasa a «Automático».
    if (design.style == InfographicStyleId.auto && illustrations > 0) {
      final illustrated = [
        for (final style in InfographicStyleId.values)
          if (style.isIllustrated) '"${style.id}"',
      ].join(', ');
      final hint =
          'Para "style_hint" elegí uno de los estilos con ilustraciones '
          '($illustrated), el que mejor vaya con el tema';
      return [hint];
    }
    return const [];
  }

  static String _illustrations(
    InfographicDesign design, {
    required int illustrations,
  }) {
    if (illustrations <= 0) {
      return 'No escribas "illustration_prompt": esta lámina va sin '
          'ilustraciones';
    }
    final everyBlock =
        design.style == InfographicStyleId.auto || design.style.isIllustrated;
    if (everyBlock) {
      return 'Escribí "illustration_prompt" en la cabecera y en cada bloque '
          '"fact", "concept", "step" o "event": una escena concreta y '
          'dibujable, en una oración, sin letras ni números';
    }
    final drawn = infographicDrawnIllustrations(design.detail);
    return 'Escribí "illustration_prompt" solo en los $drawn bloques "fact", '
        '"concept", "step" o "event" que más ganen con un dibujo: una escena '
        'concreta, en una oración, sin letras ni números';
  }
}
