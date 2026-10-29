import 'dart:async';
import 'dart:math' as math;

/// Cuánto crece el tiempo de [big] respecto del de [small] (el cociente), para
/// probar que un trabajo no depende —o depende solo en línea recta— del tamaño
/// del texto sin fijar cuánto tarda en milisegundos: con la máquina cargada los
/// dos tamaños se frenan juntos, y el cociente casi no se mueve.
///
/// Cada uno devuelve los microsegundos que tardó. Se toma lo mejor de [rounds]
/// vueltas, intercaladas —un tirón de la máquina no cae siempre sobre el mismo
/// tamaño—, después de una vuelta de calentamiento. [floor] son los
/// microsegundos que se suman a los dos: un trabajo que no tarda nada no da un
/// cociente enorme por una diferencia de unos pocos microsegundos.
///
/// Con cuatro veces más texto, un trabajo lineal da cerca de 4, uno cuadrático
/// cerca de 16 y uno que mira solo el comienzo, cerca de 1.
Future<double> timeGrowth(
  Future<int> Function() small,
  Future<int> Function() big, {
  int rounds = 3,
  int floor = 2000,
}) async {
  await small();
  await big();
  var bestSmall = await small();
  var bestBig = await big();
  for (var i = 1; i < rounds; i++) {
    bestSmall = math.min(bestSmall, await small());
    bestBig = math.min(bestBig, await big());
  }
  return (bestBig + floor) / (bestSmall + floor);
}

/// Cuántas veces el hilo principal atendió un temporizador mientras corría
/// [work]: si [work] corre en el hilo, el código no lo suelta y da exactamente
/// 0; si corre en otro, el hilo sigue atendiendo y da al menos 1 —con la
/// máquina saturada, a veces solo 1—.
///
/// No mide tiempos: con la máquina saturada, el sistema reparte la CPU en
/// tramos de varios milisegundos y la limpieza de memoria que comparten los
/// hilos puede frenar a los dos, y cualquier cociente de huecos se vuelve
/// ruido. Que el hilo se libere o no, en cambio, no depende de la máquina.
Future<int> ticksDuring(Future<void> Function() work) async {
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 2), (_) => ticks++);
  await work();
  // Se lee antes de volver a soltar el hilo: un tick que llega después ya no
  // es de [work].
  final during = ticks;
  timer.cancel();
  return during;
}

/// Los microsegundos que tarda [work].
Future<int> micros(FutureOr<void> Function() work) async {
  final watch = Stopwatch()..start();
  await work();
  return watch.elapsedMicroseconds;
}
