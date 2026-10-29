import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Una opción de [CreationSegmented].
@immutable
class CreationSegment<T> {
  const CreationSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Los botones segmentados con ✓ de las hojas de lo creado (F43), como los
/// de NotebookLM: «Menos · ✓ Estándar · Más».
///
/// Si las opciones entran en una fila, van unidas en una sola píldora; si no
/// entran —un teléfono angosto con letra grande, una traducción más larga—,
/// cada una pasa a ser su propia píldora y bajan de renglón, sin cortar
/// ninguna. Se mide con el mismo tamaño de letra que se va a dibujar.
class CreationSegmented<T> extends StatelessWidget {
  const CreationSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'segment',
    super.key,
  });

  final List<CreationSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Cada opción lleva la clave `<keyPrefix>-<valor>`.
  final String keyPrefix;

  static const double _height = 44;
  static const double _horizontalPadding = 14;
  static const double _checkWidth = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge!;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Unidas, las opciones se reparten el ancho por igual: entran si la
        // más larga entra en su parte. Cada una con lugar para el ✓ aunque
        // no esté elegida, así elegir otra no cambia el ancho de nadie.
        var widest = 0.0;
        for (final segment in segments) {
          final painter = TextPainter(
            text: TextSpan(text: segment.label, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          widest = math.max(
            widest,
            painter.width + _horizontalPadding * 2 + _checkWidth,
          );
          painter.dispose();
        }
        // Los separadores de 1 y el borde de afuera.
        final joined =
            widest * segments.length + segments.length + 1 <=
            constraints.maxWidth;
        if (joined) return _joined(context);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final segment in segments)
              _pill(context, segment, BorderRadius.circular(_height / 2)),
          ],
        );
      },
    );
  }

  Widget _joined(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_height / 2),
        border: Border.all(color: outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_height / 2),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, color: outline),
                Expanded(
                  child: _segment(context, segments[i], BorderRadius.zero),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    CreationSegment<T> segment,
    BorderRadius radius,
  ) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: outline),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: _segment(context, segment, radius),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    CreationSegment<T> segment,
    BorderRadius radius,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = segment.value == selected;
    final foreground = isSelected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          key: ValueKey('$keyPrefix-${segment.value}'),
          onTap: () => onChanged(segment.value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _height),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _horizontalPadding,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected) ...[
                    Icon(Icons.check, size: 18, color: foreground),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      segment.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: foreground),
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

/// La ✕ redonda de arriba a la derecha de las hojas de lo creado.
class CreationCloseButton extends StatelessWidget {
  const CreationCloseButton({required this.tooltip, this.onPressed, super.key});

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        shape: const CircleBorder(),
      ),
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.close),
    );
  }
}

/// El título de una sección de una hoja de lo creado: chico, tenue y
/// con aire arriba, como los de NotebookLM.
class CreationSectionLabel extends StatelessWidget {
  const CreationSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
