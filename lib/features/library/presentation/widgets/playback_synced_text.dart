import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/util/transcript_sync.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';

/// Lo que une el texto que sigue al audio con el mini reproductor (F23):
/// "Volver al audio" le pide al texto que muestre lo que suena.
class PlaybackFollowLink {
  /// Lleva la vista hasta lo que está sonando; `false` si no hay nada que
  /// mostrar —el texto no sigue al audio, o todavía no empezó—.
  bool Function()? revealPlaying;
}

/// La transcripción de un audio o un video que **sigue al audio** (F23):
/// mientras suena, la palabra que se dice —o el renglón, en una
/// transcripción sin tiempos por palabra— se ve en amarillo; tocar una
/// palabra lleva el audio a ese momento. La pantalla no se mueve sola
/// (decisión B): para eso está "Volver al audio" en el mini reproductor.
///
/// Sigue al **mismo** reproductor que se ve arriba —ver
/// `playbackSessionProvider`—, así que funciona igual con el audio sonando
/// desde el reproductor, desde el mini reproductor o en pantalla completa.
/// Antes de que el audio empiece, es el texto de siempre.
class PlaybackSyncedText extends ConsumerStatefulWidget {
  const PlaybackSyncedText({
    required this.item,
    required this.rendition,
    required this.markdown,
    this.link,
    super.key,
  });

  final KnowledgeItem item;
  final TextRendition rendition;
  final bool markdown;
  final PlaybackFollowLink? link;

  @override
  ConsumerState<PlaybackSyncedText> createState() => _PlaybackSyncedTextState();
}

class _PlaybackSyncedTextState extends ConsumerState<PlaybackSyncedText> {
  final _text = HighlightableTextController();
  late TranscriptSync _sync = _build();
  PlaybackSession? _session;
  SyncSpan? _playing;

  TranscriptSync _build() => TranscriptSync.build(
    widget.rendition.content,
    widget.rendition.wordTimings,
  );

  @override
  void initState() {
    super.initState();
    widget.link?.revealPlaying = _revealPlaying;
  }

  @override
  void didUpdateWidget(PlaybackSyncedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rendition.content != widget.rendition.content ||
        !listEquals(
          oldWidget.rendition.wordTimings,
          widget.rendition.wordTimings,
        )) {
      _sync = _build();
      // Sin setState: este cuadro ya se está por dibujar.
      _playing = _current();
    }
    if (oldWidget.link != widget.link) {
      if (oldWidget.link?.revealPlaying == _revealPlaying) {
        oldWidget.link?.revealPlaying = null;
      }
      widget.link?.revealPlaying = _revealPlaying;
    }
  }

  @override
  void dispose() {
    _session?.controller.removeListener(_update);
    if (widget.link?.revealPlaying == _revealPlaying) {
      widget.link?.revealPlaying = null;
    }
    _text.dispose();
    super.dispose();
  }

  void _follow(PlaybackSession? session) {
    if (identical(session, _session)) return;
    _session?.controller.removeListener(_update);
    _session = session;
    session?.controller.addListener(_update);
  }

  SyncSpan? _current() {
    final session = _session;
    return session != null && session.started
        ? _sync.at(session.controller.value.position)
        : null;
  }

  /// Qué se está diciendo ahora; se redibuja solo cuando cambia de palabra.
  void _update() {
    final playing = _current();
    if (playing != _playing && mounted) setState(() => _playing = playing);
  }

  bool _revealPlaying() {
    final playing = _playing;
    if (playing == null) return false;
    _text.reveal(playing.start);
    return true;
  }

  /// Tocar una palabra lleva el audio ahí —como en las transcripciones de
  /// YouTube—, solo si el audio ya está en marcha: con el audio quieto, un
  /// toque es solo un toque.
  void _seekTo(int offset) {
    final session = _session;
    if (session == null || !session.started) return;
    final span = _sync.atOffset(offset);
    if (span == null) return;
    session.controller.seekTo(Duration(milliseconds: span.startMs));
  }

  @override
  Widget build(BuildContext context) {
    final resolved = ref
        .watch(resolvedFileViewerProvider(widget.item))
        .valueOrNull;
    _follow(
      resolved is MediaResolvedViewer && !_sync.isEmpty
          ? ref.watch(playbackSessionProvider(resolved.path))
          : null,
    );
    final playing = _playing;

    return HighlightableText(
      itemId: widget.item.id,
      renditionId: widget.rendition.id,
      content: widget.rendition.content,
      markdown: widget.markdown,
      controller: _text,
      playing: playing == null
          ? null
          : (start: playing.start, end: playing.end),
      onTapOffset: _session == null ? null : _seekTo,
    );
  }
}
