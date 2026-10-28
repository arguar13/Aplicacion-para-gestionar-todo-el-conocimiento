import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/thumbnail_decode.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_images_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/stored_image.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las imágenes de una fuente en la hoja «¿Qué va a Procesado?» (F41,
/// decisión L): «Todas», «Ninguna» y una grilla de miniaturas que se eligen
/// tocándolas, de a una.
///
/// - **De a tandas** ([pageSize]): se arman las que se muestran, más «Mostrar
///   más». Una fuente con trescientas fotos no arma trescientas miniaturas ni
///   las pide a la base.
/// - **En miniatura**: cada una se decodifica al tamaño en que se ve
///   ([StoredImage]), nunca entera.
/// - **Con el teclado**: cada miniatura se enfoca con Tab y se elige con
///   Enter o Espacio. Para el lector de pantalla, cada una dice cuál es, de
///   cuántas, y si está elegida.
/// - Sin animaciones: elegir cambia el borde y la marca de una vez.
class TriageImageGrid extends ConsumerStatefulWidget {
  const TriageImageGrid({
    required this.sourceItemId,
    required this.count,
    required this.choice,
    required this.onToggle,
    required this.onAll,
    required this.onNone,
    super.key,
  });

  final String sourceItemId;

  /// Cuántas imágenes ofrece la fuente.
  final int count;

  /// Lo elegido.
  final ImageChoice choice;

  /// Elegir o soltar la imagen de esa ruta.
  final ValueChanged<String> onToggle;
  final VoidCallback onAll;
  final VoidCallback onNone;

  /// Cuántas miniaturas se suman por tanda.
  static const pageSize = 60;

  @override
  ConsumerState<TriageImageGrid> createState() => _TriageImageGridState();
}

class _TriageImageGridState extends ConsumerState<TriageImageGrid> {
  var _pages = 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const pageSize = TriageImageGrid.pageSize;
    final shown = (_pages * pageSize).clamp(0, widget.count);
    final chosen = widget.choice.countOf(widget.count);

    return Column(
      key: const Key('triage-image-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.processedTriageImagesChosen(chosen, widget.count),
                key: const Key('triage-images-chosen'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            OutlinedButton(
              key: const Key('triage-images-all'),
              onPressed: chosen == widget.count ? null : widget.onAll,
              child: Text(l10n.processedTriageImagesAll),
            ),
            OutlinedButton(
              key: const Key('triage-images-none'),
              onPressed: chosen == 0 ? null : widget.onNone,
              child: Text(l10n.processedTriageImagesNone),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 6.0;
            final columns = (constraints.maxWidth / 104).floor().clamp(3, 6);
            final side =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final decodeWidth = thumbnailDecodeWidth(context, side);
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var page = 0; page * pageSize < shown; page++)
                  ..._page(page, shown, side, decodeWidth),
              ],
            );
          },
        ),
        if (shown < widget.count)
          Align(
            child: TextButton(
              key: const Key('triage-images-more'),
              onPressed: () => setState(() => _pages++),
              child: Text(l10n.processedTriageImagesMore(widget.count - shown)),
            ),
          ),
      ],
    );
  }

  /// Las miniaturas de la tanda [page]; mientras llega, su lugar.
  List<Widget> _page(int page, int shown, double side, int decodeWidth) {
    const pageSize = TriageImageGrid.pageSize;
    final offset = page * pageSize;
    final images = ref
        .watch(
          sourceImagesPageProvider((
            sourceItemId: widget.sourceItemId,
            offset: offset,
            limit: pageSize,
          )),
        )
        .valueOrNull;
    final expected = (shown - offset).clamp(0, pageSize);
    if (images == null) {
      return [
        for (var i = 0; i < expected; i++)
          SizedBox.square(
            dimension: side,
            child: const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              child: StoredImagePlaceholder(),
            ),
          ),
      ];
    }
    return [
      for (final (index, image) in images.indexed)
        _ImageTile(
          key: ValueKey(image.path),
          image: image,
          index: offset + index,
          count: widget.count,
          side: side,
          decodeWidth: decodeWidth,
          chosen: widget.choice.includes(image.path),
          onTap: () => widget.onToggle(image.path),
        ),
    ];
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.image,
    required this.index,
    required this.count,
    required this.side,
    required this.decodeWidth,
    required this.chosen,
    required this.onTap,
    super.key,
  });

  final SourceImage image;
  final int index;
  final int count;
  final double side;
  final int decodeWidth;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final label = imageTileLabel(l10n, index, count, image.title);

    return SizedBox.square(
      dimension: side,
      child: Semantics(
        key: Key('triage-image-${image.path}'),
        label: label,
        checked: chosen,
        button: true,
        child: Tooltip(
          message: image.title ?? label,
          excludeFromSemantics: true,
          child: Material(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: chosen
                  ? BorderSide(color: scheme.primary, width: 3)
                  : BorderSide(color: scheme.outlineVariant),
            ),
            child: InkWell(
              onTap: onTap,
              focusColor: scheme.primary.withValues(alpha: 0.3),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoredImage(
                    relativePath: image.path,
                    decodeWidth: decodeWidth,
                  ),
                  // La marca, arriba a la derecha: con un círculo vacío lo
                  // que no se eligió, para que se vea que se puede tocar.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: chosen ? scheme.primary : scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: chosen ? scheme.onPrimary : scheme.outline,
                          width: 1.5,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.check,
                          size: 16,
                          color: chosen ? scheme.onPrimary : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cómo se nombra la imagen [index] (desde 0) de [count] para el lector de
/// pantalla: su lugar y, si lo tiene, su nombre.
String imageTileLabel(
  AppLocalizations l10n,
  int index,
  int count,
  String? title,
) {
  final place = l10n.processedImagePosition(index + 1, count);
  return title == null ? place : '$place: $title';
}
