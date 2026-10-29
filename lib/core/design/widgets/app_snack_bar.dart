import 'package:flutter/material.dart';

/// Lo que dura un aviso de abajo si no se dice otra cosa: lo mismo que
/// `SnackBar`.
const kSnackBarDefaultDuration = Duration(milliseconds: 4000);

/// Hasta cuánto un aviso de abajo es corto: una confirmación que se lee de
/// un vistazo y se va sola. Más que esto, y lleva su ✕ (F43, M1).
const kSnackBarShortLimit = Duration(seconds: 6);

/// Si un aviso de abajo lleva la ✕ para cerrarlo en el acto (F43, M1): el
/// que dura más de [kSnackBarShortLimit], el que tiene un botón y el que se
/// queda hasta que lo cierren. Un aviso con botón se queda por defecto
/// (`SnackBar.persist`), y sin la ✕ la única forma de sacarlo era tocar el
/// botón, que hace otra cosa.
bool snackBarNeedsClose({
  required Duration duration,
  required bool hasAction,
  required bool persist,
}) => hasAction || persist || duration > kSnackBarShortLimit;

/// El aviso de abajo de la app: un `SnackBar` que sabe solo si lleva la ✕
/// ([snackBarNeedsClose]). Las confirmaciones cortas —«Guardado», «Copiado»—
/// siguen siendo un `SnackBar` común, sin ✕; todo aviso con un botón, largo
/// o que se queda es uno de estos. Lo exige el censo de los avisos
/// (`test/core/design/snack_bar_census_test.dart`).
///
/// La ✕ es la de Material: a la derecha, con su «Cerrar» para el lector de
/// pantalla y el color del texto del aviso en cada tema, y cierra el aviso
/// que la muestra. Si el botón y la ✕ no entran al lado del texto —un
/// teléfono angosto, un botón largo—, bajan juntos a un renglón propio, a la
/// derecha (`actionOverflowThreshold`).
class AppSnackBar extends SnackBar {
  AppSnackBar({
    required super.content,
    super.key,
    super.action,
    super.duration = kSnackBarDefaultDuration,
    super.persist,
    bool? showCloseIcon,
    super.behavior,
    super.shape,
    super.padding,
    super.margin,
    super.width,
    super.backgroundColor,
    super.onVisible,
    super.dismissDirection,
  }) : super(
         showCloseIcon:
             showCloseIcon ??
             snackBarNeedsClose(
               duration: duration,
               hasAction: action != null,
               persist: persist ?? action != null,
             ),
       );
}
