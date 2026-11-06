import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_labels.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_listening.dart';
import 'package:sinapsis/features/creations/presentation/creation_passage_navigation.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_anchored_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_card.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de un podcast (F47, punto 5 del plan): lo que va debajo de la
/// barra común del visor de «Lo creado» (←, el título, «Ver N fuentes» y ⋮).
///
/// - **Arriba**, de qué es —el formato, cuánto dura, cuántas voces—, el
///   rótulo «Hecho con IA» con el modelo que lo escribió, y el audio con su
///   estado ([PodcastListenButton]): escucharlo, o por qué no hay y
///   generarlo.
/// - **Si salió más corto** porque el material no daba para más, lo dice; y
///   **si la comprobación quitó tramos**, cuántos, con lo quitado a la vista
///   y por qué.
/// - **La transcripción**: el guion por tramos, con quién habla en cada uno
///   y cada cita tocable, que lleva al pasaje en su documento. Mientras
///   suena, **se sigue**: el tramo que suena se resalta y la vista lo
///   acompaña, salvo que la persona se haya movido (`ReadAloudFollow`, con
///   «Volver a la lectura»).
///
/// Con el audio listo, el podcast se ofrece al lector (`ReadableRegion`):
/// la cola puede sumarlo como cualquier texto, y suena en el reproductor
/// anclado y en la tarjeta de la notificación.
class PodcastViewer extends ConsumerStatefulWidget {
  const PodcastViewer({required this.creation, super.key});

  final StudyCreation creation;

  /// El ancho cómodo de lectura: en una tableta, el texto no se estira de
  /// punta a punta.
  static const _maxWidth = 720.0;

  @override
  ConsumerState<PodcastViewer> createState() => _PodcastViewerState();
}

class _PodcastViewerState extends ConsumerState<PodcastViewer> {
  final _scroll = ScrollController();

  /// Si la transcripción sigue lo que suena o la persona se fue a otro lado.
  final _follow = ReadAloudFollow();

  /// La clave de cada tramo, para llevar la vista hasta él.
  final _segmentKeys = <int, GlobalKey>{};

  StudyCreation get creation => widget.creation;

  String get _readableId => podcastReadableId(creation.id);

  @override
  void initState() {
    super.initState();
    _follow.addListener(_onFollowChanged);
    ref.listenManual(
      readAloudControllerProvider.select(
        (s) => s.document?.id == _readableId && s.panel != ReadAloudPanel.hidden
            ? s.segmentIndex
            : null,
      ),
      (previous, next) => _revealSoon(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _follow
      ..removeListener(_onFollowChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFollowChanged() {
    if (!_follow.following) return;
    final state = ref.read(readAloudControllerProvider);
    if (state.document?.id != _readableId) return;
    _revealSoon(state.segmentIndex);
  }

  void _revealSoon(int? index) {
    if (index == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(index);
    });
  }

  /// Lleva el tramo [index] a la franja cómoda de la vista (`ReadAloudBand`)
  /// si la transcripción sigue lo que suena y no está ya ahí.
  void _reveal(int index) {
    final box =
        _segmentKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _scroll.position;
    final atTop = viewport.getOffsetToReveal(box, 0).offset;
    final extent = position.viewportDimension;
    final view = Rect.fromLTWH(0, position.pixels, 1, extent);
    final shown = Rect.fromLTWH(0, atTop, 1, box.size.height);
    final comfortable = ReadAloudBand.contains(view, shown);
    if (!_follow.shouldMoveTo(comfortable: comfortable)) return;
    final destination = (atTop - extent * ReadAloudBand.landing).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((destination - position.pixels).abs() < 1) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(destination);
    } else {
      unawaited(
        position.animateTo(
          destination,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final podcast = PodcastJson.decode(creation.decodedContent);
    if (podcast == null) {
      return Center(
        key: const Key('podcast-unreadable'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.f47P6Unreadable,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    final segments = podcast.segments;
    _follow.resumeOnNewReadings(ref);
    final listening = ref.watch(
      readAloudControllerProvider.select(
        (s) =>
            s.document?.id == _readableId && s.panel != ReadAloudPanel.hidden,
      ),
    );
    final audio = ref.watch(_listenableProvider(creation));
    final readable = audio.valueOrNull;
    // Todos los tramos armados —un guion son decenas, no miles—: así se
    // puede llevar la vista hasta el que suena.
    final list = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.direction != ScrollDirection.idle &&
            listening) {
          _follow.release();
        }
        return false;
      },
      child: SingleChildScrollView(
        key: const Key('podcast-viewer'),
        controller: _scroll,
        // Lo de abajo no queda tapado por el reproductor anclado: la
        // pantalla le deja su lugar (`ReadAloudRoom`).
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: PodcastViewer._maxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  creation: creation,
                  podcast: podcast,
                  readable: readable,
                ),
                for (var i = 0; i < segments.length; i++)
                  KeyedSubtree(
                    key: _segmentKeys.putIfAbsent(i, GlobalKey.new),
                    child: _SegmentView(
                      key: ValueKey('podcast-segment-$i'),
                      creation: creation,
                      podcast: podcast,
                      index: i,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return ReadableRegion(
      document: readable,
      child: Stack(
        children: [
          Positioned.fill(child: list),
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: ReadAloudBackToReading(
                sourceKey: _readableId,
                follow: _follow,
                onPressed: _follow.resume,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que suena al escuchar el podcast de una creación: su documento con el
/// audio, si el audio está, es de este guion y está en el teléfono; `null`
/// si no.
final _listenableProvider = FutureProvider.autoDispose
    .family<ReadableDocument?, StudyCreation>((ref, creation) async {
      final podcast = PodcastJson.decode(creation.decodedContent);
      final audio = podcast?.audio;
      if (podcast == null || audio == null) return null;
      final cast = PodcastCast.of(creation.options, podcast.format);
      if (podcastAudioStateOf(podcast, cast, creation.languageCode) !=
          PodcastAudioState.ready) {
        return null;
      }
      final path = await ref.watch(
        podcastAudioPathProvider(audio.reference).future,
      );
      if (path == null) return null;
      return podcastReadableDocument(
        creation: creation,
        podcast: podcast,
        audio: audio,
        path: path,
        title: creation.title ?? podcast.title,
      );
    });

/// Lo de arriba del visor: de qué es, «Hecho con IA», escuchar y los avisos
/// de la comprobación.
class _Header extends StatelessWidget {
  const _Header({
    required this.creation,
    required this.podcast,
    required this.readable,
  });

  final StudyCreation creation;
  final Podcast podcast;

  /// Lo que se escucha, si el audio está listo.
  final ReadableDocument? readable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = podcastMinutes(podcast.estimatedDuration);
    final voices = podcast.format.speakerCount;
    final meta = [
      podcastFormatLabel(l10n, podcast.format),
      l10n.f47P6Minutes(minutes),
      l10n.f47P6VoicesCount(voices),
    ].join(' · ');
    final model = creation.modelName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          meta,
          key: const Key('podcast-meta'),
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Chip(
            key: const Key('podcast-made-with-ai'),
            avatar: Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
            label: Text(
              model == null || model.isEmpty
                  ? l10n.f47P6MadeWithAi
                  : l10n.f47P6MadeWithAiModel(model),
            ),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 16),
        PodcastListenButton(
          creation: creation,
          podcast: podcast,
          readable: readable,
        ),
        if (podcast.shortenedByMaterial) ...[
          const SizedBox(height: 16),
          _Notice(
            key: const Key('podcast-shortened'),
            icon: Icons.timelapse,
            text: l10n.f47P6Shortened(
              (podcast.targetWords / kPodcastWordsPerMinute).ceil().clamp(
                1,
                999,
              ),
              podcast.length.minutes,
            ),
          ),
        ],
        if (podcast.discarded.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Discarded(podcast: podcast),
        ],
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            l10n.f47P6Transcript,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// El audio del podcast (F47, paso 6b): el botón de escuchar con su estado
/// y, si no hay audio que escuchar, por qué —sin fingir nada— y «Generar el
/// audio».
///
/// - **Listo** ([readable]): «Escuchar», que abre el podcast en el
///   reproductor anclado; mientras suena, «Pausar», y en pausa, «Seguir
///   escuchando». Debajo, cuánto dura.
/// - **De otra versión del guion o de otras voces**: apagado, lo dice y
///   ofrece «Generar el audio de nuevo».
/// - **El archivo no está** en el teléfono: lo dice y ofrece generarlo.
/// - **No se pudo generar**: por qué —una voz que falta, con su botón de
///   bajarla; un motor que falló; el disco— y «Generar el audio».
/// - **Nunca se generó** (uno de antes del audio): lo dice y ofrece
///   generarlo.
/// - **En un dispositivo que no sabe hacer las voces**: solo lo dice.
class PodcastListenButton extends ConsumerWidget {
  const PodcastListenButton({
    required this.creation,
    required this.podcast,
    this.readable,
    super.key,
  });

  final StudyCreation creation;
  final Podcast podcast;

  /// Lo que se escucha, si el audio está listo y en el teléfono.
  final ReadableDocument? readable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final readable = this.readable;
    final cast = PodcastCast.of(creation.options, podcast.format);
    final state = podcastAudioStateOf(podcast, cast, creation.languageCode);
    final audio = podcast.audio;
    final run = ref.watch(
      readAloudControllerProvider.select(
        (s) => s.document?.id != podcastReadableId(creation.id)
            ? ReadAloudRun.none
            : s.playing
            ? ReadAloudRun.playing
            : ReadAloudRun.paused,
      ),
    );
    // El archivo, solo si el contenido dice que hay uno de este guion.
    final path = state == PodcastAudioState.ready && audio != null
        ? ref.watch(podcastAudioPathProvider(audio.reference))
        : null;
    final missing = path != null && !path.isLoading && path.valueOrNull == null;
    final renderer = ref.watch(speechAudioRendererProvider);
    final canMake =
        ref.watch(speechVoiceRenderersProvider).isNotEmpty &&
        podcastSpeechPieces(
          podcast,
          cast,
          creation.languageCode,
        ).every((piece) => renderer.rendererOf(piece.voiceId) != null);

    final note = switch (state) {
      PodcastAudioState.ready when readable != null => null,
      PodcastAudioState.ready => missing ? l10n.f47P6bAudioMissingFile : null,
      PodcastAudioState.stale => l10n.f47P6bAudioStale,
      PodcastAudioState.failed => _issueText(l10n, podcast.audioIssue!),
      PodcastAudioState.none => l10n.f47P6bAudioNone,
    };
    final offerMake =
        readable == null && (state != PodcastAudioState.ready || missing);
    final toDownload = _voiceToDownload(podcast.audioIssue);

    Future<void> listen() async {
      final controller = ref.read(readAloudControllerProvider.notifier);
      switch (run) {
        case ReadAloudRun.none:
          await controller.open(readable!);
        case ReadAloudRun.playing:
          await controller.pause();
        case ReadAloudRun.paused:
          await controller.play();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          key: const Key('podcast-listen'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const StadiumBorder(),
          ),
          onPressed: readable == null ? null : () => unawaited(listen()),
          icon: Icon(
            run == ReadAloudRun.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
          label: Text(switch (run) {
            ReadAloudRun.none => l10n.f47P6Listen,
            ReadAloudRun.playing => l10n.f47P6bPause,
            ReadAloudRun.paused => l10n.f47P6bResume,
          }),
        ),
        const SizedBox(height: 6),
        if (readable != null && audio != null)
          Text(
            l10n.f47P6bAudioReady(formatReadAloudTime(audio.duration)),
            key: const Key('podcast-audio-ready'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (note != null)
          Semantics(
            liveRegion: true,
            child: Text(
              note,
              key: const Key('podcast-audio-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (offerMake && !canMake)
          Text(
            l10n.f47P6bNoAudioHere,
            key: const Key('podcast-audio-not-here'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (offerMake && canMake && toDownload != null) ...[
          const SizedBox(height: 6),
          VoiceDownloadControls(
            key: const Key('podcast-audio-download'),
            voice: offlineVoiceProfiles([toDownload]).single,
          ),
        ],
        if (offerMake && canMake) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('podcast-audio-generate'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: const StadiumBorder(),
            ),
            onPressed: () => requestPodcastAudioLater(context, ref, creation),
            icon: const Icon(Icons.graphic_eq_rounded),
            label: Text(
              state == PodcastAudioState.stale
                  ? l10n.f47P6bRegenerateAudio
                  : l10n.f47P6bGenerateAudio,
            ),
          ),
        ],
      ],
    );
  }

  /// Por qué no se generó el audio, en una línea.
  static String _issueText(AppLocalizations l10n, PodcastAudioIssue issue) {
    switch (issue.problem) {
      case PodcastAudioProblem.voiceMissing:
        final id = issue.voiceId;
        final voice = id == null ? null : podcastNarrationVoice(id);
        final offline = id == null ? null : SpeechVoiceIds.offlineIdOf(id);
        final name = offline != null
            ? OfflineVoiceCatalog.byId(offline)?.name
            : voice?.name;
        return name == null
            ? l10n.f47P6bAudioVoiceMissingAny
            : l10n.f47P6bAudioVoiceMissing(name);
      case PodcastAudioProblem.engine:
        return l10n.f47P6bAudioEngine;
      case PodcastAudioProblem.file:
        return l10n.f47P6bAudioFile;
    }
  }

  /// La voz sin conexión que faltó, para ofrecer bajarla.
  static OfflineVoice? _voiceToDownload(PodcastAudioIssue? issue) {
    if (issue?.problem != PodcastAudioProblem.voiceMissing) return null;
    final id = issue?.voiceId;
    final offline = id == null ? null : SpeechVoiceIds.offlineIdOf(id);
    return offline == null ? null : OfflineVoiceCatalog.byId(offline);
  }
}

/// Un aviso en una línea, con su ícono.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Lo que quitó la comprobación: cuántos tramos, y al abrirlo cada uno
/// tachado, con por qué.
class _Discarded extends StatelessWidget {
  const _Discarded({required this.podcast});

  final Podcast podcast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('podcast-discarded'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.fact_check_outlined,
          color: scheme.onSurfaceVariant,
        ),
        title: Text(
          l10n.f47P6Discarded(podcast.discarded.length),
          style: theme.textTheme.bodyMedium,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final discard in podcast.discarded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    podcastDiscardReasonLabel(l10n, discard.reason),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                  Text(
                    discard.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Un tramo de la transcripción: quién habla —en la conversación—, lo que
/// dice y sus citas.
class _SegmentView extends ConsumerWidget {
  const _SegmentView({
    required this.creation,
    required this.podcast,
    required this.index,
    super.key,
  });

  final StudyCreation creation;
  final Podcast podcast;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segment = podcast.segments[index];
    final conversation = podcast.format.speakerCount == 2;
    final previous = index == 0 ? null : podcast.segments[index - 1];
    // El nombre va cuando cambia quien habla, como en un guion.
    final showSpeaker =
        conversation &&
        (previous == null || previous.speaker != segment.speaker);
    final name = podcastSpeakerName(l10n, segment.speaker);
    return Padding(
      padding: EdgeInsets.only(top: showSpeaker ? 18 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // El nombre ya lo dice el tramo, para el lector de pantalla: acá
          // solo se ve.
          if (showSpeaker)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    PodcastSpeakerDot(speaker: segment.speaker, size: 24),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        name,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: podcastSpeakerColor(scheme, segment.speaker),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Cada tramo, un nodo propio que dice quién habla y qué dice; el
          // que suena, en el amarillo del lector.
          Semantics(
            container: true,
            label: conversation ? '$name: ${segment.text}' : segment.text,
            excludeSemantics: true,
            child: _SpokenText(
              text: segment.text,
              sourceKey: podcastReadableId(creation.id),
              from: podcastSegmentStart(podcast, index),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ),
          if (segment.citations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, citation) in segment.citations.indexed)
                  _CitationChip(
                    key: ValueKey('podcast-citation-$index-$i'),
                    citation: citation,
                    onTap: () => unawaited(
                      openCreationPassage(
                        context,
                        ref,
                        creation,
                        documentId:
                            citation.documentId ??
                            (creation.sourceIds.length == 1
                                ? creation.sourceIds.single
                                : null),
                        quote: citation.quote,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// El texto de un tramo, con lo que suena en el amarillo del lector —el
/// mismo de toda la app (`RenderedMarkdown.buildSpans`)—: se redibuja solo
/// cuando lo que suena entra, sale o se mueve dentro de él.
class _SpokenText extends ConsumerWidget {
  const _SpokenText({
    required this.text,
    required this.sourceKey,
    required this.from,
    this.style,
  });

  final String text;
  final String sourceKey;

  /// Dónde empieza en la transcripción entera.
  final int from;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final span = ref.watch(
      readAloudSpanProvider((
        sourceKey: sourceKey,
        from: from,
        to: from + text.length,
      )),
    );
    if (span == null) return Text(text, style: style);
    return Text.rich(
      RenderedMarkdown.plain(text).buildSpans(
        Theme.of(context),
        const [],
        baseStyle: DefaultTextStyle.of(context).style.merge(style),
        activeRange: span,
      ),
      key: const Key('podcast-segment-speaking'),
    );
  }
}

/// Una cita tocable: unas palabras del pasaje y su documento; lleva al
/// pasaje.
class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.citation, required this.onTap, super.key});

  final PodcastCitation citation;
  final VoidCallback onTap;

  /// Cuánto de la cita se ve en la ficha; la entera la dice el lector de
  /// pantalla.
  static const _shownChars = 70;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quote = citation.quote.length <= _shownChars
        ? citation.quote
        : '${citation.quote.substring(0, _shownChars - 1).trimRight()}…';
    final document = citation.documentTitle ?? l10n.f47P6CitationFromMaterial;
    return Semantics(
      button: true,
      label: l10n.f47P6CitationSemantics(document, citation.quote),
      hint: l10n.f47P6CitationHint,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.format_quote_rounded,
                    size: 18,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '«$quote»',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          TextSpan(
                            text: ' · $document',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
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
