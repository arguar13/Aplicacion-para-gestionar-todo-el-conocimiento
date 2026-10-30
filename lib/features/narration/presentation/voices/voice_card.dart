import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una voz de la biblioteca (F47, paso 3): su cara, su nombre con la bandera
/// del acento, sus rasgos, de dónde es, ♡ favorita y ▶ una muestra.
///
/// Tocarla la elige para leer ([onSelect]) si ya puede leer; una sin conexión
/// todavía sin bajar dice cuánto pesa y se baja **solo con su botón**: tocar
/// la tarjeta no baja nada.
///
/// A 360 dp con la letra al doble, los botones bajan a su propia línea en vez
/// de apretar el nombre.
class VoiceCard extends ConsumerWidget {
  const VoiceCard({
    required this.voice,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final VoiceProfile voice;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final installed = ref.watch(installedVoiceIdsProvider);
    final ready = isVoiceReady(voice, installed);
    final favorite = ref.watch(
      voiceFavoritesProvider.select((ids) => ids.contains(voice.id)),
    );
    final sampling = ref.watch(voiceSampleProvider) == voice.id;
    final sample = voiceSampleOf(voice, installed);
    final title = voiceTitle(voice, l10n);
    final traits = voiceTraitsLine(voice, l10n);
    final origin = voiceOriginLine(voice, l10n, ready: ready);

    return Card(
      key: Key('voice-card-${voice.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // La tarjeta entera es un botón para el lector de pantalla, con su
          // nombre, sus rasgos y de dónde es; los botones de abajo, aparte.
          Semantics(
            button: ready,
            selected: selected,
            label: [l10n.f47P3VoiceSemantics(title), traits, origin].join(', '),
            excludeSemantics: true,
            child: InkWell(
              onTap: ready ? onSelect : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VoiceFaceView.of(voice),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            traits,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              for (final purpose in voice.purposes.take(1)) ...[
                                Icon(purpose.icon, size: 16),
                                const SizedBox(width: 4),
                              ],
                              Icon(
                                voiceOriginIcon(voice.origin),
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  origin,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                IconButton(
                  key: Key('voice-favorite-${voice.id}'),
                  tooltip: favorite ? l10n.f47P3Unfavorite : l10n.f47P3Favorite,
                  isSelected: favorite,
                  selectedIcon: Icon(
                    Icons.favorite_rounded,
                    color: scheme.primary,
                  ),
                  icon: const Icon(Icons.favorite_border_rounded),
                  onPressed: () => unawaited(
                    ref.read(voiceFavoritesProvider.notifier).toggle(voice.id),
                  ),
                ),
                if (sample != null)
                  IconButton(
                    key: Key('voice-sample-${voice.id}'),
                    tooltip: sampling
                        ? l10n.f47P3StopSample
                        : l10n.f47P3PlaySample,
                    icon: Icon(
                      sampling
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline_rounded,
                    ),
                    onPressed: () => unawaited(
                      ref.read(voiceSampleProvider.notifier).toggle(voice),
                    ),
                  ),
                if (voice.origin == VoiceOrigin.offline && !ready)
                  _DownloadControls(voice: voice),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bajar una voz sin conexión, y cómo va: el botón con su tamaño, el avance
/// con «Pausar» y «Cancelar», la pausa con «Seguir», o por qué falló.
class _DownloadControls extends ConsumerWidget {
  const _DownloadControls({required this.voice});

  final VoiceProfile voice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final package = voice.offline!.package;
    final actions = ref.watch(offlineVoiceActionsProvider);
    if (actions == null) return const SizedBox.shrink();
    final state = ref.watch(offlineVoiceDownloadProvider(package.id));
    final size = formatFileSize(package.bytes, l10n.localeName);

    Widget status(String text) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return switch (state) {
      ModelDownloadIdle() => FilledButton.tonalIcon(
        key: Key('voice-download-${voice.id}'),
        icon: const Icon(Icons.download_rounded),
        label: Text(l10n.f47P3Download(size)),
        onPressed: () => actions.download(package),
      ),
      ModelDownloadRunning(:final progress) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Semantics(
            liveRegion: true,
            child: status(
              progress >= 0.9
                  ? l10n.f47P3Preparing
                  : l10n.f47P3Downloading((progress / 0.9 * 100).floor()),
            ),
          ),
          if (actions.canPause && progress < 0.9)
            TextButton(
              key: Key('voice-pause-${voice.id}'),
              onPressed: () => unawaited(actions.pause(package)),
              child: Text(l10n.f47P3Pause),
            ),
          if (progress < 0.9)
            TextButton(
              key: Key('voice-cancel-${voice.id}'),
              onPressed: () => unawaited(actions.cancel(package)),
              child: Text(l10n.f47P3Cancel),
            ),
        ],
      ),
      ModelDownloadPaused(:final progress) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          status(l10n.f47P3Paused((progress / 0.9 * 100).floor())),
          TextButton(
            onPressed: () => actions.download(package),
            child: Text(l10n.f47P3Resume),
          ),
          TextButton(
            onPressed: () => unawaited(actions.cancel(package)),
            child: Text(l10n.f47P3Cancel),
          ),
        ],
      ),
      ModelDownloadFailed(:final error) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          status(
            error is InsufficientStorageException
                ? l10n.f47P3DownloadNoSpace
                : l10n.f47P3DownloadFailed,
          ),
          TextButton(
            key: Key('voice-retry-${voice.id}'),
            onPressed: () => actions.download(package),
            child: Text(l10n.f47P3Retry),
          ),
        ],
      ),
    };
  }
}
