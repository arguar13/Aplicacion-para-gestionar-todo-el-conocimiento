import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Avisa dónde quedó el borde de arriba de [child] en la pantalla —su `y`
/// global— cada vez que se acomoda o se dibuja, si cambió.
///
/// Mide en el dibujo, no en la construcción: lo que sube con el teclado o se
/// desliza con el dedo se vuelve a dibujar sin reconstruirse. Y al terminar
/// el cuadro en que se acomodó: lo que todavía no se ve —un aviso que llega
/// transparente— no se dibuja, pero ya ocupa su lugar.
///
/// [onTop] puede llegar en medio del dibujo: quien lo use para cambiar
/// estado lo hace al final del cuadro (`addPostFrameCallback`), no ahí mismo.
class TopEdgeProbe extends SingleChildRenderObjectWidget {
  const TopEdgeProbe({required this.onTop, super.child, super.key});

  final ValueChanged<double> onTop;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTopEdgeProbe(onTop);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTopEdgeProbe renderObject,
  ) {
    renderObject.onTop = onTop;
  }
}

/// El que mide por [TopEdgeProbe].
class RenderTopEdgeProbe extends RenderProxyBox {
  RenderTopEdgeProbe(this.onTop);

  ValueChanged<double> onTop;
  double? _reported;
  var _checkScheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    // Recién al final del cuadro se sabe dónde quedó: los de arriba todavía
    // no lo ubicaron.
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (attached) _check();
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _check();
  }

  void _check() {
    final top = localToGlobal(Offset.zero).dy;
    if (top == _reported) return;
    _reported = top;
    onTop(top);
  }
}
