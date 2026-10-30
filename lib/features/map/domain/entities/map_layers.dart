import 'package:meta/meta.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';

/// Las capas del lienzo del Mapa (F44, paso 5): lo que se prende encima de lo
/// que se mira, varias a la vez.
///
/// Ninguna cambia qué se mira ni dónde queda cada nodo: agregan o sacan lo que
/// se dibuja de lo que ya está acomodado. Prender o apagar una no recalcula el
/// layout ni vuelve a leer la base de lo que ya se tiene.
enum MapLayer {
  /// Las uniones entre documentos —con su tipo y su flecha—, donde se dibujan
  /// documentos: los de un tema, los sin tema y lo vinculado, con su filtro de
  /// fuerza. Es lo que era el botón de cadena (F44, paso 2) y, antes, la
  /// pestaña «Vínculos» (F28).
  links,

  /// La burbuja gris con los documentos sin ningún valor de lo que se mira:
  /// de lejos, un nodo más; al entrar, sus documentos.
  unthemed,

  /// Las uniones en tensión —las contradicciones, o lo que junta alguna—, en
  /// rojo y con su rayo. Apagada, se dibujan como las demás.
  tensions,

  /// Las líneas punteadas entre documentos que hablan de lo mismo y no están
  /// vinculados, con los vectores que ya guarda el teléfono (F30). Propone y
  /// la persona confirma: nunca vincula sola.
  similar,

  /// Cada documento teñido según su estudio: sin tarjetas, con tarjetas para
  /// hoy o al día.
  study,
}

/// Con qué capas arranca el Mapa (decisión B): un mapa limpio primero, y lo
/// demás a pedido. Solo «Vínculos», que al nivel de los documentos es lo que
/// se veía siempre.
const kDefaultMapLayers = {MapLayer.links};

/// Cómo va el estudio de un documento, para la capa «Estudio».
enum MapStudyState {
  /// No tiene tarjetas: ni las suyas ni las de su fuente.
  none,

  /// Tiene tarjetas que tocan hoy.
  due,

  /// Tiene tarjetas y ninguna toca hoy.
  upToDate,
}

/// Lo que la capa «Estudio» dice de un documento: su estado y, si tiene
/// tarjetas para hoy, cuántas.
@immutable
class MapStudyMark {
  const MapStudyMark(this.state, {this.due = 0});

  /// El de un documento con las tarjetas [cards] —las que lee el Resumen,
  /// `BoardCardFact`, o `null` si no tiene ninguna—.
  factory MapStudyMark.of(BoardCardFact? cards) {
    if (cards == null || cards.cards == 0) {
      return const MapStudyMark(MapStudyState.none);
    }
    return cards.dueToday > 0
        ? MapStudyMark(MapStudyState.due, due: cards.dueToday)
        : const MapStudyMark(MapStudyState.upToDate);
  }

  final MapStudyState state;

  /// Cuántas tarjetas tocan hoy; 0 si no es [MapStudyState.due].
  final int due;

  @override
  bool operator ==(Object other) =>
      other is MapStudyMark && other.state == state && other.due == due;

  @override
  int get hashCode => Object.hash(state, due);
}
