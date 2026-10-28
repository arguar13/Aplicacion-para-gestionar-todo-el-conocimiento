import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';

/// Dónde leer una imagen guardada: su ruta en el disco o, donde no hay disco
/// (la web), sus bytes.
sealed class StoredImageSource {
  const StoredImageSource();
}

final class StoredImageFile extends StoredImageSource {
  const StoredImageFile(this.path);
  final String path;
}

final class StoredImageBytes extends StoredImageSource {
  const StoredImageBytes(this.bytes);
  final Uint8List bytes;
}

/// De dónde se lee la imagen guardada en una ruta relativa al almacén, o
/// `null` si ya no está. En el disco no pasa por Dart: `Image.file` la abre
/// directo.
final storedImageSourceProvider = FutureProvider.autoDispose
    .family<StoredImageSource?, String>((ref, relativePath) async {
      final files = ref.watch(fileStoreProvider);
      final local = await files.localPathOf(relativePath);
      if (local != null) return StoredImageFile(local);
      final bytes = await files.read(relativePath);
      return bytes == null ? null : StoredImageBytes(bytes);
    });

/// Una imagen guardada en el almacén, recortada para cubrir su recuadro
/// (F41, decisión L): las miniaturas de la grilla de la hoja y de la galería.
///
/// **Se decodifica al tamaño en que se ve** ([decodeWidth]), nunca entera:
/// una foto de 12 megapíxeles son 48 MB de memoria, y una grilla de sesenta
/// las tendría a todas. Lo que no se puede leer —el archivo ya no está, o no
/// es la imagen que su extensión promete— se ve como un ícono, sin romper la
/// grilla.
class StoredImage extends ConsumerWidget {
  const StoredImage({
    required this.relativePath,
    required this.decodeWidth,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String relativePath;

  /// El ancho, en píxeles, al que se decodifica.
  final int decodeWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(storedImageSourceProvider(relativePath));
    return switch (source.valueOrNull) {
      StoredImageFile(:final path) => Image.file(
        File(path),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: decodeWidth,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const StoredImagePlaceholder(broken: true),
      ),
      StoredImageBytes(:final bytes) => Image.memory(
        bytes,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: decodeWidth,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const StoredImagePlaceholder(broken: true),
      ),
      null => StoredImagePlaceholder(broken: source.hasValue),
    };
  }
}

/// Lo que se ve en el lugar de una imagen mientras se busca, o si no se pudo
/// leer ([broken]).
class StoredImagePlaceholder extends StatelessWidget {
  const StoredImagePlaceholder({this.broken = false, super.key});

  final bool broken;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          broken ? Icons.broken_image_outlined : Icons.image_outlined,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
