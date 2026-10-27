import 'package:flutter/material.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';

/// El PDF a pantalla completa, con su propia barra de título.
///
/// Envoltorio delgado sobre [PdfViewerView]: todo el visor de verdad vive
/// ahí, para poder embeberlo también directo en el detalle de un elemento
/// —ver `EmbeddedFileViewer`— sin pasar por esta pantalla ni por
/// `Navigator`.
class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({
    required this.path,
    required this.title,
    this.text,
    super.key,
  });

  final String path;
  final String title;

  /// Su texto extraído, para pintar lo estudiado (F36).
  final StudyText? text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      // Con lo que se estudia, arriba sus botones, como en el lector (F36).
      body: Column(
        children: [
          if (text case final text?) StudyBar(text: text),
          Expanded(
            child: PdfViewerView(path: path, text: text, title: title),
          ),
        ],
      ),
    );
  }
}
