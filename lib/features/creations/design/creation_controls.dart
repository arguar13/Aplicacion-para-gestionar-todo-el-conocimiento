import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';

/// Una opción de [CreationSegmented].
@immutable
class CreationSegment<T> {
  const CreationSegment({required this.value, required this.label, this.id});

  final T value;
  final String label;

  /// Lo que distingue la opción en su clave; sin esto, el nombre del valor.
  final String? id;

  String get keyId => id ?? (value is Enum ? (value as Enum).name : '$value');
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

  /// Cada opción lleva la clave `keyPrefix-id` (ver [CreationSegment.id]).
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
          key: ValueKey('$keyPrefix-${segment.keyId}'),
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

/// Una muestra de paleta para elegir (F43): sus colores en franjas, en una
/// píldora redonda; sin colores, la del color propio: un arcoíris. La usan
/// las hojas de diseño del mazo y de la infografía.
class CreationSwatch extends StatelessWidget {
  const CreationSwatch({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          width: 64,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (colors.isEmpty)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SweepGradient(
                        colors: [
                          Color(0xFFE53935),
                          Color(0xFFFDD835),
                          Color(0xFF43A047),
                          Color(0xFF1E88E5),
                          Color(0xFF8E24AA),
                          Color(0xFFE53935),
                        ],
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      for (final color in colors)
                        Expanded(child: ColoredBox(color: color)),
                    ],
                  ),
                if (selected)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: CreationContrast.readableOn(scheme.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una tipografía para elegir (F43): «Aa» en su letra de títulos y su
/// nombre.
class CreationFontChoice extends StatelessWidget {
  const CreationFontChoice({
    required this.pair,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CreationFontPair pair;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Aa',
                    style: pair.displayStyle(size: 26, color: foreground),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        Icon(Icons.check, size: 16, color: foreground),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground,
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
      ),
    );
  }
}

/// El deslizador del tono de un color propio (F43): un arcoíris con una
/// perilla blanca. Lo usan las hojas de diseño del mazo y de la infografía.
class CreationHueSlider extends StatelessWidget {
  const CreationHueSlider({
    required this.hue,
    required this.onChanged,
    required this.semanticLabel,
    this.sliderKey,
    super.key,
  });

  /// De 0 a 359.
  final double hue;
  final ValueChanged<double> onChanged;

  /// Lo que dice el lector de pantalla antes de los grados («Tono 210°»).
  final String semanticLabel;

  /// La clave del `Slider` de adentro (para arrastrarlo en una prueba).
  final Key? sliderKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            for (var h = 0; h <= 360; h += 60)
              HSLColor.fromAHSL(1, h % 360, 0.7, 0.55).toColor(),
          ],
        ),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
          thumbColor: Colors.white,
          overlayColor: Colors.white24,
        ),
        child: Slider(
          key: sliderKey,
          value: hue.clamp(0, 359),
          max: 359,
          semanticFormatterCallback: (value) =>
              '$semanticLabel ${value.round()}°',
          onChanged: onChanged,
        ),
      ),
    );
  }
}
