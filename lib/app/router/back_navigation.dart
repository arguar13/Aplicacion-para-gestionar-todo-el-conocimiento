import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';

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

/// «Atrás» en la pantalla de entrada de una pestaña que no es la Biblioteca
/// lleva a la Biblioteca, y recién desde la Biblioteca sale de la app (F46,
/// paso 5h). Es la pauta de Android para los destinos principales —la que
/// sigue Navigation por defecto—: el de inicio es la puerta, y salir es desde
/// ahí.
///
/// Antes, desde Estudiar › Línea de tiempo —la raíz de su rama—, «atrás»
/// minimizaba la app: la rama no tenía nada que cerrar, el navegador
/// principal tampoco, y go_router le pasaba el gesto al sistema.
///
/// **Cómo.** Envuelve el shell en un `PopScope` de la ruta del shell, en el
/// navegador principal: fuera de la Biblioteca, la ruta no deja que la saquen
/// y, cuando lo intentan, va a la Biblioteca con lo que tenía abierto. Lo que
/// hay encima se cierra antes, como siempre: go_router le da «atrás» primero
/// a la pila de la pestaña —una pantalla, una hoja de abajo—, y lo que el
/// navegador principal tiene arriba del shell —un diálogo, una pantalla sin
/// barra— lo saca él mismo antes de preguntarle a la ruta del shell.
///
/// **Lo que se le dice a Android** sale solo de esto: con la ruta que no deja
/// que la saquen, el navegador principal avisa que «atrás» lo maneja la app
/// aunque no tenga nada que cerrar, también cuando la pestaña acaba de
/// cerrar lo suyo y avisó que no (`reportBackHandling` lo deja pasar). En la
/// Biblioteca, sin nada abierto, el aviso es «no», y el sistema puede mostrar
/// el gesto atrás predictivo de salir.
class BackToLibrary extends StatelessWidget {
  const BackToLibrary({
    required this.navigationShell,
    required this.child,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final Widget child;

  static final _library = ShellBranch.library.index;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: navigationShell.currentIndex == _library,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) navigationShell.goBranch(_library);
    },
    child: child,
  );
}
