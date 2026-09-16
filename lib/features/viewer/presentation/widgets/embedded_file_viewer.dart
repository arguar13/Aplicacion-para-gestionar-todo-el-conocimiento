import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/open_document_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El archivo original de un elemento, visible directo en su detalle — sin
/// tener que tocar un botón "Ver" para recién ahí abrirlo.
///
/// Solo para las formas de archivo que **agregan algo** sobre el texto que
/// el detalle ya muestra más abajo: una foto, un video, un audio, un PDF con
/// su maquetación de verdad, la página web archivada con sus imágenes en su
/// lugar. Un DOCX o un EPUB no entran acá —`resolvedFileViewerProvider`
/// resuelve esos como `TextResolvedViewer`, y esta clase no dibuja nada para
/// ese caso— porque su contenido extraído es exactamente lo que ya se lee
/// en el cuerpo del detalle; embeber además el modo de lectura paginado
/// mostraría lo mismo dos veces. Ese modo de lectura sigue estando a un
/// toque —ver el enlace "Modo lectura" en `_TextRenditionView`— para quien
/// prefiera la tipografía grande y el paginado a un libro entero, que es un
/// beneficio real y no solo repetir el mismo texto con otro formato.
///
/// Ocupa un marco de alto acotado, no lo que le haga falta: un PDF o un
/// video no tienen por qué apoderarse de la pantalla del detalle, y cada
/// visor —`PdfViewerView`, `MediaPlayerView`— ya sabe manejarse dentro de
/// cualquier alto que se le dé, con su propio scroll o paginado por dentro.
/// Quien quiera más lugar toca el botón de expandir, que lleva a la misma
/// pantalla completa que abriría el viejo botón "Ver" — ver
/// `openDocumentViewer`.
class EmbeddedFileViewer extends ConsumerWidget {
  const EmbeddedFileViewer({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Los visores de acá adentro leen el archivo directo del disco
    // (`dart:io`): no tienen con qué trabajar en la web, donde el almacén
    // vive en OPFS y no hay una ruta de archivo real que abrir. Ahí "Abrir
    // con..." —ver `_Provenance`— sigue siendo el único camino.
    if (kIsWeb) return const SizedBox.shrink();

    // Una nota manual no tiene archivo original del que hablar.
    if (item.source.kind == SourceKind.manualNote) {
      return const SizedBox.shrink();
    }
    if (item.source.originalFilePath == null) return const SizedBox.shrink();

    final resolved = ref.watch(resolvedFileViewerProvider(item));

    return switch (resolved) {
      AsyncData(:final value) => _buildFrame(context, ref, value),
      AsyncError() => const SizedBox.shrink(),
      _ => const _EmbeddedViewerFrame(
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }

  Widget _buildFrame(
    BuildContext context,
    WidgetRef ref,
    ResolvedViewer resolved,
  ) {
    void expand() => openDocumentViewer(context, ref, item);

    return switch (resolved) {
      NoResolvedViewer() || TextResolvedViewer() => const SizedBox.shrink(),
      ImageResolvedViewer(:final path) => _EmbeddedViewerFrame(
        onExpand: expand,
        child: ImageViewerView(path: path),
      ),
      MediaResolvedViewer(:final path, :final isVideo) => _EmbeddedViewerFrame(
        onExpand: expand,
        child: MediaPlayerView(path: path, isVideo: isVideo),
      ),
      PdfResolvedViewer(:final path) => _EmbeddedViewerFrame(
        tall: true,
        onExpand: expand,
        child: PdfViewerView(path: path),
      ),
      WebPageResolvedViewer(:final path) => _EmbeddedViewerFrame(
        tall: true,
        onExpand: expand,
        child: WebPageViewerView(path: path),
      ),
    };
  }
}

/// El marco acotado —esquinas redondeadas, borde tenue— que envuelve
/// cualquier visor embebido, con el botón de expandir a pantalla completa
/// flotando en la esquina.
class _EmbeddedViewerFrame extends StatelessWidget {
  const _EmbeddedViewerFrame({
    required this.child,
    this.onExpand,
    this.tall = false,
  });

  final Widget child;
  final VoidCallback? onExpand;

  /// Un PDF o el modo de lectura se leen mejor con más alto que una foto o
  /// un video, que ya se acomodan solos a su propia relación de aspecto.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final height = (viewportHeight * (tall ? 0.62 : 0.4)).clamp(260.0, 720.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              if (onExpand != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _ExpandButton(
                    tooltip: l10n.detailExpandViewer,
                    onPressed: onExpand!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.open_in_full, size: 18),
        color: Colors.white,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
