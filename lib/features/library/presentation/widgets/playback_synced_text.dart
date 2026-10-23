import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/util/transcript_sync.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';

/// Lo que une el texto que sigue al audio con el mini reproductor (F23):
/// "Volver al audio" le pide al texto que muestre lo que suena.
class PlaybackFollowLink {
  /// Lleva la vista hasta lo que está sonando; `false` si no hay nada que
  /// mostrar —el texto no sigue al audio, o todavía no empezó—.
  bool Function()? revealPlaying;

  /// Despliega el lugar donde está el texto, si está plegado (F39): la
  /// transcripción va plegada en la tarjeta de estudiar, y plegada no está
  /// en pantalla para mostrar nada.
  VoidCallback? unfold;
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
    this.paints = const [],
    this.onStudyTap,
    super.key,
  });

  final KnowledgeItem item;
  final TextRendition rendition;
  final bool markdown;
  final PlaybackFollowLink? link;

  /// Lo estudiado de la transcripción, con sus colores (F39).
  final List<PaintedRange> paints;

  /// Un toque para lo estudiado —elegir una palabra clave—: si devuelve
  /// `true`, lo atendió y el audio no se mueve.
  final bool Function(int offset)? onStudyTap;

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
    // Armada con el audio ya sonando —desplegada en la tarjeta de estudiar
    // (F39)—, lo que suena se sabe desde el primer cuadro, sin esperar al
    // próximo aviso del reproductor. Sin setState: se está dibujando.
    _playing = _current();
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
    if (widget.onStudyTap?.call(offset) ?? false) return;
    final session = _session;
    if (session == null || !session.started) return;
    final span = _sync.atOffset(offset);
    if (span == null) return;
    session.controller.seekTo(Duration(milliseconds: span.startMs));
  }

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(itemPlaybackPathProvider(widget.item)).valueOrNull;
    _follow(
      path != null && !_sync.isEmpty
          ? ref.watch(playbackSessionProvider(path))
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
      paints: widget.paints,
      onTapOffset: _session == null && widget.onStudyTap == null
          ? null
          : _seekTo,
    );
  }
}
