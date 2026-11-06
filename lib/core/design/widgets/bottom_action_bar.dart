import 'package:flutter/material.dart';

/// La barra con el botón de una pantalla, al pie —su
/// `Scaffold.bottomNavigationBar`— (F46, paso 5g): «Elegir temas», «Guardar
/// las preguntas»...
///
/// Queda a la vista **por encima de lo que tape el pie de la ventana**: el
/// reproductor de lectura —que las pantallas esquivan como al teclado, ver
/// `ReadAloudRoom`— o el teclado. Un `Scaffold` achica su cuerpo por eso,
/// pero deja su `bottomNavigationBar` abajo, debajo de lo que tapa: esta
/// barra se para encima. Con el borde seguro de abajo.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    required this.padding,
    required this.child,
    super.key,
  });

  /// Alrededor de [child], adentro del borde seguro.
  final EdgeInsetsGeometry padding;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(padding: padding, child: child),
    ),
  );
}
