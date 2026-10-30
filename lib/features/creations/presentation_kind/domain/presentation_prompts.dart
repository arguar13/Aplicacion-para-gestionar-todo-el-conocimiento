import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_schema_prompt.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';

/// Lo que se le pide a la IA para una presentación (F43, paso 11): la tarea,
/// la de cada parte y la de unir, con lo que eligió la persona. El esquema
/// es `slideDeckJsonSchemaPrompt`; esto dice cuántas diapositivas, en qué
/// orden, en qué formato, cuántas ilustraciones pedir y, en «Automática»,
/// que elija la plantilla.
///
/// En español y en infinitivo, como lo arma `structuredInstruction`: «Tu
/// única tarea es armar…».
abstract final class PresentationPrompts {
  /// La tarea de una sola vez: el mazo entero.
  static String task(PresentationOptions o) =>
      'armar una presentación de diapositivas sobre el material, de unas '
      '${o.slideTarget} diapositivas (entre ${o.slideTarget - 2} y '
      '${o.slideTarget + 2}), que cuente sus ideas en el orden del material: '
      'una portada ("cover") primero; un comienzo de sección ("section") '
      'si el material tiene partes; el contenido, cada idea con el diseño que '
      'mejor la cuente; y un cierre ("closing") al final con lo que hay que '
      'llevarse. ${_common(o)}';

  /// La tarea de cada parte, por partes: sus diapositivas, sin portada ni
  /// cierre —esos los arma el paso de unir—.
  static String partTask(PresentationOptions o) =>
      'armar el borrador de las diapositivas de esta parte del material: de 3 '
      'a 6 diapositivas con sus ideas principales, en orden, sin portada ni '
      'cierre, cada una con el diseño que mejor la cuente. '
      '${slideDeckFormatPrompt(o.format)} ${_illustrationRule(o, parts: true)}';

  /// La de unir: el relato final, de la portada al cierre.
  static String mergeTask(PresentationOptions o) =>
      'unir en una sola presentación de unas ${o.slideTarget} diapositivas '
      '(entre ${o.slideTarget - 2} y ${o.slideTarget + 2}) los borradores '
      'que se te dan —cada uno salió de una parte del material, en orden—: '
      'una portada ("cover") primero; las ideas más importantes en el orden '
      'del material, sin repetir, con un comienzo de sección ("section") '
      'donde cambia la parte; y un cierre ("closing") al final con lo que hay '
      'que llevarse. Elegí las mejores diapositivas, reescribí las que haga '
      'falta para que el relato fluya y conservá sus "speaker_notes". '
      '${_common(o)}';

  static String _common(PresentationOptions o) => [
    slideDeckFormatPrompt(o.format),
    _illustrationRule(o),
    if (o.template == null) _templateRule,
  ].join(' ');

  /// Las ilustraciones se piden aunque estén apagadas: la app dibuja en su
  /// lugar una composición con los colores de la plantilla, y se pueden
  /// sumar después con «Completar ilustraciones».
  static String _illustrationRule(
    PresentationOptions o, {
    bool parts = false,
  }) => parts
      ? 'Poné "illustration_prompt" solo en la diapositiva de esta parte '
            'donde una imagen ayude más, o en ninguna.'
      : 'Poné "illustration_prompt" en unas ${o.maxIllustrations} '
            'diapositivas —la portada incluida—, solo donde una imagen ayude '
            'de verdad; en las demás, nada.';

  static const _templateRule =
      'Sumá al objeto de arriba, junto a "title", la clave "template" con la '
      'plantilla que mejor le va al tema y al tono del material, una de: '
      'editorial (sobria, de revista), parchment (histórica, clásica), '
      'academic (de estudio, académica), newspaper (periodística, de '
      'actualidad), ink (serena, oriental), swiss (moderna, geométrica), '
      'bento (amable, ordenada), aurora (suave, inspiradora), glass '
      '(tecnológica, liviana), magazine (vistosa, de revista), bauhaus '
      '(artística, de diseño), brutalist (audaz, cruda), midnight (oscura, '
      'elegante), neon (tecnológica, nocturna), chalkboard (de clase, '
      'didáctica), dark_minimal (oscura, sobria), terminal (de programación, '
      'informática), art_deco (de época, lujosa), watercolor (artística, '
      'natural), pastel (para chicos, liviana), paper_cut (creativa, '
      'manual), retro (nostálgica, cálida), manuscript (de apuntes, '
      'personal), whiteboard (de taller, explicativa), corporate (de '
      'empresa), data (de cifras y datos), executive (de negocios, sobria), '
      'blueprint (técnica, de ingeniería).';
}
