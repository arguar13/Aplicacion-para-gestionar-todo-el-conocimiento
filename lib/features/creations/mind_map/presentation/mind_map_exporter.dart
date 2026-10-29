import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_rasterizer.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_canvas.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_scene.dart';

/// Guardar un mapa mental como imagen (F43: «exportar a imagen»).
///
/// Sale del mismo `MindMapCanvas` que se ve en pantalla, dibujado fuera de
/// pantalla con `CreationRasterizer`: la imagen es fiel por construcción —la
/// misma letra, los mismos colores del tema, las mismas curvas—. Va **el
/// árbol entero**, con todas las ramas abiertas y sin los «›», en PNG sin
/// pérdida.
///
/// La nitidez: [pixelRatio] píxeles por punto para un mapa normal —nítido
/// para imprimir o compartir—, menos si el mapa es enorme, para que la
/// imagen no pase de [maxPixels] ni de [maxSide] por lado (lo que una placa
/// de video y una app de fotos abren sin problema).
class MindMapExporter {
  const MindMapExporter();

  static const double pixelRatio = 3;
  static const double maxPixels = 32000000;
  static const double maxSide = 8192;

  /// La resolución con que sale un mapa de [size] puntos.
  static double ratioFor(Size size) {
    if (size.isEmpty) return pixelRatio;
    return [
      pixelRatio,
      math.sqrt(maxPixels / (size.width * size.height)),
      maxSide / math.max(size.width, size.height),
    ].reduce(math.min);
  }

  /// El PNG de [map] con los colores de [palette] y la letra de [metrics]
  /// (que va sin «›»: `interactive` apagado).
  Future<Uint8List> toPng({
    required MindMap map,
    required MindMapPalette palette,
    required MindMapMetrics metrics,
  }) async {
    final scene = MindMapScene.build(map, mindMapBranchIds(map), metrics);
    final image = await CreationRasterizer.render(
      ColoredBox(
        color: palette.background,
        child: MindMapCanvas(scene: scene, palette: palette, metrics: metrics),
      ),
      logicalSize: scene.size,
      pixelRatio: ratioFor(scene.size),
    );
    try {
      return await CreationRasterizer.toPng(image);
    } finally {
      image.dispose();
    }
  }
}
