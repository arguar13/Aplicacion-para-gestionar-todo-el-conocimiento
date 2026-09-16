import 'dart:io';

import 'package:flutter/material.dart';

/// Una imagen con pellizco para acercar — lo mismo que cualquier galería
/// nativa.
///
/// Sin `Scaffold` propio a propósito: `ImageViewerScreen` lo envuelve para
/// mostrarla a pantalla completa, y `EmbeddedFileViewer` la embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class ImageViewerView extends StatelessWidget {
  const ImageViewerView({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        // Una imagen que se borró del disco después de indexarse, o que el
        // archivo no es la imagen válida que su extensión promete: un
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
  }
}
