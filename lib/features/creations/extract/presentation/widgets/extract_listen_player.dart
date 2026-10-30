import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart'
    show formatSpeed;
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El modo escuchar de los visores de extraer (F43, paso 7, M8): un
/// reproductor grande y elegante, abajo, sobre el lector en voz alta de
/// siempre (F25, F39, decisión 86) —el mismo motor, la misma posición, el
/// mismo amarillo—, con otra piel:
///
/// - qué se lee —el documento, con varios— y por dónde va: «3 de 40»;
/// - la barra de avance, que se arrastra y salta al soltarla;
/// - la oración anterior y la siguiente alrededor de reproducir o pausar,
///   grande y en el color del tipo;
/// - la velocidad y la voz, con las hojas de siempre.
///
/// [accent] es el color del ícono del tipo; [titleOf] dice de qué documento
/// es lo que suena (por la clave de su texto).
class ExtractListenPlayer extends ConsumerWidget {
  const ExtractListenPlayer({
    required this.accent,
    required this.titleOf,
    super.key,
  });

  final Color accent;
  final String Function(String sourceKey) titleOf;

  /// El lado del botón de reproducir.
  static const playSize = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final controller = ref.read(readAloudControllerProvider.notifier);
    final (playing, failed, index, count, sourceKey) = ref.watch(
      readAloudControllerProvider.select(
        (s) => (
          s.playing,
          s.failed,
          s.segmentIndex,
          s.segments.length,
          s.currentSegment?.sourceKey,
        ),
      ),
    );
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final status = failed
        ? l10n.readAloudFailed
        : playing
        ? l10n.readAloudReading
        : l10n.readAloudPaused;
    final title = sourceKey == null ? '' : titleOf(sourceKey);

    return Semantics(
      container: true,
      label: l10n.f43TextPlayer,
      child: Material(
        key: const Key('extract-player'),
        color: scheme.surfaceContainerHigh,
        elevation: 3,
        shadowColor: scheme.shadow.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        playing
                            ? Icons.graphic_eq_rounded
                            : Icons.headphones_rounded,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title.isNotEmpty)
                            Text(
                              title,
                              key: const Key('extract-player-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            count == 0
                                ? status
                                : l10n.f43TextListenStatus(
                                    status,
                                    l10n.f43TextListenPosition(
                                      index + 1,
                                      count,
                                    ),
                                  ),
                            key: const Key('extract-player-status'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: failed
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CreationCloseButton(
                      key: const Key('extract-player-close'),
                      tooltip: l10n.f43TextListenStop,
                      onPressed: () => unawaited(controller.close()),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const _SeekBar(),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _SpeedButton(
                          onPressed: () =>
                              _openSheet(context, const ReadAloudSpeedSheet()),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('extract-player-previous'),
                      tooltip: l10n.f43TextListenPrevious,
                      iconSize: 32,
                      onPressed: () => unawaited(controller.previousSegment()),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      key: const Key('extract-player-play'),
                      tooltip: playing
                          ? l10n.mediaPlayerPause
                          : l10n.mediaPlayerPlay,
                      iconSize: 36,
                      style: IconButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        fixedSize: const Size.square(playSize),
                      ),
                      onPressed: () => unawaited(controller.togglePlay()),
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      key: const Key('extract-player-next'),
                      tooltip: l10n.f43TextListenNext,
                      iconSize: 32,
                      onPressed: () => unawaited(controller.nextSegment()),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          key: const Key('extract-player-voice'),
                          tooltip: l10n.readAloudVoice,
                          onPressed: () => unawaited(showVoiceLibrary(context)),
                          icon: const Icon(Icons.record_voice_over_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Una de las hojas de siempre del lector —la velocidad, la voz—, sin
  /// deslizarse si se apagaron las animaciones.
  void _openSheet(BuildContext context, Widget sheet) {
    final still = MediaQuery.disableAnimationsOf(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
        builder: (_) => sheet,
      ),
    );
  }
}

/// La velocidad, «1,25×»: abre la hoja de la velocidad. Con la letra grande
/// se achica antes que empujar los botones del medio.
class _SpeedButton extends ConsumerWidget {
  const _SpeedButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final speed = ref.watch(readAloudControllerProvider.select((s) => s.speed));
    return Tooltip(
      message: l10n.mediaPlayerSpeed,
      child: FilledButton.tonal(
        key: const Key('extract-player-speed'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        onPressed: onPressed,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(formatSpeed(speed, locale)),
        ),
      ),
    );
  }
}

/// La barra de avance: cuánto se leyó, y arrastrarla lleva la lectura ahí al
/// soltarla (`ReadAloudController.seekToFraction`). Mientras se arrastra se
/// ve dónde va a caer; lo que suena no se mueve hasta soltar. Lo único del
/// reproductor que se redibuja palabra por palabra.
class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar();

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = ref.watch(
      readAloudControllerProvider.select((s) => s.progress),
    );
    final value = (_dragging ?? progress).clamp(0.0, 1.0);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      child: Slider(
        key: const Key('extract-player-seek'),
        value: value,
        semanticFormatterCallback: (v) =>
            '${l10n.f43TextListenSeek}: ${(v * 100).round()} %',
        onChanged: (v) => setState(() => _dragging = v),
        onChangeEnd: (v) {
          setState(() => _dragging = null);
          unawaited(
            ref.read(readAloudControllerProvider.notifier).seekToFraction(v),
          );
        },
      ),
    );
  }
}
