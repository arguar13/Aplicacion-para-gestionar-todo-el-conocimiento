import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_text_provider.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_readable_providers.dart';
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
/// Es **el marco de lectura** de un audio, un video o un YouTube (F47, paso
/// 1): ←, Contenido, IA, Aa y ⋮ arriba; el reproductor y la transcripción
/// como cuerpo, con la letra de «Apariencia»; en un YouTube, «Ver en
/// YouTube» en ⋮.
///
/// La pantalla no se mueve sola (F23, decisión B): «Ir a lo que suena»,
/// debajo del reproductor, lleva hasta la palabra que suena.
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

  /// Lo que se ofrece para escuchar con la voz: el mismo documento mientras
  /// no cambie el texto partido ni lo estudiado.
  (ReadableDocument, Map<ReadScope, List<ReadableSegment>>, ReadableDocument)?
  _offered;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// La transcripción para el lugar del reproductor del marco —«Escuchar» y
  /// «Leer: Todo · Resumen · Síntesis · Palabras clave»—, con lo estudiado.
  /// Ya suena en su propio audio: la voz **empieza por lo estudiado**, como
  /// en el detalle (`ReadableDocument.withOwnAudio`).
  ReadableDocument? _readable(KnowledgeItem item) {
    final study = studyTextOf(item);
    if (study == null) return null;
    final whole = ref.watch(
      readableTextProvider((
        id: studyReadableId(study.renditionId),
        title: item.title,
        sourceKey: study.renditionId,
        content: study.content,
        markdown: study.markdown,
      )),
    );
    final studied = ref.watch(studyReadScopesProvider(study));
    if (whole == null) return null;
    final cached = _offered;
    if (cached != null &&
        identical(cached.$1, whole) &&
        identical(cached.$2, studied)) {
      return cached.$3;
    }
    final document = whole.withScopes(studied).withOwnAudio();
    _offered = (whole, studied, document);
    return document;
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

    final url = item?.source.url;
    return ReadingFrame(
      key: const Key('transcript-follow'),
      info: ReadingDocumentInfo(
        title: item?.title ?? '',
        kindLabel: item?.source.kind.label(l10n) ?? '',
        kindIcon: item?.source.kind.icon ?? Icons.graphic_eq,
      ),
      menu: [
        if (item != null &&
            item.source.kind == SourceKind.youtube &&
            url != null)
          ReadingMenuGroup([
            ReadingMenuEntry(
              key: const Key('transcript-follow-youtube'),
              icon: Icons.smart_display_outlined,
              label: l10n.f47P1MoreOpenYoutube,
              onSelected: () => unawaited(launchExternalUrl(url)),
            ),
          ]),
      ],
      body: item == null || transcript == null
          ? const Center(child: CircularProgressIndicator())
          : ReadableRegion(
              document: _readable(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: scheme.surfaceContainerLow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (path != null)
                          Padding(
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: TextButton.icon(
                              key: const Key('transcript-follow-now'),
                              icon: const Icon(Icons.my_location),
                              label: Text(l10n.f45S3TranscriptNow),
                              onPressed: () => _link.revealPlaying?.call(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: readingColumnPadding(
                          context,
                        ).copyWith(top: 16, bottom: 48),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: readingColumnWidth,
                            ),
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
