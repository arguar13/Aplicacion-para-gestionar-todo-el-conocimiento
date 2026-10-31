import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_labels.dart';
import 'package:sinapsis/features/creations/presentation/creation_passage_navigation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de un podcast (F47, punto 5 del plan): lo que va debajo de la
/// barra común del visor de «Lo creado» (←, el título, «Ver N fuentes» y ⋮).
///
/// - **Arriba**, de qué es —el formato, cuánto dura, cuántas voces—, el
///   rótulo «Hecho con IA» con el modelo que lo escribió, y el botón de
///   escuchar con su estado ([PodcastListenButton]).
/// - **Si salió más corto** porque el material no daba para más, lo dice; y
///   **si la comprobación quitó tramos**, cuántos, con lo quitado a la vista
///   y por qué.
/// - **La transcripción**: el guion por tramos, con quién habla en cada uno
///   y cada cita tocable, que lleva al pasaje en su documento.
class PodcastViewer extends ConsumerWidget {
  const PodcastViewer({required this.creation, super.key});

  final StudyCreation creation;

  /// El ancho cómodo de lectura: en una tableta, el texto no se estira de
  /// punta a punta.
  static const _maxWidth = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return ListView.builder(
      key: const Key('podcast-viewer'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: segments.length + 1,
      itemBuilder: (context, index) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: index == 0
              ? _Header(creation: creation, podcast: podcast)
              : _SegmentView(
                  key: ValueKey('podcast-segment-${index - 1}'),
                  creation: creation,
                  podcast: podcast,
                  index: index - 1,
                ),
        ),
      ),
    );
  }
}

/// Lo de arriba del visor: de qué es, «Hecho con IA», escuchar y los avisos
/// de la comprobación.
class _Header extends StatelessWidget {
  const _Header({required this.creation, required this.podcast});

  final StudyCreation creation;
  final Podcast podcast;

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
        PodcastListenButton(creation: creation, podcast: podcast),
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

/// El botón de escuchar, con su lugar y su estado.
///
/// **Por ahora no hay audio**: el guion ya está, y la voz de cada tramo se
/// genera en la segunda parte del paso 6 de F47, con las voces sin conexión y
/// el reproductor anclado. Hasta entonces el botón está apagado y dice por
/// qué, sin fingir nada. La segunda parte cambia solo esto: lo prende cuando
/// el audio está, y lo muestra generándose mientras tanto.
class PodcastListenButton extends StatelessWidget {
  const PodcastListenButton({
    required this.creation,
    required this.podcast,
    super.key,
  });

  final StudyCreation creation;
  final Podcast podcast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
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
          onPressed: null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(l10n.f47P6Listen),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.f47P6AudioPending,
          key: const Key('podcast-audio-pending'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
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
          // Cada tramo, un nodo propio que dice quién habla y qué dice.
          Semantics(
            container: true,
            label: conversation ? '$name: ${segment.text}' : segment.text,
            excludeSemantics: true,
            child: Text(
              segment.text,
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
