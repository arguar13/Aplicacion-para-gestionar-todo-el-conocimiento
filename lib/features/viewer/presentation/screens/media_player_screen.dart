import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';

/// El reproductor de audio o video a pantalla completa, con su propia barra
/// de título.
///
/// Envoltorio delgado sobre [MediaPlayerView]: todo el reproductor de
/// verdad vive ahí, para poder embeberlo también directo en el detalle de
/// un elemento —ver `EmbeddedFileViewer`— sin pasar por esta pantalla ni
/// por `Navigator`.
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: MediaPlayerView(path: path, isVideo: isVideo),
      ),
    );
  }
}
