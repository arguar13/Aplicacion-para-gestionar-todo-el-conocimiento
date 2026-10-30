import 'package:flutter/material.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un audio o un video sin transcripción a pantalla completa, en **el marco
/// de lectura** (F47, paso 1): el reproductor como cuerpo. Con transcripción
/// se abre `TranscriptFollowScreen`, con la transcripción que se sigue.
///
/// Envoltorio delgado sobre [MediaPlayerView]: todo el reproductor de
/// verdad vive ahí, para poder embeberlo también directo en el detalle de
/// un elemento —ver `EmbeddedFileViewer`—.
class MediaPlayerScreen extends StatelessWidget {
  const MediaPlayerScreen({
    required this.path,
    required this.title,
    required this.isVideo,
    super.key,
  });

  final String path;
  final String title;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ReadingFrame(
      info: ReadingDocumentInfo(
        title: title,
        kindLabel: isVideo ? l10n.f47P1KindVideo : l10n.f47P1KindAudio,
        kindIcon: isVideo ? Icons.movie_outlined : Icons.graphic_eq,
      ),
      bodyKind: ReadingBodyKind.asIs,
      body: MediaPlayerView(path: path, isVideo: isVideo),
    );
  }
}
