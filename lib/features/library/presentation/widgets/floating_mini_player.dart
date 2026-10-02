import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mini_player.dart';

/// El mini reproductor del detalle de un audio o un video (F23, decisión
/// B): aparece abajo cuando el audio ya empezó y el reproductor —el que
/// marca [playerKey]— quedó fuera de la pantalla, y se va cuando el
/// reproductor vuelve a verse.
///
/// "Volver al audio" lleva hasta lo que está sonando en el texto —ver
/// [PlaybackFollowLink]—; si el texto no lo sigue, al reproductor.
class FloatingMiniPlayer extends ConsumerStatefulWidget {
  const FloatingMiniPlayer({
    required this.item,
    required this.scrollController,
    required this.playerKey,
    this.link,
    super.key,
  });

  final KnowledgeItem item;
  final ScrollController scrollController;
  final GlobalKey playerKey;
  final PlaybackFollowLink? link;

  @override
  ConsumerState<FloatingMiniPlayer> createState() => _FloatingMiniPlayerState();
}

class _FloatingMiniPlayerState extends ConsumerState<FloatingMiniPlayer> {
  PlaybackSession? _session;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_update);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_update);
    _session?.controller.removeListener(_update);
    super.dispose();
  }

  void _follow(PlaybackSession? session) {
    if (identical(session, _session)) return;
    _session?.controller.removeListener(_update);
    _session = session;
    session?.controller.addListener(_update);
  }

  void _update() {
    final session = _session;
    final visible = session != null && session.started && !_playerOnScreen();
    if (visible != _visible && mounted) setState(() => _visible = visible);
  }

  /// Si se ve algo del reproductor dentro de lo que muestra la pantalla.
  bool _playerOnScreen() {
    final player = widget.playerKey.currentContext;
    if (player == null) return true;
    final box = player.findRenderObject() as RenderBox?;
    final viewport =
        Scrollable.maybeOf(player)?.context.findRenderObject() as RenderBox?;
    if (box == null || viewport == null || !box.attached) return true;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final viewTop = viewport.localToGlobal(Offset.zero).dy;
    final viewBottom = viewTop + viewport.size.height;
    // Con un tercio del reproductor a la vista alcanza para manejarlo ahí.
    final visible =
        (bottom.clamp(viewTop, viewBottom) - top.clamp(viewTop, viewBottom))
            .abs();
    return visible >= box.size.height / 3;
  }

  void _backToAudio() {
    if (widget.link?.revealPlaying?.call() ?? false) return;
    final player = widget.playerKey.currentContext;
    if (player == null) return;
    Scrollable.ensureVisible(
      player,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = ref
        .watch(resolvedFileViewerProvider(widget.item))
        .valueOrNull;
    final session = resolved is MediaResolvedViewer
        ? ref.watch(playbackSessionProvider(resolved.path))
        : null;
    _follow(session);
    if (session == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedSlide(
                offset: _visible ? Offset.zero : const Offset(0, 1.6),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: MiniPlayer(
                    controller: session.controller,
                    onBackToAudio: _backToAudio,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
