import 'dart:io';

import 'package:flutter/material.dart';

/// Una imagen a pantalla completa, con pellizco para acercar — lo mismo que
/// cualquier galería nativa, en vez de la miniatura chica que quedaba
/// embebida en el detalle del elemento.
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
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
