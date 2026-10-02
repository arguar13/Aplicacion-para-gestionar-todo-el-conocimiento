import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart'
    show formatSpeed, mediaSpeedStep;
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La velocidad más lenta y la más rápida del lector flotante: lo que el
/// motor de voz entiende sin deformar la voz.
const readAloudMinSpeed = 0.5;
const readAloudMaxSpeed = 2.0;

/// Las velocidades a un toque.
const readAloudSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// [speed] redondeada al paso del ajuste fino —el mismo del reproductor de
/// audio— y dentro de los límites del lector.
double clampReadAloudSpeed(double speed) {
  final steps = (speed / mediaSpeedStep).round();
  return (steps * mediaSpeedStep).clamp(readAloudMinSpeed, readAloudMaxSpeed);
}

/// El panel de la velocidad del lector flotante (F25): el mismo del
/// reproductor de audio —`MediaSpeedSheet`, el valor en grande, menos y más
/// con la barra entre medio, y las de siempre a un toque—, de 0,5× a 2×.
///
/// Los botones y las velocidades a un toque se aplican en el acto; la barra,
/// al soltarla: cada cambio de velocidad le hace retomar la frase al motor de
/// voz, y arrastrar no tiene que tartamudear.
class ReadAloudSpeedSheet extends ConsumerStatefulWidget {
  const ReadAloudSpeedSheet({super.key});

  @override
  ConsumerState<ReadAloudSpeedSheet> createState() =>
      _ReadAloudSpeedSheetState();
}

class _ReadAloudSpeedSheetState extends ConsumerState<ReadAloudSpeedSheet> {
  /// Lo que marca la barra mientras se arrastra; `null` sin arrastrar.
  double? _dragging;

  void _set(double speed) {
    unawaited(
      ref
          .read(readAloudControllerProvider.notifier)
          .setSpeed(clampReadAloudSpeed(speed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = ref.watch(
      readAloudControllerProvider.select((s) => s.speed),
    );
    final speed = _dragging ?? current;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.mediaPlayerSpeed, style: text.titleMedium),
            const SizedBox(height: 12),
            Text(
              formatSpeed(speed, locale),
              key: const Key('read-aloud-speed-value'),
              style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  key: const Key('read-aloud-speed-down'),
                  tooltip: l10n.mediaPlayerSpeedDown,
                  onPressed: speed > readAloudMinSpeed
                      ? () => _set(speed - mediaSpeedStep)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Slider(
                    min: readAloudMinSpeed,
                    max: readAloudMaxSpeed,
                    divisions:
                        ((readAloudMaxSpeed - readAloudMinSpeed) /
                                mediaSpeedStep)
                            .round(),
                    value: speed.clamp(readAloudMinSpeed, readAloudMaxSpeed),
                    onChanged: (value) =>
                        setState(() => _dragging = clampReadAloudSpeed(value)),
                    onChangeEnd: (value) {
                      _set(value);
                      setState(() => _dragging = null);
                    },
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('read-aloud-speed-up'),
                  tooltip: l10n.mediaPlayerSpeedUp,
                  onPressed: speed < readAloudMaxSpeed
                      ? () => _set(speed + mediaSpeedStep)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in readAloudSpeedPresets)
                  ChoiceChip(
                    key: Key('read-aloud-speed-$preset'),
                    label: Text(
                      preset == 1.0
                          ? l10n.mediaPlayerSpeedNormal
                          : formatSpeed(preset, locale),
                    ),
                    selected: (speed - preset).abs() < 0.001,
                    selectedColor: scheme.primaryContainer,
                    onSelected: (_) => _set(preset),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
