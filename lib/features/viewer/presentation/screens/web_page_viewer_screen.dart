import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';

/// La página archivada a pantalla completa, con su propia barra de título.
///
/// Envoltorio delgado sobre [WebPageViewerView]: todo el visor de verdad
/// vive ahí, para poder embeberlo también directo en el detalle de un
/// elemento —ver `EmbeddedFileViewer`— sin pasar por esta pantalla ni por
/// `Navigator`.
class WebPageViewerScreen extends StatelessWidget {
  const WebPageViewerScreen({
    required this.path,
    required this.title,
    this.url,
    this.text,
    super.key,
  });

  final String path;
  final String title;

  /// La dirección de la página, para las fotos que no quedaron guardadas.
  final String? url;

  /// Su artículo extraído, para mostrar lo estudiado (F36).
  final StudyText? text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: WebPageViewerView(path: path, url: url, text: text),
    );
  }
}
