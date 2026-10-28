import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/thumbnail_decode.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_images_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_viewer.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/stored_image.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/triage_image_grid.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La galería de un documento procesado (F41, decisión L): sus imágenes en
/// miniatura, de a tandas. Tocar una la abre a pantalla completa
/// ([ProcessedImageViewerScreen]), con zoom y para pasar de una a otra.
///
/// Cada una se quita con «Deshacer»: desde la pantalla completa, con la tecla
/// Suprimir sobre la miniatura enfocada, o con la acción «Quitar» del lector
/// de pantalla. Para sumar más está «Volver a triar».
class ProcessedImageGallery extends ConsumerStatefulWidget {
  const ProcessedImageGallery({
    required this.documentId,
    required this.count,
    super.key,
  });

  final String documentId;

  /// Cuántas tiene: lo que dice la sección, sin pedir la lista.
  final int count;

  /// Cuántas miniaturas se suman por tanda.
  static const pageSize = 60;

  @override
  ConsumerState<ProcessedImageGallery> createState() =>
      _ProcessedImageGalleryState();
}

class _ProcessedImageGalleryState extends ConsumerState<ProcessedImageGallery> {
  var _limit = ProcessedImageGallery.pageSize;
  List<ProcessedImage>? _shown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final images = ref.watch(
      processedImagesProvider((
        documentId: widget.documentId,
        offset: 0,
        limit: _limit,
      )),
    );
    // Mientras llega la tanda más larga se siguen viendo las de antes.
    if (images.valueOrNull case final loaded?) _shown = loaded;
    final list = _shown;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final remaining = widget.count - list.length;

    return Column(
      key: const Key('processed-image-gallery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 6.0;
            final columns = (constraints.maxWidth / 112).floor().clamp(2, 6);
            final side =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final decodeWidth = thumbnailDecodeWidth(context, side);
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final (index, image) in list.indexed)
                  _GalleryTile(
                    key: ValueKey(image.renditionId),
                    image: image,
                    label: imageTileLabel(
                      l10n,
                      index,
                      widget.count,
                      image.title,
                    ),
                    side: side,
                    decodeWidth: decodeWidth,
                    onOpen: () => unawaited(
                      openProcessedImageViewer(
                        context,
                        documentId: widget.documentId,
                        initialIndex: index,
                      ),
                    ),
                    onRemove: () =>
                        unawaited(removeProcessedImage(context, ref, image)),
                  ),
              ],
            );
          },
        ),
        if (remaining > 0 && list.length >= _limit)
          Align(
            child: TextButton(
              key: const Key('processed-images-more'),
              onPressed: () =>
                  setState(() => _limit += ProcessedImageGallery.pageSize),
              child: Text(l10n.processedTriageImagesMore(remaining)),
            ),
          ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.image,
    required this.label,
    required this.side,
    required this.decodeWidth,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  final ProcessedImage image;
  final String label;
  final double side;
  final int decodeWidth;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: side,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.delete): onRemove,
          const SingleActivator(LogicalKeyboardKey.backspace): onRemove,
        },
        child: Semantics(
          key: Key('processed-image-${image.renditionId}'),
          label: label,
          button: true,
          customSemanticsActions: {
            CustomSemanticsAction(label: l10n.processedImageRemove): onRemove,
          },
          child: Tooltip(
            message: image.title ?? label,
            excludeFromSemantics: true,
            child: Material(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: InkWell(
                onTap: onOpen,
                focusColor: scheme.primary.withValues(alpha: 0.3),
                child: StoredImage(
                  relativePath: image.relativePath,
                  decodeWidth: decodeWidth,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quita [image] de su documento procesado —su copia va a la papelera del
/// contenido— y ofrece «Deshacer», que la devuelve a su lugar. Devuelve si se
/// quitó.
Future<bool> removeProcessedImage(
  BuildContext context,
  WidgetRef ref,
  ProcessedImage image,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(processedRepositoryProvider);
  final removed = await repository.removeImage(image.renditionId);
  return removed.match(
    (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return false;
    },
    (removal) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.processedImageRemoved),
            action: SnackBarAction(
              label: l10n.trashUndo,
              onPressed: () async {
                final restored = await repository.restoreImage(removal);
                final failure = restored.getLeft().toNullable();
                if (failure != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(failure.localizedMessage(l10n))),
                  );
                }
              },
            ),
          ),
        );
      return true;
    },
  );
}
