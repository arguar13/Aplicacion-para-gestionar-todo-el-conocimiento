import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// Una imagen con pellizco para acercar — lo mismo que cualquier galería
/// nativa.
///
/// Sin `Scaffold` propio a propósito: el marco de lectura la pone como
/// cuerpo a pantalla completa (`ImageViewerScreen`), y `EmbeddedFileViewer`
/// la embebe tal cual dentro de un marco acotado en el detalle del elemento.
/// En el marco, además, le deja el zoom a «Apariencia» (F47, paso 1).
class ImageViewerView extends StatefulWidget {
  const ImageViewerView({required this.path, super.key});

  final String path;

  /// Lo más y lo menos que se acerca.
  static const minScale = 0.5;
  static const maxScale = 4.0;

  @override
  State<ImageViewerView> createState() => _ImageViewerViewState();
}

class _ImageViewerViewState extends State<ImageViewerView> {
  final _transform = TransformationController();
  late final _zoom = _ImageZoom(_transform, () => _size);
  ReadingFrameController? _frame;

  /// El tamaño de la vista, para acercar desde el centro.
  Size _size = Size.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frame = ReadingFrameController.maybeOf(context);
    if (identical(frame, _frame)) return;
    _frame = frame;
    // Después del cuadro: avisarle al marco mientras se construye no se puede.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) frame?.zoom = _zoom;
    });
  }

  @override
  void dispose() {
    _frame?.dropZoom(_zoom);
    _zoom.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return InteractiveViewer(
          transformationController: _transform,
          minScale: ImageViewerView.minScale,
          maxScale: ImageViewerView.maxScale,
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            // Una imagen que se borró del disco después de indexarse, o que
            // el archivo no es la imagen válida que su extensión promete: un
            // ícono roto sigue siendo mejor que una excepción sin atrapar que
            // se lleva puesto el resto de la pantalla.
            errorBuilder: (context, error, stackTrace) => Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// El zoom de una imagen para «Apariencia»: cuánto se acercó, y acercar o
/// alejar de a un cuarto desde el centro de lo que se ve.
class _ImageZoom implements ReadingZoom {
  _ImageZoom(this._transform, this._size) {
    _transform.addListener(_update);
  }

  final TransformationController _transform;
  final Size Function() _size;

  /// Cuánto cambia cada toque.
  static const _step = 1.25;

  @override
  final ValueNotifier<double> level = ValueNotifier(1);

  void _update() => level.value = _transform.value.getMaxScaleOnAxis();

  void _scaleBy(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(
      ImageViewerView.minScale,
      ImageViewerView.maxScale,
    );
    final size = _size();
    final center = _transform.toScene(size.center(Offset.zero));
    final scale = target / current;
    _transform.value = _transform.value.clone()
      ..translateByVector3(Vector3(center.dx, center.dy, 0))
      ..scaleByVector3(Vector3(scale, scale, 1))
      ..translateByVector3(Vector3(-center.dx, -center.dy, 0));
  }

  @override
  void zoomIn() => _scaleBy(_step);

  @override
  void zoomOut() => _scaleBy(1 / _step);

  @override
  void fit() => _transform.value = Matrix4.identity();

  void dispose() {
    _transform.removeListener(_update);
    level.dispose();
  }
}
