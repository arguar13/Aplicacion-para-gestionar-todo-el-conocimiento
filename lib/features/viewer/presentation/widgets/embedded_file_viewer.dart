import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/image_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mobile_page_width.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/open_document_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/youtube_embed_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El archivo original de un elemento, visible directo en su detalle — sin
/// tener que tocar ningún botón para recién ahí abrirlo.
///
/// Cada `SourceKind` con algo que mostrar se ve en su forma natural: una
/// foto o un video se ven como tales, un PDF con su maquetación de verdad,
/// la página web archivada con sus imágenes en su lugar, y un DOCX o un
/// EPUB con la tipografía de libro que ya tenía el viejo "Modo lectura"
/// —ver `DocumentReaderView`—. Un documento para leer —un PDF, un DOCX, un
/// EPUB, un texto— se ve como su **primera página, fija** (F39): no se
/// desplaza ni se hace zoom, y arrastrar encima mueve el detalle, no el
/// documento; se lee entero con «Leer como libro» o tocándola — ver
/// `PdfFirstPagePreview` y `DocumentFirstPagePreview`. Un video de YouTube
/// es la única excepción real: lo que se ve es su miniatura, no un
/// reproductor propio, porque lo que hay para mostrar no es un archivo de
/// este elemento sino el video original — ver `YoutubeEmbedView`.
///
/// Ocupa un marco de alto acotado, no lo que le haga falta: un PDF o un
/// video no tienen por qué apoderarse de la pantalla del detalle, y cada
/// visor —`MediaPlayerView`, `WebPageViewerView`— ya sabe manejarse dentro de
/// cualquier alto que se le dé. Quien quiera más lugar toca el botón de
/// expandir, que lleva a la misma pantalla completa que abriría el viejo
/// botón "Ver" — ver `openDocumentViewer`.
///
/// En un documento para leer —un PDF, un DOCX o un EPUB, un texto— ese
/// botón va grande, semitransparente y en el centro, con «Leer como libro»
/// (F35): es lo primero que se ve, y dice qué hacer para leerlo entero. En
/// una página web, igual, con «Ver la página» (pedido del usuario), y en una
/// foto, con «Ampliar» (F45, paso 3): la misma píldora, que deja ver la foto
/// debajo. En un video queda chico en la esquina: en el centro taparía el
/// botón de reproducir.
///
/// El audio de un video —el reproductor solo con su audio de F24— ya no va
/// acá abajo: es la parte de arriba del panel de la fuente (F26, decisión
/// B), junto a las acciones. Acá queda solo el original.
///
/// **El original es el mismo que en Procesado** (F45, paso 7b, mejora 16):
/// una página web se ve como en el navegador del teléfono, también en la
/// computadora (`MobilePageWidth`), y a pantalla completa abre la misma
/// pantalla de original (`openDocumentViewer`).
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

    final frame = switch (resolved) {
      AsyncData(:final value) => _buildFrame(context, ref, value),
      AsyncError() => null,
      _ => const EmbeddedViewerFrame(
        child: Center(child: CircularProgressIndicator()),
      ),
    };
    return frame ?? const SizedBox.shrink();
  }

  /// El marco con el visor que le toca a [resolved], o `null` si no hay
  /// nada que mostrar.
  Widget? _buildFrame(
    BuildContext context,
    WidgetRef ref,
    ResolvedViewer resolved,
  ) {
    void expand() => openDocumentViewer(context, ref, item);
    final l10n = AppLocalizations.of(context)!;

    return switch (resolved) {
      NoResolvedViewer() => null,
      TextResolvedViewer(:final content, :final markdown, :final study) =>
        EmbeddedViewerFrame(
          tall: true,
          onExpand: expand,
          bigButtonLabel: l10n.detailReadAsBook,
          child: DocumentFirstPagePreview(
            content: content,
            markdown: markdown,
            study: study,
            onTap: expand,
          ),
        ),
      ImageResolvedViewer(:final path) => EmbeddedViewerFrame(
        onExpand: expand,
        bigButtonLabel: l10n.f45S3Enlarge,
        child: ImageViewerView(path: path),
      ),
      // Un audio o un video —uno del teléfono, un TikTok, un reel—. El
      // reproductor solo con el audio de un video va en el panel de la
      // fuente (F26); los dos manejan el mismo audio: ver
      // `playbackSessionProvider`.
      MediaResolvedViewer(:final path, :final isVideo) => EmbeddedViewerFrame(
        onExpand: expand,
        child: MediaPlayerView(path: path, isVideo: isVideo),
      ),
      PdfResolvedViewer(:final path, :final text) => EmbeddedViewerFrame(
        tall: true,
        onExpand: expand,
        bigButtonLabel: l10n.detailReadAsBook,
        child: PdfFirstPagePreview(path: path, text: text, onTap: expand),
      ),
      WebPageResolvedViewer(:final path, :final url, :final text) =>
        EmbeddedViewerFrame(
          tall: true,
          onExpand: expand,
          bigButtonLabel: l10n.detailViewWebPage,
          child: MobilePageWidth(
            child: WebPageViewerView(
              path: path,
              url: url,
              text: text,
              mobile: true,
            ),
          ),
        ),
      // Sin `onExpand`: tocar la vista previa ya hace lo único que tiene
      // sentido hacer con un video ajeno —abrirlo en YouTube—, así que no
      // hay una pantalla completa propia de la app a la que expandirla.
      YoutubeEmbedResolvedViewer(:final videoId, :final url) =>
        EmbeddedViewerFrame(
          child: YoutubeEmbedView(videoId: videoId, url: url),
        ),
    };
  }
}

/// El marco acotado —esquinas redondeadas, borde tenue— que envuelve
/// cualquier visor embebido, con el botón de expandir a pantalla completa
/// flotando encima: en la esquina, o grande y en el centro con
/// [bigButtonLabel].
///
/// El mismo marco muestra el original de un documento procesado en su
/// pantalla (F43, paso 15: `ProcessedOriginalSection`): se ve y se comporta
/// igual que en el detalle de la Biblioteca.
class EmbeddedViewerFrame extends StatelessWidget {
  const EmbeddedViewerFrame({
    required this.child,
    this.onExpand,
    this.tall = false,
    this.bigButtonLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onExpand;

  /// Con esto, el botón va grande y en el centro, con este texto: «Leer como
  /// libro» en un documento (F35), «Ver la página» en una página web,
  /// «Ampliar» en una foto (F45). Fuera del botón, lo de abajo se sigue
  /// desplazando, tocando y, en una foto, pellizcando como siempre.
  final String? bigButtonLabel;

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
              if (onExpand != null && bigButtonLabel != null)
                Positioned.fill(
                  child: Center(
                    child: _CenterButton(
                      label: bigButtonLabel!,
                      tooltip: l10n.detailExpandViewer,
                      onPressed: onExpand!,
                    ),
                  ),
                )
              else if (onExpand != null)
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

/// El botón grande del centro (F35): las flechas de expandir y su nombre
/// —«Leer como libro», «Ver la página», «Ampliar»—, sobre un fondo oscuro
/// semitransparente que deja ver el original debajo. Uno solo para todo lo
/// que lo lleva, así se ve y se toca igual en un libro que en una foto.
///
/// La llave conserva el nombre con que nació, «Leer como libro»: la buscan
/// las pruebas del detalle y de Procesado.
class _CenterButton extends StatelessWidget {
  const _CenterButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium;
    // El lector de pantalla lo anuncia como lo que es: un botón con su
    // nombre, no un texto suelto que se puede tocar.
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: Material(
          key: const Key('embedded-viewer-read-as-book'),
          color: Colors.black.withValues(alpha: 0.4),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.open_in_full, size: 32, color: Colors.white),
                  const SizedBox(width: 12),
                  // Con la letra al doble en un teléfono angosto, el nombre se
                  // parte en dos renglones en vez de salirse del botón.
                  Flexible(
                    child: Text(
                      label,
                      style: textStyle?.copyWith(color: Colors.white),
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
