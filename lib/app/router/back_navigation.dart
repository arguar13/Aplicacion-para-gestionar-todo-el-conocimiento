import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Le dice a Android si el gesto o el botón "atrás" lo maneja la app —volver
/// a la pantalla anterior— o el sistema —minimizarla—, mirando **todos** los
/// navegadores de go_router, no solo el que avisó.
///
/// Desde Android 13, y a la fuerza desde Android 16, el sistema decide qué
/// hace "atrás" antes de preguntarle nada a la app: Flutter le avisa cada vez
/// que cambia la pila con `SystemNavigator.setFrameworkHandlesBack`. Pero
/// cada `Navigator` avisa por su cuenta, y el último en hablar gana. La app
/// tiene uno principal —diálogos, pantallas sueltas— y uno por pestaña —la
/// biblioteca y el elemento abierto adentro—. Al cerrarse un diálogo sobre
/// un elemento —"Volver a extraer", "Transcribir"—, el principal avisaba "no
/// tengo nada que cerrar", sin contar que la pestaña sí podía volver a la
/// biblioteca, y el gesto siguiente minimizaba la app. Medido en el teléfono
/// del usuario (HyperOS 3, Android 16): el registro del sistema muestra el
/// aviso cambiar a "no" en el instante en que se cerró el diálogo, y el
/// gesto siguiente terminar en `moveTaskToBack`.
///
/// Para `MaterialApp.onNavigationNotification`: hace lo mismo que el manejo
/// por defecto de Flutter, con lo que puede volver go_router —que recorre el
/// navegador principal y el de la pestaña abierta— sumado al aviso.
bool reportBackHandling(GoRouter router, NavigationNotification notification) {
  switch (WidgetsBinding.instance.lifecycleState) {
    case null:
    case AppLifecycleState.detached:
      // Igual que Flutter: con la app sin arrancar no se le avisa nada al
      // sistema.
      return true;
    case AppLifecycleState.inactive:
    case AppLifecycleState.resumed:
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
      SystemNavigator.setFrameworkHandlesBack(
        notification.canHandlePop || router.canPop(),
      );
      return true;
  }
}
