import 'package:flutter/material.dart';

/// Un lienzo de tamaño lógico fijo —1920×1080 una diapositiva, por ejemplo—
/// dibujado a cualquier tamaño (F43).
///
/// Lo creado se compone una sola vez, en el tamaño de [logicalSize], y
/// después se escala entero para caber donde se lo ponga: la miniatura de la
/// galería, el visor del teléfono, la pantalla completa o la imagen del PDF.
/// Así una diapositiva se ve idéntica en todos lados —lo que en una
/// miniatura entra en dos líneas entra en dos líneas en el PDF— y el texto
/// se ajusta una sola vez, contra el lienzo, no contra cada pantalla.
///
/// Adentro el texto no sigue el tamaño de letra del sistema: una diapositiva
/// es como una imagen, que se agranda entera (con pellizco o en pantalla
/// completa). El texto grande sí rige en todo lo que la rodea.
class CreationCanvas extends StatelessWidget {
  const CreationCanvas({
    required this.logicalSize,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.shadow = false,
    super.key,
  });

  final Size logicalSize;
  final Widget child;

  /// El redondeo de las esquinas, en píxeles de pantalla (no del lienzo).
  final BorderRadius borderRadius;

  /// Una sombra suave alrededor, para que la diapositiva flote.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = CreationCanvasMath.fittedSize(
          logicalSize,
          constraints.biggest,
        );
        Widget canvas = SizedBox.fromSize(
          size: size,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
              size: logicalSize,
              child: MediaQuery(
                data: (MediaQuery.maybeOf(context) ?? const MediaQueryData())
                    .copyWith(textScaler: TextScaler.noScaling),
                child: child,
              ),
            ),
          ),
        );
        // Siempre recortado: un adorno que asoma del borde (un recorte de
        // papel, un resplandor) no se dibuja sobre lo que haya al lado.
        canvas = borderRadius == BorderRadius.zero
            ? ClipRect(child: canvas)
            : ClipRRect(borderRadius: borderRadius, child: canvas);
        if (shadow) {
          canvas = DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: canvas,
          );
        }
        return Center(child: canvas);
      },
    );
  }
}

/// Las cuentas del escalado de un lienzo lógico.
abstract final class CreationCanvasMath {
  /// La escala con que [logical] cabe entero en [available] sin deformarse.
  /// Si [available] no tiene alto (una lista que se desplaza), solo cuenta el
  /// ancho; sin ancho ni alto, 1.
  static double fitScale(Size logical, Size available) {
    final byWidth = available.width.isFinite
        ? available.width / logical.width
        : double.infinity;
    final byHeight = available.height.isFinite
        ? available.height / logical.height
        : double.infinity;
    final scale = byWidth < byHeight ? byWidth : byHeight;
    return scale.isFinite ? scale : 1;
  }

  /// El tamaño en pantalla de [logical] escalado para caber en [available].
  static Size fittedSize(Size logical, Size available) =>
      logical * fitScale(logical, available);

  /// Un punto de la pantalla (relativo al lienzo dibujado en [available])
  /// llevado a coordenadas del lienzo lógico.
  static Offset toLogical(Offset screen, Size logical, Size available) =>
      screen / fitScale(logical, available);

  /// Cuántos píxeles por punto lógico hacen falta para que [logical] salga de
  /// [pixelWidth] píxeles de ancho (la resolución de una exportación).
  static double pixelRatioFor(Size logical, double pixelWidth) =>
      pixelWidth / logical.width;
}
