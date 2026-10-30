import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:sinapsis/features/narration/domain/read_aloud/read_aloud_speed.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «1,0×» en español, «1.0×» en inglés: la velocidad del lector siempre con
/// su décima, como en la regla (F47, paso 2).
String formatReadAloudSpeed(double speed, String locale) =>
    '${NumberFormat('0.0', locale).format(speed)}×';

/// La velocidad del lector en voz alta (F47, paso 2, captura 15): la cifra
/// en grande, **una regla de 0,5× a 3×** que se arrastra de costado, con − y
/// + a los lados, y los atajos 1,0 · 1,2 · 1,5 · 2,0 · 3,0, sin candados
/// (decisión H).
///
/// Los botones y los atajos se aplican en el acto; la regla, al soltarla:
/// cada cambio de velocidad le hace retomar la frase al motor de voz, y
/// arrastrar no tiene que tartamudear.
class ReadAloudSpeedSheet extends ConsumerStatefulWidget {
  const ReadAloudSpeedSheet({super.key});

  @override
  ConsumerState<ReadAloudSpeedSheet> createState() =>
      _ReadAloudSpeedSheetState();
}

class _ReadAloudSpeedSheetState extends ConsumerState<ReadAloudSpeedSheet> {
  /// Lo que marca la regla mientras se arrastra; `null` sin arrastrar.
  double? _dragging;

  void _set(double speed) {
    unawaited(
      ref
          .read(readAloudControllerProvider.notifier)
          .setSpeed(snapReadAloudSpeed(speed)),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.mediaPlayerSpeed,
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // La cifra la dice la regla al lector de pantalla.
            ExcludeSemantics(
              child: Text(
                formatReadAloudSpeed(speed, locale),
                key: const Key('read-aloud-speed-value'),
                style: text.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  key: const Key('read-aloud-speed-down'),
                  tooltip: l10n.f47P2SpeedSlower,
                  onPressed: speed > readAloudMinSpeed
                      ? () => _set(speed - readAloudSpeedStep)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: SpeedRuler(
                    key: const Key('read-aloud-speed-ruler'),
                    value: speed,
                    label: l10n.f47P2SpeedRuler,
                    format: (value) => formatReadAloudSpeed(value, locale),
                    onChanged: (value) => setState(() => _dragging = value),
                    onChangeEnd: (value) {
                      _set(value);
                      setState(() => _dragging = null);
                    },
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('read-aloud-speed-up'),
                  tooltip: l10n.f47P2SpeedFaster,
                  onPressed: speed < readAloudMaxSpeed
                      ? () => _set(speed + readAloudSpeedStep)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in readAloudSpeedPresets)
                  ChoiceChip(
                    key: Key('read-aloud-speed-$preset'),
                    label: Text(formatReadAloudSpeed(preset, locale)),
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

/// La regla de la velocidad (F47, paso 2): las marcas de 0,5× a 3× pasan
/// por debajo de una aguja fija en el medio, como una cinta métrica. Se
/// arrastra de costado —hacia la izquierda, más rápido— y marca de a una
/// décima, con las mayores en cada media.
///
/// Mientras se arrastra avisa por [onChanged], ya en su décima; al soltar,
/// por [onChangeEnd]. Para el lector de pantalla es un control deslizante:
/// dice la cifra y sube o baja una décima.
class SpeedRuler extends StatefulWidget {
  const SpeedRuler({
    required this.value,
    required this.label,
    required this.format,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final double value;
  final String label;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  /// Cuánto se corre la cinta por cada décima.
  static const tickSpacing = 14.0;

  @override
  State<SpeedRuler> createState() => _SpeedRulerState();
}

class _SpeedRulerState extends State<SpeedRuler> {
  /// Lo arrastrado, sin llevar a la décima: así la cinta sigue al dedo.
  double? _raw;

  double get _value => _raw ?? widget.value;

  void _drag(DragUpdateDetails details) {
    final raw =
        (_value -
                details.delta.dx / SpeedRuler.tickSpacing * readAloudSpeedStep)
            .clamp(readAloudMinSpeed, readAloudMaxSpeed);
    final before = snapReadAloudSpeed(_value);
    setState(() => _raw = raw);
    final after = snapReadAloudSpeed(raw);
    if (after != before) widget.onChanged(after);
  }

  void _end() {
    final value = snapReadAloudSpeed(_value);
    setState(() => _raw = null);
    widget.onChangeEnd(value);
  }

  void _step(double delta) {
    final next = snapReadAloudSpeed(widget.value + delta);
    if (next != widget.value) widget.onChangeEnd(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelMedium!.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final scaler = MediaQuery.textScalerOf(context);
    final labelHeight = scaler.scale(labelStyle.fontSize ?? 12) * 1.4;
    final value = snapReadAloudSpeed(widget.value);

    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.format(value),
      increasedValue: value < readAloudMaxSpeed
          ? widget.format(snapReadAloudSpeed(value + readAloudSpeedStep))
          : null,
      decreasedValue: value > readAloudMinSpeed
          ? widget.format(snapReadAloudSpeed(value - readAloudSpeedStep))
          : null,
      onIncrease: value < readAloudMaxSpeed
          ? () => _step(readAloudSpeedStep)
          : null,
      onDecrease: value > readAloudMinSpeed
          ? () => _step(-readAloudSpeedStep)
          : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // La cinta sigue al dedo desde que se apoya, sin saltar al pasar
          // el umbral del arrastre.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragUpdate: _drag,
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          child: SizedBox(
            height: 40 + labelHeight,
            child: CustomPaint(
              painter: _RulerPainter(
                value: _value,
                tick: scheme.outline,
                needle: scheme.primary,
                labelStyle: labelStyle,
                textScaler: scaler,
                textDirection: Directionality.of(context),
                format: (value) => NumberFormat(
                  '0.0',
                  Localizations.localeOf(context).toString(),
                ).format(value),
                labelHeight: labelHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.value,
    required this.tick,
    required this.needle,
    required this.labelStyle,
    required this.textScaler,
    required this.textDirection,
    required this.format,
    required this.labelHeight,
  });

  final double value;
  final Color tick;
  final Color needle;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final String Function(double) format;
  final double labelHeight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final center = size.width / 2;
    final ticks = Paint()
      ..color = tick
      ..strokeCap = StrokeCap.round;
    final steps = ((readAloudMaxSpeed - readAloudMinSpeed) / readAloudSpeedStep)
        .round();
    for (var i = 0; i <= steps; i++) {
      final at = readAloudMinSpeed + i * readAloudSpeedStep;
      final x =
          center + (at - value) / readAloudSpeedStep * SpeedRuler.tickSpacing;
      if (x < -SpeedRuler.tickSpacing ||
          x > size.width + SpeedRuler.tickSpacing) {
        continue;
      }
      // Una marca mayor en cada media: 0,5, 1,0, 1,5…
      final major = i % 5 == 0;
      ticks.strokeWidth = major ? 2 : 1.2;
      final height = major ? 22.0 : 12.0;
      canvas.drawLine(Offset(x, 4), Offset(x, 4 + height), ticks);
      if (!major) continue;
      final label = TextPainter(
        text: TextSpan(text: format(at), style: labelStyle),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      label.paint(
        canvas,
        Offset(x - label.width / 2, size.height - labelHeight),
      );
      label.dispose();
    }
    final needlePaint = Paint()
      ..color = needle
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center, 0), Offset(center, 32), needlePaint);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.value != value ||
      old.tick != tick ||
      old.needle != needle ||
      old.labelStyle != labelStyle ||
      old.textScaler != textScaler ||
      old.labelHeight != labelHeight;
}
