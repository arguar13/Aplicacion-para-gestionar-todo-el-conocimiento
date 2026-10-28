import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_images_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_gallery.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/stored_image.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre a pantalla completa las imágenes del documento [documentId],
/// empezando por la [initialIndex].
Future<void> openProcessedImageViewer(
  BuildContext context, {
  required String documentId,
  required int initialIndex,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ProcessedImageViewerScreen(
      documentId: documentId,
      initialIndex: initialIndex,
    ),
  ),
);

/// Las imágenes de un documento procesado a pantalla completa (F41, decisión
/// L): con pellizco para acercar, deslizando —o con las flechas— para pasar
/// de una a otra, y «Quitar» con «Deshacer».
///
/// La lista que se recorre es solo la de sus filas —ruta, nombre, peso—, y
/// cada imagen se abre recién cuando se mira: la de al lado no se decodifica
/// hasta que se llega a ella. Sin animaciones, pasar de una a otra es un
/// salto.
class ProcessedImageViewerScreen extends ConsumerStatefulWidget {
  const ProcessedImageViewerScreen({
    required this.documentId,
    required this.initialIndex,
    super.key,
  });

  final String documentId;
  final int initialIndex;

  @override
  ConsumerState<ProcessedImageViewerScreen> createState() =>
      _ProcessedImageViewerScreenState();
}

class _ProcessedImageViewerScreenState
    extends ConsumerState<ProcessedImageViewerScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index, int count) {
    if (index < 0 || index >= count) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      unawaited(
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final images = ref
        .watch(
          processedImagesProvider((
            documentId: widget.documentId,
            offset: 0,
            limit: null,
          )),
        )
        .valueOrNull;

    if (images != null && images.isEmpty) {
      // Se quitó la última: no queda nada que mirar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    final count = images?.length ?? 0;
    final index = count == 0 ? 0 : _index.clamp(0, count - 1);
    final current = images == null || count == 0 ? null : images[index];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(index + 1, count),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(index - 1, count),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        if (current != null) ...{
          const SingleActivator(LogicalKeyboardKey.delete): () =>
              unawaited(removeProcessedImage(context, ref, current)),
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 0
                      ? ''
                      : l10n.processedImagePosition(index + 1, count),
                  key: const Key('processed-image-viewer-position'),
                ),
                if (current?.title case final title?)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l10n.processedImagePrevious,
                onPressed: index > 0 ? () => _go(index - 1, count) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: l10n.processedImageNext,
                onPressed: index < count - 1
                    ? () => _go(index + 1, count)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                key: const Key('processed-image-remove'),
                tooltip: l10n.processedImageRemove,
                onPressed: current == null
                    ? null
                    : () => unawaited(
                        removeProcessedImage(context, ref, current),
                      ),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: images == null
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  controller: _pages,
                  itemCount: count,
                  onPageChanged: (page) => setState(() => _index = page),
                  itemBuilder: (context, page) => _ViewerPage(
                    key: ValueKey(images[page].renditionId),
                    image: images[page],
                    label: l10n.processedImagePosition(page + 1, count),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Una imagen entera, con zoom: la del disco por su ruta, o sus bytes donde
/// no hay disco.
class _ViewerPage extends ConsumerWidget {
  const _ViewerPage({required this.image, required this.label, super.key});

  final ProcessedImage image;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(storedImageSourceProvider(image.relativePath));
    return Semantics(
      image: true,
      label: image.title == null ? label : '$label: ${image.title}',
      child: switch (source.valueOrNull) {
        StoredImageFile(:final path) => ImageViewerView(path: path),
        StoredImageBytes(:final bytes) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) =>
                const StoredImagePlaceholder(broken: true),
          ),
        ),
        null when source.isLoading => const Center(
          child: CircularProgressIndicator(),
        ),
        null => const StoredImagePlaceholder(broken: true),
      },
    );
  }
}
