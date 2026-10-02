import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';

/// El modo de lectura a pantalla completa, con su propia barra de título.
///
/// Envoltorio delgado sobre [DocumentReaderView]: todo el lector de verdad
/// vive ahí, para poder embeberlo también directo en el detalle de un
/// elemento sin pasar por esta pantalla ni por `Navigator`. Acá se activan
/// los controles de tamaño de letra —[DocumentReaderView.showFontControls]—
/// porque hay lugar de sobra; embebido no, para no recargar un fragmento
/// pensado para mirar de pasada.
class DocumentReaderScreen extends StatelessWidget {
  const DocumentReaderScreen({
    required this.title,
    required this.content,
    this.markdown = true,
    super.key,
  });

  final String title;
  final String content;

  /// Ver `TextResolvedViewer.markdown`.
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: DocumentReaderView(
          title: title,
          content: content,
          markdown: markdown,
          showFontControls: true,
          controlsAtBottom: true,
        ),
      ),
    );
  }
}
