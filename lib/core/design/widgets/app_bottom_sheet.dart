import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// **La única puerta para abrir un panel de abajo** (F46, paso 5j, decisión
/// 1b del dueño): se abre en el navegador de la raíz, encima de la barra de
/// pestañas, y su sombreado tapa la pantalla entera, como pide Material 3.
///
/// Antes cada pantalla llamaba a `showModalBottomSheet` por su cuenta, y
/// ninguna pedía el navegador de la raíz: abierto desde una pestaña, el panel
/// quedaba en el navegador de esa rama, arriba de la barra, y la barra seguía
/// sin sombrear y se podía tocar —se cambiaba de pestaña con el panel abierto—.
/// Lo vigila el censo de los paneles
/// (`test/core/design/bottom_sheet_census_test.dart`).
///
/// Además fija lo que repetía cada llamada:
/// - **el alto lo pone lo de adentro** (`isScrollControlled`): un panel corto
///   mide lo que mide, y uno largo —o con la letra al doble— llega hasta
///   arriba en vez de cortarse en los nueve dieciséis de la pantalla.
///   [maxHeightFactor] lo topea en una parte del alto de la pantalla;
/// - **no se mete debajo de la barra del sistema** ni arriba ni abajo
///   (`useSafeArea` y el borde seguro de abajo, ver [AppBottomSheetFrame]);
/// - **el teclado no lo tapa**: el panel sube con él;
/// - **la manija** arriba ([showDragHandle]);
/// - **sin animación** con «quitar animaciones» del sistema;
/// - la forma y el color son los de Material 3 —esquinas de 28 arriba, el
///   fondo `surfaceContainerLow`—: no hace falta pedirlos.
///
/// **Lo que ve el panel.** En la raíz, el panel no queda debajo de lo que hay
/// entre la raíz y la rama —el `Scaffold` de las pestañas, el lugar que le
/// deja al reproductor—. Los temas (`Theme`, `DefaultTextStyle`…) los lleva
/// Flutter de donde se abrió, y los proveedores también: si [context] ve un
/// `ProviderScope` propio, con lo que sobrescribe, el panel ve el mismo
/// contenedor de Riverpod, no el de la raíz.
///
/// **Cerrarlo.** El contexto que recibe [builder] es el del panel: con
/// `Navigator.of(context).pop(…)` se cierra él y devuelve lo que se elija.
/// «Atrás» de Android lo cierra antes que cualquier otra cosa —go_router no
/// mira la pestaña mientras hay algo encima del shell en la raíz—.
///
/// [ownSurface] es para un panel que dibuja su propia superficie —otro color,
/// su encabezado fijo—: el del panel es transparente, sin manija, y el borde
/// seguro de abajo lo pone él, adentro de su superficie.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  double? maxHeightFactor,
  BoxConstraints? constraints,
  bool ownSurface = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final container = _containerOf(context);
  // Solo si es otro: el de la raíz ya lo ve el panel.
  final scoped =
      container != null &&
          !identical(container, _containerOf(navigator.context))
      ? container
      : null;

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: !ownSurface && showDragHandle,
    backgroundColor: ownSurface ? Colors.transparent : null,
    constraints: constraints,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (sheetContext) {
      final Widget sheet = AppBottomSheetFrame(
        maxHeightFactor: maxHeightFactor,
        bottomSafeArea: !ownSurface,
        child: Builder(builder: builder),
      );
      return scoped == null
          ? sheet
          : UncontrolledProviderScope(container: scoped, child: sheet);
    },
  );
}

/// El contenedor de Riverpod que ve [context], o `null` si no hay ninguno.
ProviderContainer? _containerOf(BuildContext context) {
  final scope =
      context
              .getElementForInheritedWidgetOfExactType<
                UncontrolledProviderScope
              >()
              ?.widget
          as UncontrolledProviderScope?;
  return scope?.container;
}

/// Lo de adentro de un panel de [showAppBottomSheet]: el teclado, el borde
/// seguro de abajo y el alto máximo, una vez para todos.
///
/// - **El teclado**: el panel le deja abajo lo que tapa
///   (`MediaQuery.viewInsets`), así el campo que se escribe y lo que se filtra
///   quedan a la vista. Lo de adentro ya no lo ve: un panel que también lo
///   dejara lo dejaría dos veces.
/// - **El borde seguro de abajo** —la barra de gestos—, con
///   [bottomSafeArea]: la superficie del panel llega hasta el borde de la
///   pantalla y lo de adentro queda arriba de la barra. Con el teclado
///   abierto no hay borde: lo tapa el teclado. Lo de adentro que también pida
///   `SafeArea` no lo suma otra vez.
/// - **El alto máximo**, con [maxHeightFactor]: una parte del alto de la
///   pantalla.
class AppBottomSheetFrame extends StatelessWidget {
  const AppBottomSheetFrame({
    required this.child,
    this.maxHeightFactor,
    this.bottomSafeArea = true,
    super.key,
  }) : assert(
         maxHeightFactor == null ||
             (maxHeightFactor > 0 && maxHeightFactor <= 1),
         'El alto máximo es una parte del alto de la pantalla.',
       );

  final Widget child;
  final double? maxHeightFactor;
  final bool bottomSafeArea;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    var content = child;
    if (maxHeightFactor case final factor?) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * factor),
        child: content,
      );
    }
    if (bottomSafeArea) {
      content = SafeArea(top: false, left: false, right: false, child: content);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: content,
      ),
    );
  }
}
