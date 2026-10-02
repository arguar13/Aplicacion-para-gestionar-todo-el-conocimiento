import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/open_document_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/youtube_embed_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El archivo original de un elemento, visible directo en su detalle — sin
/// tener que tocar ningún botón para recién ahí abrirlo.
///
/// Cada `SourceKind` con algo que mostrar se ve en su forma natural: una
/// foto o un video se ven como tales, un PDF con su maquetación de verdad,
/// la página web archivada con sus imágenes en su lugar, y un DOCX o un
/// EPUB con el mismo formato paginado y con tipografía de libro que ya
/// tenía el viejo "Modo lectura" —ver `DocumentReaderView`—, en vez del
/// texto corrido sin forma que se ve más abajo con `HighlightableText`.
/// Ese texto corrido sigue estando —es lo que permite subrayar y buscar—,
/// pero ya no es la única manera de leerlo: arriba se ve como el documento
/// que es. Un video de YouTube es la única excepción real: lo que se ve es
/// su miniatura, no un reproductor propio, porque lo que hay para mostrar
/// no es un archivo de este elemento sino el video original — ver
/// `YoutubeEmbedView`.
///
/// Ocupa un marco de alto acotado, no lo que le haga falta: un PDF o un
/// video no tienen por qué apoderarse de la pantalla del detalle, y cada
/// visor —`PdfViewerView`, `MediaPlayerView`, `DocumentReaderView`— ya sabe
/// manejarse dentro de cualquier alto que se le dé, con su propio scroll o
/// paginado por dentro. Quien quiera más lugar toca el botón de expandir,
/// que lleva a la misma pantalla completa que abriría el viejo botón "Ver"
/// — ver `openDocumentViewer`.
class EmbeddedFileViewer extends ConsumerWidget {
  const EmbeddedFileViewer({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Todos los visores salvo el de documentos y el de YouTube leen el
    // archivo directo del disco (`dart:io`): no tienen con qué trabajar en
    // la web, donde el almacén vive en OPFS y no hay una ruta de archivo
    // real que abrir. Los otros dos son la excepción —`DocumentReaderView`
    // solo necesita el contenido ya extraído, y la vista previa de YouTube
    // solo necesita la URL original, ninguno pide una ruta de archivo— así
    // que ahí sí vale la pena seguir adelante.
    if (kIsWeb &&
        item.source.kind != SourceKind.document &&
        item.source.kind != SourceKind.youtube) {
      return const SizedBox.shrink();
    }

    // Una nota manual no tiene archivo original del que hablar.
    if (item.source.kind == SourceKind.manualNote) {
      return const SizedBox.shrink();
    }
    // La vista previa de YouTube tampoco depende de un archivo original
    // —ver el comentario de `YoutubeEmbedResolvedViewer`—, así que es la
    // única que sigue adelante sin uno.
    if (item.source.originalFilePath == null &&
        item.source.kind != SourceKind.youtube) {
      return const SizedBox.shrink();
    }

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
      NoResolvedViewer() => const SizedBox.shrink(),
      TextResolvedViewer(:final content, :final markdown) =>
        _EmbeddedViewerFrame(
          tall: true,
          onExpand: expand,
          child: DocumentReaderView(
            title: item.title,
            content: content,
            markdown: markdown,
          ),
        ),
      ImageResolvedViewer(:final path) => _EmbeddedViewerFrame(
        onExpand: expand,
        child: ImageViewerView(path: path),
      ),
      MediaResolvedViewer(:final path, isVideo: false) => _EmbeddedViewerFrame(
        onExpand: expand,
        child: MediaPlayerView(path: path, isVideo: false),
      ),
      // Un video —uno del teléfono, un TikTok, un reel—: el video, y debajo
      // el mismo reproductor que un audio del teléfono, solo con su audio
      // (F24, decisión B del usuario). Los dos manejan el mismo audio: ver
      // `playbackSessionProvider`.
      MediaResolvedViewer(:final path, isVideo: true) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmbeddedViewerFrame(
            onExpand: expand,
            child: MediaPlayerView(path: path, isVideo: true),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: MediaPlayerView(
                key: const Key('video-audio-player'),
                path: path,
                isVideo: false,
                audioOnly: true,
              ),
            ),
          ),
        ],
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
      // Sin `onExpand`: tocar la vista previa ya hace lo único que tiene
      // sentido hacer con un video ajeno —abrirlo en YouTube—, así que no
      // hay una pantalla completa propia de la app a la que expandirla.
      YoutubeEmbedResolvedViewer(:final videoId, :final url) =>
        _EmbeddedViewerFrame(
          child: YoutubeEmbedView(videoId: videoId, url: url),
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
