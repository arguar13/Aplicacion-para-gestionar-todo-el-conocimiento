import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/youtube_audio_download.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El audio de un video de YouTube, debajo de su vista previa, en el mismo
/// reproductor que un audio del teléfono (F24): ±10 s, velocidad, el mini
/// reproductor y el texto que sigue al audio en amarillo.
///
/// Se baja **solo**, sin botón —apenas el video queda listo, o al abrirlo
/// si todavía no lo tiene— y en la mejor calidad que ofrece YouTube
/// (decisión A de F24). Mientras baja se ve cuánto va; si no se pudo, el
/// motivo y "Reintentar".
///
/// Debajo de la vista previa del video, no en su lugar: el video es el
/// original, y lo principal del detalle es el original.
class YouTubeAudioDownloadSection extends ConsumerStatefulWidget {
  const YouTubeAudioDownloadSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  ConsumerState<YouTubeAudioDownloadSection> createState() =>
      _YouTubeAudioDownloadSectionState();
}

class _YouTubeAudioDownloadSectionState
    extends ConsumerState<YouTubeAudioDownloadSection> {
  @override
  void initState() {
    super.initState();
    // Un video que todavía no tiene su audio —procesado antes de F24, o
    // cuya descarga se cortó al cerrarse la app— lo baja al abrirse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !needsYouTubeAudio(widget.item)) return;
      final itemId = widget.item.id;
      if (ref.read(youTubeAudioDownloadProvider(itemId)) is AudioDownloadIdle) {
        unawaited(
          ref.read(youTubeAudioDownloadProvider(itemId).notifier).start(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final downloaded = item.source.originalFilePath;
    if (downloaded != null) return _DownloadedAudio(relativePath: downloaded);

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final itemId = item.id;
    final state = ref.watch(youTubeAudioDownloadProvider(itemId));
    final notifier = ref.read(youTubeAudioDownloadProvider(itemId).notifier);

    return switch (state) {
      AudioDownloadFailed(:final reason) => Row(
        children: [
          Expanded(
            child: Text(
              failureMessage(l10n, reason) ?? l10n.youtubeAudioFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(notifier.start()),
            child: Text(l10n.detailRetry),
          ),
        ],
      ),
      // Bajando, o por empezar: lo mismo, sin un botón de por medio.
      AudioDownloading(:final fraction) => _Progress(fraction: fraction),
      AudioDownloadIdle() => const _Progress(fraction: null),
    };
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.fraction});

  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fraction = this.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: fraction, minHeight: 6),
        ),
        const SizedBox(height: 8),
        Text(
          fraction == null
              ? l10n.youtubeAudioDownloadingUnknown
              : l10n.youtubeAudioDownloading((fraction * 100).floor()),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
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
