import 'package:flutter/material.dart';

/// «─── Lo creado ───»: una línea que corta la pantalla con su nombre en el
/// medio (F46, paso 5h). El «Lo creado» de Repasar y el «o» de Capturar.
///
/// **Las dos líneas miden siempre lo mismo**: cada una es un `Expanded` igual,
/// y el texto va entre ellas con lo que mide. Así el nombre queda en el centro
/// de la fila, sea corto o largo. Antes, el texto iba en un `Flexible` suelto
/// con tres partes de cinco: se quedaba con lo que medía, pero lo que le
/// sobraba de sus tres quintos no volvía a las líneas, y quedaba vacío al final
/// —la línea de la derecha terminaba en la mitad de la pantalla—.
///
/// Un nombre largo, o con la letra grande, no se come las líneas: ocupa como
/// mucho [maxLabelFraction] del ancho y sigue en renglones, centrados.
class LabeledDivider extends StatelessWidget {
  const LabeledDivider({
    required this.label,
    this.style,
    this.maxLabelFraction = 0.6,
    super.key,
  }) : assert(
         maxLabelFraction > 0 && maxLabelFraction < 1,
         'El nombre ocupa una parte del ancho, no todo ni nada.',
       );

  final String label;

  /// La letra del nombre; sin esto, la chica de la pantalla, en el color de lo
  /// secundario.
  final TextStyle? style;

  /// La parte del ancho que puede ocupar el nombre, como mucho.
  final double maxLabelFraction;

  /// Lo que separa el nombre de cada línea.
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = Expanded(child: Divider(color: scheme.outlineVariant));
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          line,
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * maxLabelFraction,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: gap),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style:
                    style ??
                    theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}
