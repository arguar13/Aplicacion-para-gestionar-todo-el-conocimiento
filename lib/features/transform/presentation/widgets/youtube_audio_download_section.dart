import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/youtube_audio_download.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El audio de un video de YouTube, para escucharlo sin conexión: se baja
/// solo si el usuario lo pide (F21, decisión B) —el video ya está listo con
/// su transcripción—, y una vez bajado se escucha acá.
///
/// Debajo de la vista previa del video, no en su lugar: el video es el
/// original, y lo principal del detalle es el original.
class YouTubeAudioDownloadSection extends ConsumerWidget {
  const YouTubeAudioDownloadSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = item.source.originalFilePath;
    if (downloaded != null) return _DownloadedAudio(relativePath: downloaded);

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final itemId = item.id;
    final state = ref.watch(youTubeAudioDownloadProvider(itemId));
    final notifier = ref.read(youTubeAudioDownloadProvider(itemId).notifier);

    return switch (state) {
      AudioDownloading(:final fraction) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: fraction, minHeight: 6),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  fraction == null
                      ? l10n.youtubeAudioDownloadingUnknown
                      : l10n.youtubeAudioDownloading((fraction * 100).floor()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: notifier.cancel,
                child: Text(l10n.youtubeAudioCancel),
              ),
            ],
          ),
        ],
      ),
      AudioDownloadFailed(:final reason) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failureMessage(l10n, reason) ?? l10n.youtubeAudioFailed,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          _DownloadButton(onPressed: () => unawaited(notifier.start())),
        ],
      ),
      AudioDownloadIdle() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DownloadButton(onPressed: () => unawaited(notifier.start())),
          const SizedBox(height: 4),
          Text(
            l10n.youtubeAudioDownloadHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    };
  }
}

/// El reproductor del audio ya bajado.
class _DownloadedAudio extends ConsumerWidget {
  const _DownloadedAudio({required this.relativePath});

  final String relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final path = ref.watch(_resolvedPathProvider(relativePath));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.youtubeAudioDownloaded,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (path case AsyncData(:final value))
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: MediaPlayerView(path: value, isVideo: false),
            ),
          ),
      ],
    );
  }
}

final _resolvedPathProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, relativePath) => ref.read(fileStoreProvider).resolve(relativePath),
);

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.headphones, size: 18),
      label: Text(l10n.youtubeAudioDownloadAction),
    );
  }
}
