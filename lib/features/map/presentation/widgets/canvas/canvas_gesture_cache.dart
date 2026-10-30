import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:sinapsis/features/map/presentation/widgets/arrow_head.dart';

/// Cuánto puede cambiar el zoom desde que se capturó la imagen antes de que se
/// vea inaceptablemente borrosa: a partir de acá se recaptura una vez a mitad
/// del gesto (F18, 18.2).
const kMaxSnapshotZoomChange = 2.0;

/// El caché de rasterizado del lienzo durante un gesto (F18, 18.2).
///
/// Al empezar un arrastre o un zoom se captura lo ya dibujado y, mientras dura
/// el gesto, el lienzo pinta esa imagen en vez de su dibujo: moverla es mucho
/// más barato que recorrer cientos de nodos en cada cuadro. Al soltar se
/// descarta y vuelve el dibujo vectorial de siempre, idéntico, porque la imagen
/// es una captura exacta de esa misma caja.
///
/// Un `ui.Image` vivo a la vez: el anterior se libera recién después de que el
/// cuadro siguiente —que ya no lo usa— se pintó.
class CanvasGestureCache {
  CanvasGestureCache({required this.boundaryKey, required this.onChanged});

  /// La caja cuyo dibujo se captura.
  final GlobalKey boundaryKey;

  /// Avisa que cambió [image]: quien lo usa vuelve a dibujar.
  final VoidCallback onChanged;

  /// Lo capturado; `null` fuera de un gesto, o si la captura falló.
  ui.Image? get image => _image;
  ui.Image? _image;

  /// El zoom con el que se capturó [image].
  double _scale = 1;

  /// Si hay un gesto en curso: una captura que resuelve con el gesto ya
  /// terminado se descarta sin mostrarla.
  bool _gesturing = false;

  bool _disposed = false;

  /// Empieza un gesto: captura lo dibujado. [scale] dice el zoom de ese
  /// momento, que se lee cuando la captura llega.
  void start({required double pixelRatio, required double Function() scale}) {
    _gesturing = true;
    unawaited(_capture(pixelRatio, scale));
  }

  /// Mientras dura el gesto: si el zoom ya cambió demasiado desde la última
  /// captura, recaptura una vez para que la imagen no se vea borrosa. Un
  /// arrastre puro no cambia el zoom, así que no recaptura nada.
  void update({required double pixelRatio, required double Function() scale}) {
    if (_image == null) return;
    final change = scale() / _scale;
    if (change > kMaxSnapshotZoomChange ||
        change < 1 / kMaxSnapshotZoomChange) {
      unawaited(_capture(pixelRatio, scale));
    }
  }

  /// Terminó el gesto: vuelve el dibujo de siempre.
  void end() {
    _gesturing = false;
    _replace(null);
  }

  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
  }

  /// Si algo falla —sin tamaño todavía, o lo que sea—, no pasa nada: sin
  /// captura, el dibujo sigue siendo el vectorial de siempre.
  Future<void> _capture(double pixelRatio, double Function() scale) async {
    ui.Image? image;
    try {
      image = await captureBoundaryImage(boundaryKey, pixelRatio: pixelRatio);
      // Cualquier falla acá degrada al dibujo vectorial de siempre, no
      // rompe la vista: no hace falta distinguir el tipo de excepción.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return;
    }
    // El gesto ya terminó mientras la captura estaba en camino: esta imagen
    // ya no le corresponde a nada, se descarta sin mostrarla.
    if (image == null || _disposed || !_gesturing) {
      image?.dispose();
      return;
    }
    _scale = scale();
    _replace(image);
  }

  void _replace(ui.Image? next) {
    final previous = _image;
    if (identical(previous, next)) return;
    _image = next;
    onChanged();
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }
}
