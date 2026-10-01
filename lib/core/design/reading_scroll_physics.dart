import 'package:flutter/widgets.dart';

/// Cuánto más lejos llega un arrastre rápido al leer que en una lista.
const readingFlingBoost = 1.5;

/// La física de desplazamiento de lo que se lee de corrido —un PDF, las
/// páginas de un libro o de un documento, el modo lectura—: la de la
/// plataforma, con el arrastre rápido [readingFlingBoost] veces más
/// enérgico.
///
/// Para pasar hojas de un libro hace falta más recorrido por gesto que para
/// moverse en una lista de diez elementos: con la física de siempre, pasar
/// diez páginas de un PDF pedía una docena de arrastres (pedido del usuario,
/// "tiene muy poca sensibilidad"). El arrastre lento sigue al dedo igual que
/// antes: solo cambia lo que pasa al soltar con impulso.
class ReadingScrollPhysics extends ScrollPhysics {
  const ReadingScrollPhysics({super.parent});

  @override
  ReadingScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ReadingScrollPhysics(parent: buildParent(ancestor));

  @override
  double get maxFlingVelocity => super.maxFlingVelocity * readingFlingBoost;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(position, velocity * readingFlingBoost);
}
