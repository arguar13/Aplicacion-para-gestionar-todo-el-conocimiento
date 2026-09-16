import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// El PDF, paginado y con zoom, igual que cualquier lector nativo —Adobe
/// Reader, el visor del sistema—.
///
/// `pdfrx` es el mismo PDFium que ya usa `PdfParser` para extraer texto (ver
/// `pdfrx_engine` en `pubspec.yaml`), con el widget de lectura completo
/// encima. Renderiza página por página bajo demanda —no carga el documento
/// entero en memoria de una vez—, así que abrir un PDF de mil páginas cuesta
/// lo mismo que uno de diez: se puede embeber directo en el detalle de un
/// elemento sin distinguir "vista previa" de "el visor de verdad", los dos
/// son el mismo widget.
///
/// Sin `Scaffold` propio a propósito: `PdfViewerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class PdfViewerView extends StatelessWidget {
  const PdfViewerView({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(
      path,
      params: PdfViewerParams(
        // Un fondo neutro entre página y página, para que se distinga
        // dónde termina una y empieza la otra al scrollear — lo mismo que
        // hace cualquier lector de PDF de verdad.
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
    );
  }
}
