import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_pane.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_target.dart';

/// Adónde lleva en el lienzo lo que se toca en el Resumen (F44, paso 3,
/// decisión D): cada destino, el pedido del canal del lienzo que le toca.
void main() {
  test('un documento: lo vinculado, con él en foco', () {
    final request = canvasRequestFor(const MapBoardItem('d1'));

    expect(request, isA<MapShowLinks>());
    expect((request as MapShowLinks).focusId, 'd1');
  });

  test('un tema: los de su comunidad, con él resaltado', () {
    final request = canvasRequestFor(const MapBoardTopic('roma'));

    expect(request, isA<MapShowTopic>());
    expect((request as MapShowTopic).valueId, 'roma');
  });

  test('cada cifra, a su altura; los vínculos, a lo vinculado sin foco', () {
    MapAltitude? altitudeOf(MapBoardFigure figure) =>
        switch (canvasRequestFor(MapBoardLevel(figure))) {
          MapShowAltitude(:final altitude) => altitude,
          _ => null,
        };

    expect(altitudeOf(MapBoardFigure.communities), MapAltitude.communities);
    expect(altitudeOf(MapBoardFigure.topics), MapAltitude.topics);
    expect(altitudeOf(MapBoardFigure.documents), MapAltitude.documents);
    final links = canvasRequestFor(const MapBoardLevel(MapBoardFigure.links));
    expect(links, isA<MapShowLinks>());
    expect((links as MapShowLinks).focusId, isNull);
  });
}
