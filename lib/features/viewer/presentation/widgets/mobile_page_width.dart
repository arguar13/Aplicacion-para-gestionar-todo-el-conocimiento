import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_mobile.dart';

/// Una página web con el ancho de un teléfono, centrada, también en una
/// pantalla ancha (F45, paso 4, decisión D): en la computadora, la página de
/// Procesado se ve como en el teléfono, dentro de su tarjeta, y no estirada a
/// lo ancho de la ventana. En un teléfono no cambia nada: ya es más angosto.
///
/// A los costados, el fondo de la tarjeta y una línea tenue que marca dónde
/// termina la página.
class MobilePageWidth extends StatelessWidget {
  const MobilePageWidth({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= kMobilePageWidth) return child;
        final line = Theme.of(context).colorScheme.outlineVariant;
        return Center(
          child: DecoratedBox(
            key: const Key('mobile-page-width'),
            decoration: BoxDecoration(
              border: Border.symmetric(vertical: BorderSide(color: line)),
            ),
            child: SizedBox(width: kMobilePageWidth, child: child),
          ),
        );
      },
    );
  }
}
