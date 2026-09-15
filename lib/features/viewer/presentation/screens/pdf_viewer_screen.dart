import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// El PDF, paginado y con zoom, igual que cualquier lector nativo —Adobe
/// Reader, el visor del sistema—.
///
/// `pdfrx` es el mismo PDFium que ya usa `PdfParser` para extraer texto
/// (ver `pdfrx_engine` en `pubspec.yaml`), con el widget de lectura
/// completo encima: nada de "abrir con otra app" para algo tan básico como
/// mirar un PDF que ya está guardado en la bóveda.
class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({required this.path, required this.title, super.key});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: PdfViewer.file(
        path,
        params: PdfViewerParams(
          // Un fondo neutro entre página y página, para que se distinga
          // dónde termina una y empieza la otra al scrollear — lo mismo
          // que hace cualquier lector de PDF de verdad.
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
      ),
    );
  }
}
