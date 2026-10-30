import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/viewer/presentation/providers/playback_session.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La transcripción de un audio o un video que sigue al audio (F23), en su
/// propia pantalla (F45, paso 3).
///
/// El detalle de una fuente muestra solo su original: el texto que se sacó de
/// él no va ahí. Pero la transcripción que sigue al audio es la forma de
/// escuchar el original —la palabra que suena, en amarillo; tocar una palabra
/// lleva el audio ahí—, y en Procesado no hay audio que seguir. Se abre desde
/// el panel de la fuente, como se amplía una foto: arriba el mismo
/// reproductor que el del detalle —el mismo audio, ver
/// `playbackSessionProvider`—, siempre a la vista, y abajo la transcripción.
///
/// La pantalla no se mueve sola (F23, decisión B): «Ir a lo que suena», en la
/// barra, lleva hasta la palabra que suena.
class TranscriptFollowScreen extends ConsumerStatefulWidget {
  const TranscriptFollowScreen({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<TranscriptFollowScreen> createState() =>
      _TranscriptFollowScreenState();
}

class _TranscriptFollowScreenState
    extends ConsumerState<TranscriptFollowScreen> {
  final _link = PlaybackFollowLink();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final item = ref.watch(libraryItemProvider(widget.itemId)).valueOrNull;
    final transcript = item == null ? null : followedTranscriptOf(item);
    final path = item == null
        ? null
        : ref.watch(itemPlaybackPathProvider(item)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          item?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('transcript-follow-now'),
            icon: const Icon(Icons.my_location),
            tooltip: l10n.f45S3TranscriptNow,
            onPressed: () => _link.revealPlaying?.call(),
          ),
        ],
      ),
      body: item == null || transcript == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: scheme.surfaceContainerLow,
                  child: path == null
                      ? const SizedBox(height: 100)
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: sourcePanelInset - 8,
                          ),
                          child: MediaPlayerView(
                            key: const Key('transcript-follow-player'),
                            path: path,
                            isVideo: false,
                            audioOnly: true,
                            compact: true,
                          ),
                        ),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: PlaybackSyncedText(
                            item: item,
                            rendition: transcript,
                            markdown: extractedTextIsMarkdown(item.source),
                            link: _link,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// La transcripción de [item] que sigue a su audio, o `null` si no tiene: la
/// forma principal de un audio, un video o un video de YouTube —la que lleva
/// los tiempos de cada palabra—, con algo escrito.
TextRendition? followedTranscriptOf(KnowledgeItem item) {
  if (!isTranscriptSource(item.source)) return null;
  return item.renditions
      .whereType<TextRendition>()
      .where(
        (r) =>
            r.isPrimary &&
            r.kind != RenditionKind.blocks &&
            r.content.trim().isNotEmpty,
      )
      .firstOrNull;
}
