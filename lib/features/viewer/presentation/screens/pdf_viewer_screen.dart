import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';

/// El PDF a pantalla completa, con su propia barra de título.
///
/// Envoltorio delgado sobre [PdfViewerView]: todo el visor de verdad vive
/// ahí, para poder embeberlo también directo en el detalle de un elemento
/// —ver `EmbeddedFileViewer`— sin pasar por esta pantalla ni por
/// `Navigator`.
class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({required this.path, required this.title, super.key});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: PdfViewerView(path: path),
    );
  }
}
