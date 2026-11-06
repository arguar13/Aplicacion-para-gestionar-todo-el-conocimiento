import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// **El lugar del reproductor** (F46, paso 5g): las pantallas lo esquivan
/// como esquivan el teclado.
///
/// El reproductor anclado va por encima de todo (`ReadAloudOverlay`), y casi
/// ninguna pantalla sabía que estaba: tapaba el último renglón de Ajustes, el
/// botón flotante de «Nuevo cuaderno», el pie de «Clonación de voz». Ahora
/// las pantallas lo reciben como algo que tapa el pie de la ventana, por
/// `MediaQueryData.viewInsets` —lo mismo que el teclado—: cada `Scaffold`
/// achica su cuerpo hasta el borde de arriba del reproductor, y con eso el
/// final de una lista se puede subir por encima de él, el botón flotante y
/// los avisos quedan arriba, y lo que se centra se centra en lo que queda a
/// la vista. Sin que ninguna pantalla haga nada, y sin importar cómo arma su
/// lista.
///
/// - **Al pie** —una pantalla sin barra de navegación—: el reproductor tapa
///   su alto y el borde seguro de abajo, que lleva debajo
///   ([mediaWithRoomAtBottom], lo que pone `ReadAloudOverlay` sobre el
///   `Navigator`).
/// - **Encima de la barra de navegación**: la pantalla de las pestañas se
///   achica hasta arriba del reproductor, y la barra queda donde está, debajo
///   de él ([mediaWithRoomAboveBar], en `NavigationBarScope`).
/// - **Con el teclado abierto** manda el más alto de los dos, no la suma: el
///   reproductor se hace a un lado y el teclado lo tapa; al cerrarse, el
///   contenido baja hasta donde vuelve el reproductor, sin saltar.
/// - **Sin reproductor**, nada cambia: `MediaQuery` es el de siempre.
///
/// El alto ([height]) es el de la forma que se eligió —abierto o achicado—:
/// la Lectura enfocada lo achica mientras se desplaza, y el lugar no cambia
/// por eso; si siguiera al de cada momento, la lista que se arrastra
/// cambiaría de alto a mitad del arrastre. Cambia, con el mismo andar que el
/// reproductor, cuando se abre, se cierra, se achica o se agranda.
///
/// Este widget lleva ese alto y el `MediaQuery` de afuera ([outer]), sin el
/// lugar del reproductor: con él se sabe si el teclado está abierto de
/// verdad.
class ReadAloudRoom extends InheritedModel<ReadAloudRoomAspect> {
  const ReadAloudRoom({
    required this.height,
    required this.outer,
    required super.child,
    super.key,
  });

  /// El alto del reproductor anclado, sin lo que tenga debajo —la barra de
  /// navegación o el borde seguro—. 0 si no se lee nada.
  final double height;

  /// `MediaQuery` sin el lugar del reproductor.
  final MediaQueryData outer;

  /// Ver [height]; 0 fuera de `ReadAloudOverlay`.
  static double heightOf(BuildContext context) =>
      InheritedModel.inheritFrom<ReadAloudRoom>(
        context,
        aspect: ReadAloudRoomAspect.height,
      )?.height ??
      0;

  /// Ver [outer]; fuera de `ReadAloudOverlay`, el `MediaQuery` de siempre.
  static MediaQueryData outerOf(BuildContext context) =>
      InheritedModel.inheritFrom<ReadAloudRoom>(
        context,
        aspect: ReadAloudRoomAspect.outer,
      )?.outer ??
      MediaQuery.of(context);

  @override
  bool updateShouldNotify(ReadAloudRoom oldWidget) =>
      height != oldWidget.height || outer != oldWidget.outer;

  @override
  bool updateShouldNotifyDependent(
    ReadAloudRoom oldWidget,
    Set<ReadAloudRoomAspect> dependencies,
  ) =>
      (dependencies.contains(ReadAloudRoomAspect.height) &&
          height != oldWidget.height) ||
      (dependencies.contains(ReadAloudRoomAspect.outer) &&
          outer != oldWidget.outer);
}

/// De qué depende quien lee [ReadAloudRoom]: el alto cambia en cada cuadro
/// mientras el reproductor aparece o se va, y quien solo mira el teclado no
/// tiene por qué reconstruirse por eso.
enum ReadAloudRoomAspect { height, outer }

/// [outer] con el reproductor de [height] de alto parado al pie de la
/// pantalla: tapa eso y el borde seguro de abajo, que lleva debajo.
///
/// El borde seguro entra de a poco mientras el reproductor aparece —con los
/// primeros píxeles de [height]—: así lo que lo respeta (`SafeArea`) no salta
/// cuando el lugar llega a 0 o sale de 0, porque el borde pasa de la pantalla
/// al reproductor sin cortes.
MediaQueryData mediaWithRoomAtBottom(MediaQueryData outer, double height) {
  if (height <= 0) return outer;
  final safe = outer.viewPadding.bottom;
  return _covered(outer, height + math.min(height, safe));
}

/// [outer] con el reproductor de [height] de alto parado encima de la barra
/// de navegación, de [barHeight] de alto sin su borde seguro: lo de arriba de
/// la barra se achica hasta el borde de arriba del reproductor. La barra
/// queda donde está, con su borde seguro: un `Scaffold` no la sube por lo
/// que tape abajo.
MediaQueryData mediaWithRoomAboveBar(
  MediaQueryData outer,
  double height, {
  required double barHeight,
}) {
  if (height <= 0) return outer;
  return outer.copyWith(
    viewInsets: outer.viewInsets.copyWith(
      bottom: math.max(
        outer.viewInsets.bottom,
        barHeight + outer.padding.bottom + height,
      ),
    ),
  );
}

/// [outer] con [covered] tapado desde el pie, como lo hace el teclado: el
/// borde seguro que queda debajo de lo tapado ya no cuenta.
MediaQueryData _covered(MediaQueryData outer, double covered) {
  final insets = math.max(outer.viewInsets.bottom, covered);
  return outer.copyWith(
    viewInsets: outer.viewInsets.copyWith(bottom: insets),
    padding: outer.padding.copyWith(
      bottom: math.max(0, outer.viewPadding.bottom - insets),
    ),
  );
}

/// Avisa el alto de [child] cada vez que cambia, después de medirlo y fuera
/// de la construcción: el reproductor anclado mide lo que de verdad ocupa
/// —con la letra que se eligió y en su forma de ahora— para dejarle su lugar
/// ([ReadAloudRoom]).
class HeightProbe extends SingleChildRenderObjectWidget {
  const HeightProbe({required this.onHeight, super.child, super.key});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderHeightProbe(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHeightProbe renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

/// Lo que dibuja [HeightProbe].
class RenderHeightProbe extends RenderProxyBox {
  RenderHeightProbe(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}
