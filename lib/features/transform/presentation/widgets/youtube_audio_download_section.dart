import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/transform/presentation/providers/youtube_audio_download.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El audio de un video de YouTube, en el panel de la fuente debajo de su
/// vista previa (F26, decisión B), en el mismo reproductor que un audio del
/// teléfono (F24): ±10 s, velocidad, el mini reproductor y el texto que
/// sigue al audio en amarillo.
///
/// Se baja **solo**, sin botón —apenas el video queda listo, o al abrirlo
/// si todavía no lo tiene— y en la mejor calidad que ofrece YouTube
/// (decisión A de F24). Mientras baja, el panel muestra cuánto va en su
/// franja de estado; si no se pudo, el motivo y "Reintentar"; ya bajado, el
/// reproductor.
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

    // Del avance al reproductor con un fundido: es la misma sección del
    // panel que cambia de estado, no algo nuevo que aparece.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: downloaded != null
          ? _DownloadedAudio(
              key: const ValueKey('downloaded'),
              relativePath: downloaded,
            )
          : _Downloading(key: const ValueKey('downloading'), itemId: item.id),
    );
  }
}

/// Bajando, por empezar o fallido: la franja de estado del panel.
class _Downloading extends ConsumerWidget {
  const _Downloading({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(youTubeAudioDownloadProvider(itemId));
    final notifier = ref.read(youTubeAudioDownloadProvider(itemId).notifier);

    return switch (state) {
      AudioDownloadFailed(:final reason) => SourcePanelStatus(
        icon: Icons.music_off_outlined,
        tone: SourcePanelTone.error,
        message: failureMessage(l10n, reason) ?? l10n.youtubeAudioFailed,
        // Un bloqueo de YouTube no se arregla reintentando.
        action: reason == ProcessingFailureReason.downloadBlocked
            ? null
            : SourcePanelStatusButton(
                icon: Icons.refresh,
                label: l10n.detailRetry,
                onPressed: () => unawaited(notifier.start()),
              ),
      ),
      // Bajando, o por empezar: lo mismo, sin un botón de por medio.
      AudioDownloading(:final fraction) => _progress(l10n, fraction),
      AudioDownloadIdle() => _progress(l10n, null),
    };
  }

  Widget _progress(AppLocalizations l10n, double? fraction) =>
      SourcePanelStatus(
        icon: Icons.downloading,
        message: fraction == null
            ? l10n.youtubeAudioDownloadingUnknown
            : l10n.youtubeAudioDownloading((fraction * 100).floor()),
        progress: SourcePanelProgressBar(value: fraction),
      );
}

/// El reproductor del audio ya bajado.
class _DownloadedAudio extends ConsumerWidget {
  const _DownloadedAudio({required this.relativePath, super.key});

  final String relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final path = ref.watch(_resolvedPathProvider(relativePath)).valueOrNull;

    return SourcePanelAudio(path: path, subtitle: l10n.youtubeAudioDownloaded);
  }
}

final _resolvedPathProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, relativePath) => ref.read(fileStoreProvider).resolve(relativePath),
);
