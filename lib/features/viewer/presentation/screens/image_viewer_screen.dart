import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';

/// Una imagen a pantalla completa, con su propia barra de título.
///
/// Envoltorio delgado sobre [ImageViewerView]: todo el visor de verdad vive
/// ahí, para poder embeberlo también directo en el detalle de un elemento
/// —ver `EmbeddedFileViewer`— sin pasar por esta pantalla ni por
/// `Navigator`.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({required this.path, required this.title, super.key});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: ImageViewerView(path: path),
    );
  }
}
