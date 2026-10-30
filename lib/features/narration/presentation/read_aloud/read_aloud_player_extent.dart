import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// **Cuánto ocupa el reproductor anclado** desde el borde de abajo de la
/// pantalla (F47, paso 2), en píxeles lógicos: su borde de arriba, contado
/// desde abajo, con la barra de navegación que tiene debajo incluida. 0 si
/// no se ve.
///
/// Lo publica `ReadAloudOverlay` y lo usa quien muestra avisos abajo, para
/// ponerlos **por encima** del reproductor, como en los reproductores de
/// música: el reproductor nunca tapa un aviso ni su ✕.
@immutable
class PlayerExtent {
  const PlayerExtent({this.current = 0, this.resting = 0});

  /// Lo que ocupa ahora, en la forma que se ve: lo que usa un anfitrión de
  /// avisos que se acomoda solo.
  final double current;

  /// Lo que ocupa en la forma que se eligió —abierto o achicado—, sin el
  /// achicarse pasajero de la Lectura enfocada: no cambia mientras se
  /// desplaza. Lo usan los avisos de Material (`SnackBar`), que suben con el
  /// tema y volverían a armar todas las pantallas en cada cambio.
  final double resting;

  @override
  bool operator ==(Object other) =>
      other is PlayerExtent &&
      other.current == current &&
      other.resting == resting;

  @override
  int get hashCode => Object.hash(current, resting);
}

/// Ver [PlayerExtent]. Cambia cuando el reproductor aparece, se va, se abre o
/// se achica —no mientras se anima—: quien lo lee se acomoda una vez por
/// cambio.
class ReadAloudPlayerExtent extends Notifier<PlayerExtent> {
  @override
  PlayerExtent build() => const PlayerExtent();

  void report(PlayerExtent extent) {
    if (extent != state) state = extent;
  }
}

final readAloudPlayerExtentProvider =
    NotifierProvider<ReadAloudPlayerExtent, PlayerExtent>(
      ReadAloudPlayerExtent.new,
    );

/// Avisa el alto de [child] cada vez que cambia, después de medirlo y fuera
/// de la construcción: el reproductor anclado mide lo que de verdad ocupa
/// —con la letra que se eligió y en su forma de ahora— para publicarlo en
/// [readAloudPlayerExtentProvider].
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
