import 'package:flutter/material.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La miniatura de un video de YouTube, para tocar y abrirlo de verdad —en
/// la app de YouTube si está instalada, o en el navegador si no—.
///
/// No es un reproductor: no hay ningún control de reproducción acá, ni
/// video que corra dentro de la propia app — a diferencia de
/// `MediaPlayerView`. Es justamente la diferencia que separa a los dos, ver
/// el comentario de `YoutubeEmbedResolvedViewer` sobre por qué.
///
/// Sin `Scaffold` propio, igual que el resto de los visores: esto solo se
/// embebe dentro del marco acotado del detalle del elemento —no hay una
/// pantalla completa propia a la que expandirlo, porque tocarlo ya hace lo
/// único que tiene sentido hacer con un video ajeno: llevar a donde vive de
/// verdad.
class YoutubeEmbedView extends StatelessWidget {
  const YoutubeEmbedView({required this.videoId, required this.url, super.key});

  final String videoId;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: () => _open(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              // La misma miniatura pública que ya arma `ItemThumbnailResolver`
              // para la Biblioteca y el Grafo, en una resolución más grande:
              // acá el video ocupa mucho más lugar en pantalla.
              'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
              fit: BoxFit.cover,
              // Sin miniatura —sin red, un video privado que ya no la
              // sirve— el fondo negro de más arriba sigue dejando ver el
              // ícono de reproducir: sigue quedando claro que hay algo
              // para tocar.
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),
            // Oscurece el centro de la miniatura lo justo para que el
            // ícono de reproducir se lea igual de bien sobre un fotograma
            // claro que sobre uno oscuro.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.black38, Colors.transparent],
                  radius: 0.55,
                ),
              ),
            ),
            Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 72,
                color: Colors.white.withValues(alpha: 0.94),
                shadows: const [Shadow(blurRadius: 16, color: Colors.black54)],
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'YouTube',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final launched = await launchExternalUrl(url);
    if (launched || !context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailYoutubeOpenFailed)));
  }
}
